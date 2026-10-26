defmodule Socialmedia.Content do
  @moduledoc """
  Content sync over S3. Two machines, no direct connection:

    * **Prod (primary)** publishes `plan.json`: every post waiting for content
      (`planned` with `generate_at` reached, or `render_requested`), each
      tagged with its `gen_rev`. It then imports finished work from `inbox/`.
    * **Mac (content node)** reads `plan.json`, runs Claude + the renderer for
      each item it hasn't done, uploads the slides to `content/<id>/<rev>/` and
      drops a manifest in `inbox/<id>-<rev>.json` (written last, so a manifest
      always points at complete uploads).

  `gen_rev` makes this safe to repeat: a manifest for an old revision (the
  admin regenerated in the meantime) is discarded on import.
  """
  import Ecto.Query
  require Logger
  alias Socialmedia.{Repo, Posts, Storage}
  alias Socialmedia.Posts.Post
  alias Socialmedia.Content.{Matches, Work}

  @plan_key "plan.json"
  # "Try again later" requests honoured per post (e.g. 8 × 45 min for a long match)
  @max_retries 8

  ## Prod side

  @doc "Posts that need content right now, as Work."
  def pending_work do
    now = DateTime.utc_now()

    Repo.all(
      from p in Post,
        where:
          (p.status == "planned" and p.generate_at <= ^now and p.scheduled_at > ^now) or
            (p.status == "render_requested" and p.scheduled_at > ^now),
        order_by: p.scheduled_at,
        preload: [:channel, :schedule, :parent]
    )
    |> Enum.map(fn post ->
      kind = if post.status == "planned", do: "generate", else: "render"
      Work.from_post(post, kind, Posts.recent_data(post.channel, 20))
    end)
  end

  @doc "Writes plan.json for the content node."
  def publish_plan do
    work = pending_work()

    :ok =
      Storage.put_json(@plan_key, %{
        generated_at: DateTime.utc_now(),
        work: Enum.map(work, &Work.to_json_map/1)
      })

    {:ok, length(work)}
  end

  @doc "Imports every manifest in inbox/. Returns the number imported."
  def import_inbox do
    {:ok, keys} = Storage.list("inbox/")

    keys
    |> Enum.filter(&String.ends_with?(&1, ".json"))
    |> Enum.count(fn key ->
      result =
        with {:ok, manifest} <- Storage.get_json(key) do
          import_manifest(manifest)
        end

      case result do
        {:ok, _} ->
          Storage.delete(key)
          true

        {:stale, why} ->
          Logger.info("dropping stale manifest #{key}: #{why}")
          Storage.delete(key)
          false

        other ->
          Logger.warning("could not import #{key}: #{inspect(other)}")
          false
      end
    end)
  end

  def import_manifest(%{"post_id" => id, "rev" => rev} = m) do
    case Posts.get_post(id) do
      nil ->
        {:stale, "post #{id} is gone"}

      %Post{gen_rev: ^rev, status: status} = post
      when status in ["planned", "render_requested"] ->
        apply_manifest(post, m)

      %Post{} = post ->
        {:stale, "post #{id} is rev #{post.gen_rev} / #{post.status}"}
    end
  end

  defp apply_manifest(post, %{"status" => "ok"} = m) do
    old = post.slide_paths

    with {:ok, post} <-
           Posts.mark(post, "needs_review", %{
             data: m["data"],
             caption: m["caption"],
             sources: m["sources"] || post.sources,
             agent_log: m["notes"] || post.agent_log,
             slide_paths: m["slides"],
             error: nil
           }) do
      # Previous revision's slides are no longer referenced
      Enum.each(old -- m["slides"], &Storage.delete/1)
      if post.post_type == "fixture", do: Matches.after_fixture(post)
      {:ok, post}
    end
  end

  defp apply_manifest(post, %{"status" => "failed", "retry_after_minutes" => mins} = m)
       when is_integer(mins) and mins > 0 do
    if post.retries < @max_retries do
      Posts.retry_later(post, mins, "Waiting: #{m["error"]}")
    else
      Posts.mark(post, "failed", %{error: "Gave up after #{post.retries} tries: #{m["error"]}"})
    end
  end

  defp apply_manifest(post, %{"status" => "failed"} = m) do
    msg = if m["skip"], do: "Agent skipped: #{m["error"]}", else: m["error"]
    Posts.mark(post, "failed", %{error: msg})
  end

  ## Mac side

  @doc "Reads plan.json. A missing plan means no work."
  def read_plan do
    case Storage.get_json(@plan_key) do
      {:ok, %{"work" => list}} -> {:ok, Enum.map(list, &Work.from_json_map/1)}
      {:error, :not_found} -> {:ok, []}
      error -> error
    end
  end

  def inbox_key(%Work{post_id: id, rev: rev}), do: "inbox/#{id}-#{rev}.json"

  @doc "True when this request was already delivered (waiting for prod to import)."
  def delivered?(%Work{} = w), do: Storage.exists?(inbox_key(w))

  @doc "Uploads slides untouched, then the manifest."
  def deliver(%Work{} = w, %{data: data, caption: caption, slides: files} = result) do
    keys =
      for file <- files do
        key = "content/#{w.post_id}/#{w.rev}/#{Path.basename(file)}"
        :ok = Storage.put_file(key, file, "image/jpeg")
        key
      end

    Storage.put_json(inbox_key(w), %{
      status: "ok",
      post_id: w.post_id,
      rev: w.rev,
      data: data,
      caption: caption,
      sources: result[:sources],
      notes: result[:notes],
      slides: keys
    })
  end

  def deliver_failure(%Work{} = w, error, skip?, retry_after_minutes \\ nil) do
    Storage.put_json(inbox_key(w), %{
      status: "failed",
      post_id: w.post_id,
      rev: w.rev,
      error: error,
      skip: skip?,
      retry_after_minutes: retry_after_minutes
    })
  end
end
