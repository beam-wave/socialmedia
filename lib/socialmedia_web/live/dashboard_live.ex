defmodule SocialmediaWeb.DashboardLive do
  use SocialmediaWeb, :live_view
  import SocialmediaWeb.AdminComponents
  alias Socialmedia.{Posts, Channels}
  alias SocialmediaWeb.PostText

  @tz "Asia/Kolkata"

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, "This week") |> load()}
  end

  @impl true
  def handle_info({:post_updated, _}, socket), do: {:noreply, load(socket)}

  @impl true
  def handle_event("approve", %{"id" => id}, socket) do
    case Posts.approve(Posts.get_post!(id)) do
      {:ok, _} ->
        {:noreply, put_flash(socket, :info, "Scheduled. It goes live at its time.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Can't schedule: #{inspect(reason)}")}
    end
  end

  defp load(socket) do
    today = DateTime.now!(@tz) |> DateTime.to_date()
    {:ok, from} = DateTime.new(today, ~T[00:00:00], @tz)
    from = DateTime.shift_zone!(from, "Etc/UTC")
    to = DateTime.add(from, 8 * 86_400)
    days = Enum.map(0..7, &Date.add(today, &1))
    channels = Channels.list_channels()

    posts =
      for ch <- channels, p <- Posts.list_posts(ch, from, to), into: [] do
        %{p | channel: ch}
      end

    grid =
      Enum.group_by(posts, fn p ->
        {p.channel_id, p.scheduled_at |> DateTime.shift_zone!(@tz) |> DateTime.to_date()}
      end)

    counts = Enum.frequencies_by(posts, & &1.status)

    socket
    |> assign(days: days, channels: channels, grid: grid, counts: counts, tz: @tz)
    |> assign(
      :review,
      posts
      |> Enum.filter(&(&1.status == "needs_review"))
      |> Enum.sort_by(& &1.scheduled_at, DateTime)
    )
    |> assign(:failed, posts |> Enum.filter(&(&1.status == "failed")))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      nav_channels={@nav_channels}
      current_path={@current_path}
    >
      <.page_header
        title="This week"
        subtitle={"#{Calendar.strftime(hd(@days), "%a %d %b")} – #{Calendar.strftime(List.last(@days), "%a %d %b")} · times in IST"}
      >
        <:actions>
          <.link navigate={~p"/content"} class="btn btn-sm btn-outline">
            <.icon name="hero-cloud-arrow-down" class="size-4" /> Pull from S3
          </.link>
        </:actions>
      </.page_header>

      <div class="grid grid-cols-2 sm:grid-cols-5 gap-3">
        <.stat label="Ready to schedule" value={@counts["needs_review"] || 0} strong />
        <.stat label="Scheduled" value={@counts["approved"] || 0} />
        <.stat label="Live" value={@counts["published"] || 0} />
        <.stat
          label="Being made"
          value={(@counts["creating"] || 0) + (@counts["uploaded"] || 0)}
        />
        <.stat label="Failed" value={@counts["failed"] || 0} />
      </div>

      <section :if={@channels == []}>
        <.empty text="No channels yet. Run mix run priv/repo/seeds.exs or add one.">
          <.link navigate={~p"/channels/new"} class="btn btn-sm btn-primary">Add channel</.link>
        </.empty>
      </section>

      <section :if={@channels != []} class="rounded-lg border hairline overflow-x-auto">
        <table class="w-full text-sm min-w-[880px] table-fixed">
          <thead>
            <tr class="border-b hairline text-left">
              <th class="w-40 px-3 py-2 font-medium muted text-xs">Channel</th>
              <th :for={d <- @days} class="px-2 py-2 font-medium text-xs">
                <span class={d == hd(@days) && "underline underline-offset-4"}>
                  {Calendar.strftime(d, "%a")}
                </span>
                <span class="muted">{Calendar.strftime(d, "%d")}</span>
              </th>
            </tr>
          </thead>
          <tbody>
            <tr :for={ch <- @channels} class="border-b hairline last:border-0 align-top">
              <td class="px-3 py-2.5">
                <.link navigate={~p"/channels/#{ch.id}"} class="font-medium hover:underline">
                  {ch.handle}
                </.link>
              </td>
              <td :for={d <- @days} class="px-1.5 py-1.5">
                <div class="space-y-1">
                  <.link
                    :for={p <- Map.get(@grid, {ch.id, d}, [])}
                    navigate={~p"/posts/#{p.id}"}
                    class="block rounded-md px-1.5 py-1 row-hover"
                  >
                    <div class="mono text-[11px] muted">{local(p.scheduled_at, @tz, "%H:%M")}</div>
                    <.status_badge status={p.status} />
                  </.link>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </section>

      <section class="space-y-2">
        <h2 class="text-sm font-semibold">Ready to schedule</h2>
        <.empty :if={@review == []} text="Nothing to review right now." />
        <ul :if={@review != []} class="rounded-lg border hairline divide-y divide-base-300">
          <li :for={p <- @review} class="flex items-center gap-4 px-3 py-2.5">
            <img
              :if={p.slide_paths != []}
              src={slide_src(hd(p.slide_paths))}
              class="slide-thumb w-12 rounded border hairline"
              alt=""
            />
            <div class="min-w-0 flex-1">
              <div class="text-sm font-medium truncate">{PostText.title(p) || "Untitled"}</div>
              <div class="text-xs muted">
                {p.channel.handle} · {post_type_label(p.post_type)} · {local(p.scheduled_at, @tz)}
              </div>
            </div>
            <.link navigate={~p"/posts/#{p.id}"} class="btn btn-sm btn-ghost">Open</.link>
            <button phx-click="approve" phx-value-id={p.id} class="btn btn-sm btn-primary">
              Schedule
            </button>
          </li>
        </ul>
      </section>

      <section :if={@failed != []} class="space-y-2">
        <h2 class="text-sm font-semibold">Failed</h2>
        <ul class="rounded-lg border-2 border-base-content divide-y divide-base-300">
          <li :for={p <- @failed} class="px-3 py-2.5 text-sm flex items-center gap-4">
            <div class="min-w-0 flex-1">
              <div class="font-medium">{p.channel.handle} · {local(p.scheduled_at, @tz)}</div>
              <div class="text-xs muted truncate">{p.error}</div>
            </div>
            <.link navigate={~p"/posts/#{p.id}"} class="btn btn-sm btn-outline">Fix</.link>
          </li>
        </ul>
      </section>
    </Layouts.app>
    """
  end
end
