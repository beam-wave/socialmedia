defmodule SocialmediaWeb.ContentLive do
  @moduledoc """
  The admin's working list: content the Mac has made, ready to edit and
  schedule. Edit the caption and time inline, then Schedule (= approve).
  """
  use SocialmediaWeb, :live_view
  import Ecto.Query
  import SocialmediaWeb.AdminComponents
  alias Socialmedia.{Repo, Posts, Channels}
  alias Socialmedia.Posts.Post
  alias SocialmediaWeb.PostText

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Content", channels: Channels.list_channels())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    channel_id =
      with id when is_binary(id) and id != "" <- params["channel"], do: String.to_integer(id)

    {:noreply, socket |> assign(channel_id: channel_id) |> load()}
  end

  @impl true
  def handle_info({:post_updated, _}, socket), do: {:noreply, load(socket)}

  defp load(socket) do
    now = DateTime.utc_now()

    base =
      from p in Post,
        where: p.scheduled_at > ^DateTime.add(now, -86_400),
        order_by: p.scheduled_at,
        preload: [:channel]

    base =
      if id = socket.assigns.channel_id, do: where(base, [p], p.channel_id == ^id), else: base

    posts = Repo.all(base)
    by = Enum.group_by(posts, & &1.status)

    assign(socket,
      ready: Map.get(by, "needs_review", []),
      scheduled: Map.get(by, "approved", []) ++ Map.get(by, "publishing", []),
      needs_facts:
        by
        |> Map.get("planned", [])
        |> Enum.filter(&(&1.post_type == "result" and is_nil(&1.facts))),
      waiting:
        (Map.get(by, "planned", [])
         |> Enum.reject(&(&1.post_type == "result" and is_nil(&1.facts)))) ++
          Map.get(by, "render_requested", []),
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
    do: simple(socket, Posts.regenerate(Posts.get_post!(id)), "Sent back to the Mac")

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
      roles={@roles}
      current_path={@current_path}
    >
      <.page_header
        title="Content"
        subtitle="Made on the Mac, ready for you. Edit the caption and time, then Schedule. Unscheduled posts are dropped when their time passes."
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
          text="Nothing waiting. New content shows up here as soon as the Mac uploads it."
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

      <section class="space-y-2">
        <h2 class="text-sm font-semibold">
          Waiting for the Mac <span class="muted font-normal">· {length(@waiting)}</span>
        </h2>
        <p class="text-xs muted">
          Planned from your slots. The Mac picks up each one when its writing time comes.
        </p>
        <ul
          :if={@waiting != []}
          class="rounded-lg border border-dashed hairline divide-y divide-base-300 text-sm"
        >
          <li :for={p <- Enum.take(@waiting, 12)} class="flex items-center gap-3 px-3 py-2">
            <span class="mono text-xs w-28 muted">
              {local(p.scheduled_at, p.channel.timezone, "%a %d · %H:%M")}
            </span>
            <span class="flex-1 truncate">{p.channel.handle} · {post_type_label(p.post_type)}</span>
            <.status_badge status={p.status} />
            <span :if={p.status == "planned" && p.generate_at} class="text-xs faint">
              writes {local(p.generate_at, p.channel.timezone, "%a %d %b %H:%M")}
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
