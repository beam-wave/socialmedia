defmodule Socialmedia.Workers.Publish do
  @moduledoc """
  Posts an approved post to Instagram at its time: the photo/carousel post, the
  animated reel, or both (per `post.formats`). Each part's media id is saved as
  soon as it is live, so a retry never posts the same part twice. For a channel
  in dry-run mode nothing is sent; the post is marked published with a dry-run note.
  """
  use Oban.Worker,
    queue: :publish,
    max_attempts: 3,
    unique: [keys: [:post_id], period: :infinity, states: :incomplete]

  require Logger
  alias Socialmedia.Posts
  alias Socialmedia.Posts.Post
  alias Socialmedia.Instagram.Publisher

  def enqueue(post, opts \\ []) do
    sched = if opts[:now], do: [], else: [scheduled_at: post.scheduled_at]
    %{post_id: post.id} |> new(sched) |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"post_id" => id}, attempt: attempt, max_attempts: max}) do
    case Posts.get_post(id) do
      %{status: status} = post when status in ["approved", "publishing"] ->
        {:ok, post} = Posts.mark(post, "publishing")
        do_publish(post, attempt, max)

      nil ->
        {:cancel, :post_deleted}

      post ->
        {:cancel, "post is #{post.status}, not approved"}
    end
  end

  defp do_publish(post, attempt, max) do
    if not post.channel.dry_run do
      with {:ok, post} <- photo_part(post),
           {:ok, post} <- reel_part(post) do
        Posts.mark(post, "published", %{published_at: now(), error: nil})
        :ok
      else
        {:error, reason} when attempt < max ->
          Posts.mark(post, "approved", %{error: "publish attempt #{attempt}: #{inspect(reason)}"})
          {:error, reason}

        {:error, reason} ->
          Posts.fail(post, "publish failed: #{inspect(reason)}")
          {:cancel, reason}
      end
    else
      Logger.info("dry-run publish of post #{post.id}")

      Posts.mark(post, "published", %{
        published_at: now(),
        error: nil,
        permalink: nil,
        agent_log: append(post.agent_log, "Dry run: nothing sent to Instagram.")
      })

      :ok
    end
  end

  defp photo_part(%Post{ig_media_id: id} = post) when is_binary(id), do: {:ok, post}

  defp photo_part(post) do
    if Post.photo?(post) do
      with {:ok, %{ig_media_id: mid, permalink: link}} <- Publisher.publish(post),
           do: Posts.mark(post, "publishing", %{ig_media_id: mid, permalink: link})
    else
      {:ok, post}
    end
  end

  defp reel_part(%Post{reel_media_id: id} = post) when is_binary(id), do: {:ok, post}

  defp reel_part(post) do
    if Post.reel?(post) do
      with {:ok, r} <- Publisher.publish_reel(post),
           do: Posts.mark(post, "publishing", r)
    else
      {:ok, post}
    end
  end

  defp append(nil, s), do: s
  defp append(log, s), do: log <> "\n" <> s

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
