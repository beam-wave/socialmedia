defmodule SocialmediaWeb.ContentLive do
  @moduledoc """
  The admin's working list. Pull brings in what's waiting in S3; then edit
  the caption and time inline and Schedule (= approve, which queues the
  Oban publish job for that time).
  """
  use SocialmediaWeb, :live_view
  import Ecto.Query
  import SocialmediaWeb.AdminComponents
  alias Socialmedia.{Repo, Posts, Channels, Content}
  alias Socialmedia.Posts.Post
  alias SocialmediaWeb.PostText

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Content", channels: Channels.list_channels())
     |> load_s3()}
  end

  # S3 is only read on mount and when asked (Refresh, Pull, Delete, or a post made here)
  defp load_s3(socket) do
    if connected?(socket) do
      assign(socket, s3: Content.manifests(), s3_error: nil)
    else
      assign(socket, s3: [], s3_error: nil)
    end
  rescue
    e -> assign(socket, s3: [], s3_error: Exception.message(e))
  end

  @impl true
  def handle_params(params, _url, socket) do
    channel_id =
      with id when is_binary(id) and id != "" <- params["channel"], do: String.to_integer(id)

    {:noreply, socket |> assign(channel_id: channel_id) |> load()}
  end

  @impl true
  def handle_info({:post_updated, %{status: "uploaded"}}, socket),
    do: {:noreply, socket |> load() |> load_s3()}

  def handle_info({:post_updated, _}, socket), do: {:noreply, load(socket)}

  defp load(socket) do
    now = DateTime.utc_now()

    base =
      from p in Post,
        # Anything still waiting on the admin stays listed however old it is
        where:
          p.status in ~w(planned creating needs_review approved publishing failed) or
            p.scheduled_at > ^DateTime.add(now, -86_400),
        order_by: p.scheduled_at,
        preload: [:channel]

    base =
      if id = socket.assigns.channel_id, do: where(base, [p], p.channel_id == ^id), else: base

    posts = Repo.all(base)
    by = Enum.group_by(posts, & &1.status)

    assign(socket,
      ready: Map.get(by, "needs_review", []),
      scheduled: Map.get(by, "approved", []) ++ Map.get(by, "publishing", []),
      needs_facts: by |> Map.get("planned", []) |> Enum.filter(&(&1.post_type == "result")),
      creating: Map.get(by, "creating", []),
      failed: Map.get(by, "failed", []),
      live: by |> Map.get("published", []) |> Enum.reverse() |> Enum.take(10)
    )
  end

  ## Events

  @impl true
  def handle_event("filter", %{"channel" => id}, socket),
    do: {:noreply, push_patch(socket, to: ~p"/content?#{[channel: id]}")}

  def handle_event("schedule", %{"post_id" => id} = params, socket) do
    post = Posts.get_post!(id)

    with {:ok, at} <- parse_local(params["at"], post.channel.timezone),
         {:ok, _} <- Posts.schedule(post, %{caption: params["caption"], scheduled_at: at}) do
      {:noreply, put_flash(socket, :info, "Scheduled for #{local(at, post.channel.timezone)}")}
    else
      {:error, reason} -> {:noreply, put_flash(socket, :error, explain(reason))}
    end
  end

  def handle_event("move", %{"post_id" => id, "at" => at}, socket) do
    post = Posts.get_post!(id)

    with {:ok, at} <- parse_local(at, post.channel.timezone),
         {:ok, _} <- Posts.reschedule(post, at) do
      {:noreply, put_flash(socket, :info, "Moved to #{local(at, post.channel.timezone)}")}
    else
      {:error, reason} -> {:noreply, put_flash(socket, :error, explain(reason))}
    end
  end

  def handle_event("unschedule", %{"id" => id}, socket),
    do: simple(socket, Posts.unapprove(Posts.get_post!(id)), "Back in the ready list")

  def handle_event("reject", %{"id" => id}, socket),
    do: simple(socket, Posts.reject(Posts.get_post!(id)), "Rejected")

  def handle_event("retry", %{"id" => id}, socket),
    do: simple(socket, Posts.regenerate(Posts.get_post!(id)), "Writing it again…")

  def handle_event("refresh_s3", _, socket), do: {:noreply, load_s3(socket)}

  def handle_event("pull_all", _, socket) do
    n = Content.pull_all()
    {:noreply, socket |> put_flash(:info, "Pulled #{n} post(s)") |> load() |> load_s3()}
  end

  def handle_event("pull", %{"key" => key}, socket) do
    socket =
      case find_manifest(socket, key) do
        nil ->
          put_flash(socket, :error, "It's no longer in S3.")

        m ->
          case Content.pull(m) do
            {:ok, _} -> put_flash(socket, :info, "Pulled. It's ready to schedule.")
            {:error, why} -> put_flash(socket, :error, why)
          end
      end

    {:noreply, socket |> load() |> load_s3()}
  end

  def handle_event("delete_s3", %{"key" => key}, socket) do
    socket =
      case find_manifest(socket, key) do
        nil -> socket
        m -> Content.delete(m) && put_flash(socket, :info, "Deleted from S3")
      end

    {:noreply, load_s3(socket)}
  end

  defp find_manifest(socket, key), do: Enum.find(socket.assigns.s3, &(&1["key"] == key))

  defp manifest_tz(m, channels) do
    Enum.find_value(channels, "Asia/Kolkata", &(&1.handle == m["channel"] && &1.timezone))
  end

  defp manifest_time(m, channels) do
    case DateTime.from_iso8601(m["scheduled_at"] || "") do
      {:ok, at, _} -> local(at, manifest_tz(m, channels), "%a %d %b · %H:%M")
      _ -> "no time"
    end
  end

  defp simple(socket, {:ok, _}, msg), do: {:noreply, put_flash(socket, :info, msg)}
  defp simple(socket, {:error, r}, _), do: {:noreply, put_flash(socket, :error, explain(r))}

  @doc false
  def parse_local(str, tz) when is_binary(str) and str != "" do
    str = if String.length(str) == 16, do: str <> ":00", else: str

    with {:ok, naive} <- NaiveDateTime.from_iso8601(str),
         {:ok, local} <- DateTime.from_naive(naive, tz) do
      {:ok, local |> DateTime.shift_zone!("Etc/UTC") |> DateTime.truncate(:second)}
    else
      _ -> {:error, :bad_time}
    end
  end

  def parse_local(_, _), do: {:error, :bad_time}

  defp input_value(%DateTime{} = at, tz),
    do: at |> DateTime.shift_zone!(tz) |> Calendar.strftime("%Y-%m-%dT%H:%M")

  defp explain(:time_passed), do: "Pick a time in the future."
  defp explain(:slot_passed), do: "That time has passed. Pick a new time."
  defp explain(:bad_time), do: "That date/time isn't valid."
  defp explain(:not_reviewable), do: "This post can't be changed now."
  defp explain(:not_approved), do: "It isn't scheduled."
  defp explain(:final), do: "This post is already final."
  defp explain(other), do: inspect(other)

  ## Render

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      nav_channels={@nav_channels}
      current_path={@current_path}
    >
      <.page_header
        title="Content"
        subtitle="Pull what's in S3, edit the caption and time, then Schedule. Reject anything you don't want."
      >
        <:actions>
          <form phx-change="filter">
            <select name="channel" class="select select-sm">
              <option value="">All channels</option>
              <option :for={c <- @channels} value={c.id} selected={c.id == @channel_id}>
                {c.handle}
              </option>
            </select>
          </form>
        </:actions>
      </.page_header>

      <section id="s3-inbox" class="space-y-2">
        <div class="flex flex-wrap items-center justify-between gap-2">
          <h2 class="text-sm font-semibold">
            In S3, not pulled yet <span class="muted font-normal">· {length(@s3)}</span>
          </h2>
          <div class="flex gap-2">
            <button id="refresh-s3" phx-click="refresh_s3" class="btn btn-sm btn-ghost">
              <.icon name="hero-arrow-path" class="size-4" /> Refresh
            </button>
            <button
              id="pull-all"
              phx-click="pull_all"
              disabled={@s3 == []}
              class="btn btn-sm btn-primary"
              phx-disable-with="Pulling…"
            >
              <.icon name="hero-cloud-arrow-down" class="size-4" /> Pull all
            </button>
          </div>
        </div>
        <p :if={@s3_error} class="text-xs font-semibold">Couldn't read S3: {@s3_error}</p>
        <.empty
          :if={@s3 == [] and is_nil(@s3_error)}
          text="Nothing in S3. Create posts from a channel page; they land here when done."
        />
        <ul :if={@s3 != []} class="rounded-lg border hairline divide-y divide-base-300">
          <li
            :for={m <- @s3}
            id={"s3-#{m["key"]}"}
            class="flex flex-wrap items-center gap-3 px-3 py-2.5"
          >
            <img
              :if={(m["slides"] || []) != []}
              src={slide_src(hd(m["slides"]))}
              class="slide-thumb w-10 rounded border hairline"
              alt=""
            />
            <div class="min-w-0 flex-1">
              <div class="text-sm truncate">{PostText.title(%{data: m["data"]}) || "Untitled"}</div>
              <div class="text-xs muted">
                {m["channel"]} · {post_type_label(m["post_type"])} · {manifest_time(m, @channels)}
              </div>
            </div>
            <button
              phx-click="delete_s3"
              phx-value-key={m["key"]}
              data-confirm="Delete this post and its slides from S3?"
              class="btn btn-sm btn-ghost"
            >
              <.icon name="hero-trash" class="size-4" /> Delete
            </button>
            <button phx-click="pull" phx-value-key={m["key"]} class="btn btn-sm btn-outline">
              Pull
            </button>
          </li>
        </ul>
      </section>

      <section :if={@needs_facts != []} class="space-y-2">
        <h2 class="text-sm font-semibold">
          Match results to enter <span class="muted font-normal">· {length(@needs_facts)}</span>
        </h2>
        <ul class="rounded-lg border-2 border-base-content divide-y divide-base-300">
          <li :for={p <- @needs_facts} class="flex items-center gap-3 px-3 py-2.5 text-sm">
            <.icon name="hero-pencil-square" class="size-4" />
            <div class="min-w-0 flex-1">
              <div>{p.channel.handle} · result</div>
              <div class="text-xs muted">
                goes out {local(p.scheduled_at, p.channel.timezone, "%a %d %b · %H:%M")}
              </div>
            </div>
            <.link navigate={~p"/posts/#{p.id}"} class="btn btn-sm btn-primary">Enter result</.link>
          </li>
        </ul>
      </section>

      <section class="space-y-3">
        <h2 class="text-sm font-semibold">
          Ready to schedule <span class="muted font-normal">· {length(@ready)}</span>
        </h2>
        <.empty
          :if={@ready == []}
          text="Nothing to schedule. Pull from S3 above, or create a post on a channel page."
        />

        <article :for={p <- @ready} id={"ready-#{p.id}"} class="rounded-lg border hairline p-4">
          <div class="grid md:grid-cols-[220px_minmax(0,1fr)] gap-5">
            <div class="space-y-2">
              <.link navigate={~p"/posts/#{p.id}"}>
                <img
                  :if={p.slide_paths != []}
                  src={slide_src(hd(p.slide_paths))}
                  class="slide-thumb w-full rounded-md border hairline"
                  alt=""
                />
              </.link>
              <div :if={length(p.slide_paths) > 1} class="flex gap-1 overflow-x-auto">
                <img
                  :for={k <- tl(p.slide_paths)}
                  src={slide_src(k)}
                  class="slide-thumb w-10 rounded-sm border hairline"
                  alt=""
                />
              </div>
            </div>

            <form phx-submit="schedule" class="space-y-3 min-w-0">
              <input type="hidden" name="post_id" value={p.id} />
              <div class="flex flex-wrap items-baseline justify-between gap-2">
                <div class="min-w-0">
                  <div class="text-xs muted">{p.channel.handle} · {post_type_label(p.post_type)}</div>
                  <h3 class="font-medium truncate">{PostText.title(p) || "Untitled"}</h3>
                </div>
                <.link navigate={~p"/posts/#{p.id}"} class="text-xs muted hover:underline">
                  Details, sources, regenerate →
                </.link>
              </div>

              <textarea
                name="caption"
                rows="7"
                maxlength="2200"
                class="textarea w-full text-sm leading-relaxed"
                aria-label="Caption"
              >{p.caption}</textarea>

              <div class="flex flex-wrap items-end gap-3">
                <label class="text-xs">
                  <span class="block muted mb-1">Post at ({p.channel.timezone})</span>
                  <input
                    type="datetime-local"
                    name="at"
                    value={input_value(p.scheduled_at, p.channel.timezone)}
                    class="input input-sm mono"
                  />
                </label>
                <div class="flex gap-2 ml-auto">
                  <button
                    type="button"
                    phx-click="reject"
                    phx-value-id={p.id}
                    data-confirm="Reject this post?"
                    class="btn btn-sm btn-ghost"
                  >
                    Reject
                  </button>
                  <button
                    type="submit"
                    class="btn btn-sm btn-primary"
                    phx-disable-with="Scheduling…"
                  >
                    <.icon name="hero-calendar" class="size-4" /> Schedule
                  </button>
                </div>
              </div>
            </form>
          </div>
        </article>
      </section>

      <section class="space-y-2">
        <h2 class="text-sm font-semibold">
          Scheduled <span class="muted font-normal">· {length(@scheduled)}</span>
        </h2>
        <.empty :if={@scheduled == []} text="Nothing scheduled yet." />
        <ul :if={@scheduled != []} class="rounded-lg border hairline divide-y divide-base-300">
          <li :for={p <- @scheduled} class="flex flex-wrap items-center gap-3 px-3 py-2.5">
            <img
              :if={p.slide_paths != []}
              src={slide_src(hd(p.slide_paths))}
              class="slide-thumb w-10 rounded border hairline"
              alt=""
            />
            <div class="min-w-0 flex-1">
              <div class="text-sm truncate">{PostText.title(p)}</div>
              <div class="text-xs muted">{p.channel.handle} · {post_type_label(p.post_type)}</div>
            </div>
            <form phx-submit="move" class="flex items-center gap-2">
              <input type="hidden" name="post_id" value={p.id} />
              <input
                type="datetime-local"
                name="at"
                value={input_value(p.scheduled_at, p.channel.timezone)}
                class="input input-sm mono"
                aria-label="Post at"
              />
              <button class="btn btn-sm btn-ghost">Move</button>
            </form>
            <button phx-click="unschedule" phx-value-id={p.id} class="btn btn-sm btn-ghost">
              Unschedule
            </button>
            <.link navigate={~p"/posts/#{p.id}"} class="btn btn-sm btn-ghost">Open</.link>
          </li>
        </ul>
      </section>

      <section :if={@failed != []} class="space-y-2">
        <h2 class="text-sm font-semibold">
          Failed <span class="muted font-normal">· {length(@failed)}</span>
        </h2>
        <ul class="rounded-lg border-2 border-base-content divide-y divide-base-300">
          <li :for={p <- @failed} class="flex items-center gap-3 px-3 py-2.5 text-sm">
            <div class="min-w-0 flex-1">
              <div>{p.channel.handle} · {local(p.scheduled_at, p.channel.timezone)}</div>
              <div class="text-xs muted truncate">{p.error}</div>
            </div>
            <button phx-click="retry" phx-value-id={p.id} class="btn btn-sm btn-outline">
              Try again
            </button>
            <button phx-click="reject" phx-value-id={p.id} class="btn btn-sm btn-ghost">
              Reject
            </button>
          </li>
        </ul>
      </section>

      <section :if={@creating != []} class="space-y-2">
        <h2 class="text-sm font-semibold">
          Being made here <span class="muted font-normal">· {length(@creating)}</span>
        </h2>
        <ul class="rounded-lg border border-dashed hairline divide-y divide-base-300 text-sm">
          <li :for={p <- @creating} class="flex items-center gap-3 px-3 py-2">
            <span class="loading loading-spinner loading-xs"></span>
            <span class="flex-1 truncate">{p.channel.handle} · {post_type_label(p.post_type)}</span>
            <span class="mono text-xs muted">
              {local(p.scheduled_at, p.channel.timezone, "%a %d · %H:%M")}
            </span>
          </li>
        </ul>
      </section>

      <section :if={@live != []} class="space-y-2">
        <h2 class="text-sm font-semibold">Recently live</h2>
        <ul class="text-sm space-y-1">
          <li :for={p <- @live} class="flex gap-3 muted">
            <span class="mono text-xs w-28">
              {local(p.scheduled_at, p.channel.timezone, "%a %d · %H:%M")}
            </span>
            <span class="truncate">{p.channel.handle} · {PostText.title(p)}</span>
            <a :if={p.permalink} href={p.permalink} target="_blank" rel="noopener" class="underline">
              view
            </a>
          </li>
        </ul>
      </section>
    </Layouts.app>
    """
  end
end
