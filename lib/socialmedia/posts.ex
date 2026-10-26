defmodule Socialmedia.Posts do
  @moduledoc """
  Post lifecycle:

      creating → uploaded → (Pull) needs_review → approved → publishing → published

  `creating` and `uploaded` live on the machine that made the post; a Pull
  brings it in as `needs_review`. `failed` and `rejected` are side exits. Only
  `approved` posts are ever published. Nothing is dropped automatically: the
  admin rejects what they don't want.
  """
  import Ecto.Query
  alias Socialmedia.Repo
  alias Socialmedia.Posts.Post
  alias Socialmedia.Channels.Channel
  alias Socialmedia.Workers

  @topic "posts"

  def subscribe, do: Phoenix.PubSub.subscribe(Socialmedia.PubSub, @topic)

  defp broadcast({:ok, %Post{} = post} = result) do
    Phoenix.PubSub.broadcast(Socialmedia.PubSub, @topic, {:post_updated, post})
    result
  end

  defp broadcast(other), do: other

  ## Queries

  def get_post!(id), do: Post |> Repo.get!(id) |> Repo.preload(:channel)

  def get_post(id), do: Post |> Repo.get(id) |> Repo.preload(:channel)

  @doc "Posts for one channel between two UTC datetimes, ordered by time."
  def list_posts(%Channel{id: channel_id}, %DateTime{} = from, %DateTime{} = to) do
    Repo.all(
      from p in Post,
        where: p.channel_id == ^channel_id and p.scheduled_at >= ^from and p.scheduled_at < ^to,
        order_by: p.scheduled_at
    )
  end

  @doc "Counts per status for each channel inside a window, e.g. %{channel_id => %{\"needs_review\" => 2}}."
  def status_counts(%DateTime{} = from, %DateTime{} = to) do
    Repo.all(
      from p in Post,
        where: p.scheduled_at >= ^from and p.scheduled_at < ^to,
        group_by: [p.channel_id, p.status],
        select: {p.channel_id, p.status, count(p.id)}
    )
    |> Enum.reduce(%{}, fn {cid, status, n}, acc ->
      Map.update(acc, cid, %{status => n}, &Map.put(&1, status, n))
    end)
  end

  @doc "Data of the channel's most recent generated posts, newest first. Fed to the agent to avoid repeats."
  def recent_data(%Channel{id: channel_id}, limit \\ 30) do
    Repo.all(
      from p in Post,
        where: p.channel_id == ^channel_id and not is_nil(p.data) and p.status != "rejected",
        order_by: [desc: p.scheduled_at],
        limit: ^limit,
        select: p.data
    )
  end

  @doc """
  Next Day N / quote N for a series channel (one with `base_data.series_start`):
  one more than the highest number held, or `series_start.n` for the first
  post. Rejected and failed posts don't hold one. Nil for other channels.
  """
  def next_series_number(%Channel{id: channel_id, base_data: base}) do
    case base do
      %{"series_start" => start} ->
        last =
          Repo.one(
            from p in Post,
              where: p.channel_id == ^channel_id and p.status not in ["rejected", "failed"],
              select: max(p.series_number)
          )

        if last, do: last + 1, else: (is_map(start) && start["n"]) || 1

      _ ->
        nil
    end
  end

  @doc "Published posts so far for the channel (used for streak numbers)."
  def published_count(%Channel{id: channel_id}) do
    Repo.aggregate(
      from(p in Post, where: p.channel_id == ^channel_id and p.status == "published"),
      :count
    )
  end

  ## Creating

  @doc "Inserts a post (a new `content_key` is set unless given)."
  def create_post(attrs) do
    %Post{} |> Post.changeset(attrs) |> Repo.insert() |> broadcast()
  end

  @doc "Inserts a result post linked to its fixture; it waits for the admin's facts."
  def create_linked(attrs), do: create_post(attrs)

  @doc """
  Admin entered the scores for a result post. The app builds its data (no
  agent) and renders it right away. Returns `{:error, message}` for bad scores.
  """
  def enter_facts(%Post{} = post, facts) when is_map(facts) do
    post = Repo.preload(post, [:parent, :channel])

    cond do
      Post.final?(post) or post.status == "publishing" ->
        {:error, :final}

      true ->
        with {:ok, data} <- Socialmedia.Content.MatchResult.build(post, facts) do
          remake(post, %{facts: facts, data: data}, render_only: true)
        end
    end
  end

  # Back to `creating` and a new Produce job (any publish job is dropped).
  # A failed post gave up its number, so it takes the next free one.
  defp remake(post, attrs, opts \\ []) do
    cancel_jobs(post)

    attrs =
      if post.status == "failed" and post.series_number,
        do:
          Map.put(attrs, :series_number, next_series_number(Repo.preload(post, :channel).channel)),
        else: attrs

    Repo.transact(fn ->
      with {:ok, post} <-
             post
             |> Post.changeset(
               Map.merge(attrs, %{status: "creating", approved_at: nil, error: nil})
             )
             |> Repo.update(),
           {:ok, _job} <- Workers.Produce.enqueue(post, opts) do
        {:ok, post}
      end
    end)
    |> broadcast()
  end

  ## Pipeline transitions (called by workers)

  def mark(%Post{} = post, status, attrs \\ %{}) do
    post
    |> Post.changeset(Map.put(attrs, :status, status))
    |> Repo.update()
    |> broadcast()
  end

  def fail(%Post{} = post, error) do
    mark(post, "failed", %{error: format_error(error)})
  end

  defp format_error(e) when is_binary(e), do: e
  defp format_error(e), do: inspect(e, limit: 50, printable_limit: 2000)

  ## Admin actions

  @doc """
  The admin's "Schedule" button: save caption/time edits, then approve.
  `attrs` may hold `:caption` and `:scheduled_at` (UTC).
  """
  def schedule(%Post{status: "needs_review"} = post, attrs) do
    changes = Map.take(attrs, [:caption, :scheduled_at])

    with :ok <- check_future(Map.get(changes, :scheduled_at, post.scheduled_at)),
         {:ok, post} <- post |> Post.changeset(changes) |> Repo.update() do
      approve(post)
    end
  end

  def schedule(%Post{}, _), do: {:error, :not_reviewable}

  @doc "Move a post to another time. An approved post's publish job moves with it."
  def reschedule(%Post{} = post, %DateTime{} = at) do
    at = DateTime.truncate(at, :second)

    cond do
      Post.final?(post) or post.status == "publishing" ->
        {:error, :final}

      check_future(at) != :ok ->
        {:error, :time_passed}

      post.status == "approved" ->
        cancel_jobs(post, Workers.Publish)

        Repo.transact(fn ->
          with {:ok, post} <- post |> Post.changeset(%{scheduled_at: at}) |> Repo.update(),
               {:ok, _} <- Workers.Publish.enqueue(post) do
            {:ok, post}
          end
        end)
        |> broadcast()

      true ->
        post |> Post.changeset(%{scheduled_at: at}) |> Repo.update() |> broadcast()
    end
  end

  defp check_future(at) do
    if DateTime.compare(at, DateTime.utc_now()) == :gt, do: :ok, else: {:error, :time_passed}
  end

  @doc "Approve a post that is ready for review. Publishing is queued for its scheduled time."
  def approve(%Post{status: "needs_review"} = post) do
    if DateTime.compare(post.scheduled_at, DateTime.utc_now()) == :lt do
      {:error, :slot_passed}
    else
      Repo.transact(fn ->
        with {:ok, post} <-
               post
               |> Post.changeset(%{status: "approved", approved_at: now(), error: nil})
               |> Repo.update(),
             {:ok, _job} <- Workers.Publish.enqueue(post) do
          {:ok, post}
        end
      end)
      |> broadcast()
    end
  end

  def approve(%Post{}), do: {:error, :not_reviewable}

  @doc "Move an approved post back to review and drop its publish job."
  def unapprove(%Post{status: "approved"} = post) do
    cancel_jobs(post, Workers.Publish)
    mark(post, "needs_review", %{approved_at: nil})
  end

  def unapprove(%Post{}), do: {:error, :not_approved}

  def reject(%Post{} = post, reason \\ "rejected_by_admin") do
    if Post.final?(post) or post.status == "publishing" do
      {:error, :final}
    else
      cancel_jobs(post)

      with {:ok, rejected} <- mark(post, "rejected", %{reject_reason: reason}) do
        reject_linked_result(rejected)
        {:ok, rejected}
      end
    end
  end

  # A result post scores the fixture's predictions, so it goes when the fixture goes
  defp reject_linked_result(%Post{id: id}) do
    Repo.all(
      from p in Post,
        where:
          p.parent_id == ^id and
            p.status in ["planned", "creating", "uploaded", "needs_review", "failed"]
    )
    |> Enum.each(&reject(&1, "fixture_rejected"))
  end

  @doc "Restore a rejected post whose time is still ahead."
  def restore(%Post{status: "rejected"} = post) do
    if DateTime.compare(post.scheduled_at, DateTime.utc_now()) == :gt do
      cond do
        post.slide_paths != [] ->
          mark(post, "needs_review", %{reject_reason: nil})

        post.post_type == "result" and is_nil(post.facts) ->
          mark(post, "planned", %{reject_reason: nil})

        true ->
          remake(post, %{reject_reason: nil})
      end
    else
      {:error, :slot_passed}
    end
  end

  def restore(%Post{}), do: {:error, :not_rejected}

  @doc "Ask the agent to write this post again, here and now (same content_key)."
  def regenerate(%Post{} = post, note \\ nil) do
    if Post.reviewable?(post) and future?(post),
      do: remake(post, %{admin_note: note}),
      else: {:error, :not_reviewable}
  end

  @doc """
  Admin edits the template data or the caption. A data change re-renders the
  slides here (the renderer rewrites the caption from data, so edit the
  caption after the re-render finishes).
  """
  def update_content(%Post{} = post, attrs) do
    rerender? = Map.get(attrs, :data, post.data) != post.data

    cond do
      not Post.reviewable?(post) or is_nil(post.data) ->
        {:error, :not_reviewable}

      rerender? ->
        remake(post, %{data: attrs.data}, render_only: true)

      # Its manifest is already in S3; edit the caption after the Pull
      post.status in ~w(creating uploaded) ->
        {:error, :not_reviewable}

      true ->
        cancel_jobs(post, Workers.Publish)

        post
        |> Post.changeset(Map.merge(attrs, %{status: "needs_review", approved_at: nil}))
        |> Repo.update()
        |> broadcast()
    end
  end

  @doc "Publish an approved post right away instead of waiting for its time."
  def publish_now(%Post{status: "approved"} = post) do
    cancel_jobs(post, Workers.Publish)
    Workers.Publish.enqueue(post, now: true)
  end

  def publish_now(%Post{}), do: {:error, :not_approved}

  ## Helpers

  @doc "Cancels queued jobs for a post (all workers, or just one)."
  def cancel_jobs(%Post{id: id}, worker \\ nil) do
    query =
      from j in Oban.Job,
        where: fragment("?->>'post_id' = ?", j.args, ^Integer.to_string(id)),
        where: j.state in ["available", "scheduled", "retryable"]

    query = if worker, do: where(query, [j], j.worker == ^inspect(worker)), else: query
    Oban.cancel_all_jobs(query)
  end

  defp future?(%Post{scheduled_at: at}), do: DateTime.compare(at, DateTime.utc_now()) == :gt

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
