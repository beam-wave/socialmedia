defmodule Socialmedia.Posts do
  @moduledoc """
  Post lifecycle:

      planned → generating → rendering → needs_review → approved → publishing → published

  `failed` and `rejected` are side exits. Only `approved` posts are ever published;
  anything not approved by its slot time is rejected by `Socialmedia.Workers.Expirer`.
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

  def get_post!(id), do: Post |> Repo.get!(id) |> Repo.preload([:channel, :schedule])

  def get_post(id), do: Post |> Repo.get(id) |> Repo.preload([:channel, :schedule])

  @doc "Posts for one channel between two UTC datetimes, ordered by slot."
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

  @doc "Published posts so far for the channel (used for streak numbers)."
  def published_count(%Channel{id: channel_id}) do
    Repo.aggregate(
      from(p in Post, where: p.channel_id == ^channel_id and p.status == "published"),
      :count
    )
  end

  ## Planning

  @doc "Inserts a planned post for a slot unless one exists. Returns {:ok, post} or {:ok, :exists}."
  def ensure_planned(attrs) do
    %Post{}
    |> Post.changeset(Map.merge(attrs, %{status: "planned", slot_at: attrs.scheduled_at}))
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:schedule_id, :slot_at])
    |> case do
      {:ok, %Post{id: nil}} -> {:ok, :exists}
      {:ok, post} -> broadcast({:ok, post})
      error -> error
    end
  end

  @doc """
  Admin typed the facts for a result post. Queues it for the agent right away
  (as a new revision, so a version in flight is ignored).
  """
  def enter_facts(%Post{} = post, facts) when is_map(facts) do
    if Post.final?(post) or post.status == "publishing" do
      {:error, :final}
    else
      cancel_jobs(post, Workers.Publish)

      post
      |> mark("planned", %{
        facts: facts,
        generate_at: now(),
        gen_rev: post.gen_rev + 1,
        approved_at: nil,
        error: nil
      })
      |> tap(fn _ -> request_sync() end)
    end
  end

  @doc "Inserts a post that isn't from a slot (e.g. a result linked to its fixture)."
  def create_linked(attrs) do
    %Post{} |> Post.changeset(attrs) |> Repo.insert() |> broadcast()
  end

  @doc """
  The agent asked to try later (e.g. the match isn't over). Re-queues the post
  as a new revision and keeps review time before it goes out.
  """
  def retry_later(%Post{} = post, minutes, note) do
    generate_at = DateTime.utc_now() |> DateTime.add(minutes * 60) |> DateTime.truncate(:second)
    earliest = DateTime.add(generate_at, 45 * 60)

    scheduled_at =
      if DateTime.compare(post.scheduled_at, earliest) == :lt,
        do: earliest,
        else: post.scheduled_at

    mark(post, "planned", %{
      generate_at: generate_at,
      scheduled_at: scheduled_at,
      gen_rev: post.gen_rev + 1,
      retries: post.retries + 1,
      error: note
    })
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
            p.status in ["planned", "render_requested", "needs_review", "failed"]
    )
    |> Enum.each(&reject(&1, "fixture_rejected"))
  end

  @doc "Restore a rejected post whose slot is still ahead."
  def restore(%Post{status: "rejected"} = post) do
    if DateTime.compare(post.scheduled_at, DateTime.utc_now()) == :gt do
      status = if post.slide_paths == [], do: "planned", else: "needs_review"
      mark(post, status, %{reject_reason: nil})
    else
      {:error, :slot_passed}
    end
  end

  def restore(%Post{}), do: {:error, :not_rejected}

  @doc "Ask the agent to write this post again (picked up by the next content poll)."
  def regenerate(%Post{} = post, note \\ nil) do
    if Post.reviewable?(post) and future?(post) do
      cancel_jobs(post)

      post
      |> mark("planned", %{
        admin_note: note,
        error: nil,
        approved_at: nil,
        generate_at: now(),
        gen_rev: post.gen_rev + 1
      })
      |> tap(fn _ -> request_sync() end)
    else
      {:error, :not_reviewable}
    end
  end

  @doc """
  Admin edits the template data and/or caption. A data change asks the content
  node to re-render the slides (the renderer rewrites the caption from data, so
  edit the caption after the re-render finishes).
  """
  def update_content(%Post{} = post, attrs) do
    if Post.reviewable?(post) and post.data do
      cancel_jobs(post, Workers.Publish)

      rerender? = Map.get(attrs, :data, post.data) != post.data

      extra =
        if rerender?,
          do: %{status: "render_requested", gen_rev: post.gen_rev + 1},
          else: %{status: "needs_review"}

      result =
        post
        |> Post.changeset(attrs |> Map.merge(extra) |> Map.put(:approved_at, nil))
        |> Repo.update()
        |> broadcast()

      if rerender?, do: request_sync()
      result
    else
      {:error, :not_reviewable}
    end
  end

  @doc "Publish an approved post right away instead of waiting for its slot."
  def publish_now(%Post{status: "approved"} = post) do
    cancel_jobs(post, Workers.Publish)
    Workers.Publish.enqueue(post, now: true)
  end

  def publish_now(%Post{}), do: {:error, :not_approved}

  ## Helpers

  # Publish plan.json soon instead of waiting for the next cron tick.
  defp request_sync, do: Workers.SyncBus.enqueue()

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
