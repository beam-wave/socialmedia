defmodule Socialmedia.Content do
  @moduledoc """
  Making content and moving it between machines through S3. Every step is a
  button, on any machine:

    * **Create** (channel page): one click makes one post. Its `Produce` job
      runs Claude + the renderer, uploads the slides to `content/<key>/`, then
      writes the manifest `inbox/<key>.json` last, so a manifest always points
      at complete uploads. The post is then `uploaded`.
    * **Pull** (Content page): imports every manifest in `inbox/` as a post
      ready to schedule, then removes the manifest. **Delete** drops a
      manifest and its slides without importing.

  `content_key` names the post on every machine, so pulling on the machine
  that made it, or pulling a regenerated version, updates the same post.
  """
  import Ecto.Query
  require Logger
  alias Socialmedia.{Channels, Posts, Repo, Storage}
  alias Socialmedia.Channels.Channel
  alias Socialmedia.Posts.Post
  alias Socialmedia.Content.Matches
  alias Socialmedia.Workers.Produce

  # A pulled post whose time has passed gets this much time to be reviewed
  @review_minutes 60

  ## Create

  @doc """
  Creates one post and queues its Produce job. `attrs`: `:post_type`,
  `:scheduled_at` (UTC) and an optional `:admin_note`.
  """
  def create(%Channel{} = channel, attrs) do
    slot = Channels.slot_for(channel, attrs.post_type)

    Repo.transact(fn ->
      with {:ok, post} <-
             Posts.create_post(%{
               channel_id: channel.id,
               schedule_id: slot && slot.id,
               post_type: attrs.post_type,
               scheduled_at: attrs.scheduled_at,
               admin_note: attrs[:admin_note],
               status: "creating"
             }),
           {:ok, _job} <- Produce.enqueue(post) do
        {:ok, post}
      end
    end)
  end

  @doc "Uploads a finished post (slides, then manifest) and marks it `uploaded`."
  def upload(%Post{} = post, %{data: data, caption: caption, slides: files} = result) do
    post = Repo.preload(post, [:channel, :parent])

    scheduled_at =
      if post.post_type == "fixture",
        do: Matches.fixture_time(data, post.scheduled_at),
        else: post.scheduled_at

    keys =
      for file <- files do
        key = "content/#{post.content_key}/#{Path.basename(file)}"
        :ok = Storage.put_file(key, file, "image/jpeg")
        key
      end

    # A regenerated post can have fewer slides than before
    Enum.each(post.slide_paths -- keys, &Storage.delete/1)

    :ok =
      Storage.put_json(manifest_key(post.content_key), %{
        key: post.content_key,
        channel: post.channel.handle,
        post_type: post.post_type,
        scheduled_at: scheduled_at,
        parent_key: post.parent && post.parent.content_key,
        facts: post.facts,
        admin_note: post.admin_note,
        data: data,
        caption: caption,
        sources: result[:sources] || [],
        notes: result[:notes],
        slides: keys,
        made_at: DateTime.utc_now()
      })

    with {:ok, post} <-
           Posts.mark(post, "uploaded", %{
             scheduled_at: scheduled_at,
             data: data,
             caption: caption,
             sources: result[:sources] || post.sources,
             agent_log: result[:notes] || post.agent_log,
             slide_paths: keys,
             error: nil
           }) do
      if post.post_type == "fixture", do: Matches.after_fixture(post)
      {:ok, post}
    end
  end

  ## Pull

  def manifest_key(content_key), do: "inbox/#{content_key}.json"

  @doc "Manifests waiting in S3, oldest first. Each has a `\"manifest\"` key (its S3 key)."
  def manifests do
    {:ok, keys} = Storage.list("inbox/")

    for key <- keys,
        String.ends_with?(key, ".json"),
        {:ok, m} <- [Storage.get_json(key)] do
      Map.put(m, "manifest", key)
    end
    |> Enum.sort_by(&(&1["made_at"] || ""))
  end

  @doc "Pulls every manifest. Returns how many posts were imported."
  def pull_all, do: Enum.count(manifests(), &match?({:ok, %Post{}}, pull(&1)))

  @doc """
  Imports one manifest as a post ready to schedule, then removes the manifest.
  A post that is already scheduled or live here is left alone.
  """
  def pull(%{"manifest" => mkey} = m) do
    with %Channel{} = ch <- Channels.get_channel_by_handle(m["channel"]) || {:error, :no_channel},
         {:ok, at, _} <- DateTime.from_iso8601(m["scheduled_at"] || "") do
      attrs = %{
        channel_id: ch.id,
        post_type: m["post_type"],
        scheduled_at: review_time(at),
        parent_id: parent_id(m["parent_key"]),
        facts: m["facts"],
        admin_note: m["admin_note"],
        data: m["data"],
        caption: m["caption"],
        sources: m["sources"] || [],
        agent_log: m["notes"],
        slide_paths: m["slides"] || [],
        error: nil
      }

      result =
        case Repo.get_by(Post, content_key: m["key"]) do
          nil ->
            Posts.create_post(Map.merge(attrs, %{content_key: m["key"], status: "needs_review"}))

          %Post{status: s} = post when s in ~w(planned creating uploaded needs_review failed) ->
            Posts.mark(post, "needs_review", attrs)

          %Post{} = post ->
            Logger.info("pull: #{m["key"]} is already #{post.status} here, kept as is")
            {:ok, :kept}
        end

      Storage.delete(mkey)
      result
    else
      {:error, :no_channel} -> {:error, "no channel #{m["channel"]} here"}
      _ -> {:error, "manifest #{mkey} has no valid time"}
    end
  end

  @doc "Deletes a manifest and its slides from S3 without importing it."
  def delete(%{"manifest" => mkey} = m) do
    Enum.each(m["slides"] || [], &Storage.delete/1)
    Storage.delete(mkey)

    # Made on this machine: the post's slides are gone, so it can't be pulled any more
    case Repo.one(from p in Post, where: p.content_key == ^m["key"] and p.status == "uploaded") do
      nil -> :ok
      post -> Posts.reject(post, "deleted_from_s3")
    end

    :ok
  end

  defp parent_id(nil), do: nil
  defp parent_id(key), do: Repo.one(from p in Post, where: p.content_key == ^key, select: p.id)

  # Unscheduled posts are rejected once their time passes, so give late ones time for review
  defp review_time(at) do
    earliest =
      DateTime.utc_now() |> DateTime.add(@review_minutes * 60) |> DateTime.truncate(:second)

    if DateTime.compare(at, earliest) == :lt, do: earliest, else: at
  end
end
