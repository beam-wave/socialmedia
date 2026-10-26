defmodule SocialmediaWeb.ChannelLive.Show do
  @moduledoc "One channel: its upcoming posts (Week) and its posting slots (Slots)."
  use SocialmediaWeb, :live_view
  import SocialmediaWeb.AdminComponents
  alias Socialmedia.{Channels, Posts}
  alias Socialmedia.Channels.Schedule
  alias Socialmedia.Workers.Planner
  alias SocialmediaWeb.PostText

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    channel = Channels.get_channel!(id)
    {:ok, socket |> assign(channel: channel, page_title: channel.handle, editing: nil) |> load()}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_info(
        {:post_updated, %{channel_id: cid}},
        %{assigns: %{channel: %{id: cid}}} = socket
      ),
      do: {:noreply, load_posts(socket)}

  def handle_info(_, socket), do: {:noreply, socket}

  defp load(socket), do: socket |> load_posts() |> load_slots()

  defp load_posts(socket) do
    ch = socket.assigns.channel
    now = DateTime.utc_now()
    posts = Posts.list_posts(ch, DateTime.add(now, -2 * 86_400), DateTime.add(now, 8 * 86_400))

    days =
      posts
      |> Enum.group_by(
        &(&1.scheduled_at
          |> DateTime.shift_zone!(ch.timezone)
          |> DateTime.to_date())
      )
      |> Enum.sort_by(&elem(&1, 0), Date)

    assign(socket, days: days, today: DateTime.now!(ch.timezone) |> DateTime.to_date())
  end

  defp load_slots(socket) do
    slots = Channels.list_schedules(socket.assigns.channel)
    assign(socket, slots: slots, form: slot_form(socket.assigns[:editing]))
  end

  defp slot_form(nil),
    do:
      to_form(
        Channels.change_schedule(%Schedule{
          weekdays: Enum.to_list(1..7),
          time_of_day: ~T[09:00:00]
        })
      )

  defp slot_form(%Schedule{} = s), do: to_form(Channels.change_schedule(s))

  ## Events: posts

  @impl true
  def handle_event("approve", %{"id" => id}, socket) do
    case Posts.approve(Posts.get_post!(id)) do
      {:ok, _} -> {:noreply, put_flash(socket, :info, "Scheduled")}
      {:error, r} -> {:noreply, put_flash(socket, :error, "Can't schedule: #{inspect(r)}")}
    end
  end

  def handle_event("plan", _, socket) do
    Planner.enqueue()
    {:noreply, put_flash(socket, :info, "Planning the next 7 days…")}
  end

  ## Events: slots

  def handle_event("edit_slot", %{"id" => id}, socket) do
    s = Channels.get_schedule!(id)
    {:noreply, socket |> assign(editing: s, form: slot_form(s))}
  end

  def handle_event("cancel_edit", _, socket),
    do: {:noreply, socket |> assign(editing: nil, form: slot_form(nil))}

  def handle_event("validate_slot", %{"schedule" => params}, socket) do
    base = socket.assigns.editing || %Schedule{}
    cs = Channels.change_schedule(base, normalize(params, socket)) |> Map.put(:action, :validate)
    {:noreply, assign(socket, form: to_form(cs))}
  end

  def handle_event("save_slot", %{"schedule" => params}, socket) do
    params = normalize(params, socket)

    result =
      case socket.assigns.editing do
        nil -> Channels.create_schedule(params)
        s -> Channels.update_schedule(s, params)
      end

    case result do
      {:ok, s} ->
        Planner.replan(s)

        {:noreply,
         socket
         |> put_flash(:info, "Slot saved. Upcoming posts re-planned.")
         |> assign(editing: nil)
         |> load()}

      {:error, cs} ->
        {:noreply, assign(socket, form: to_form(cs))}
    end
  end

  def handle_event("toggle_slot", %{"id" => id}, socket) do
    s = Channels.get_schedule!(id)
    {:ok, s} = Channels.update_schedule(s, %{active: !s.active})
    Planner.replan(s)
    {:noreply, load(socket)}
  end

  def handle_event("delete_slot", %{"id" => id}, socket) do
    s = Channels.get_schedule!(id)
    {:ok, _} = Channels.delete_schedule(s)
    Planner.enqueue()
    {:noreply, socket |> put_flash(:info, "Slot deleted") |> load()}
  end

  defp normalize(params, socket) do
    days =
      params
      |> Map.get("weekdays", [])
      |> List.wrap()
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(&String.to_integer/1)

    params
    |> Map.put("weekdays", days)
    |> Map.put("channel_id", socket.assigns.channel.id)
  end

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
      <.page_header title={@channel.handle} subtitle={"#{@channel.name} · #{@channel.timezone}"}>
        <:actions>
          <span class={[
            "rounded px-2 py-0.5 text-[11px] uppercase tracking-wide",
            if(@channel.dry_run, do: "border hairline muted", else: "bg-base-content text-base-100")
          ]}>
            {if @channel.dry_run, do: "Dry run", else: "Publishing live"}
          </span>
          <button :if={@roles.primary} phx-click="plan" class="btn btn-sm btn-outline">
            Plan 7 days
          </button>
        </:actions>
      </.page_header>

      <.tabs tabs={[
        {"Week", ~p"/channels/#{@channel.id}", @live_action == :week},
        {"Slots", ~p"/channels/#{@channel.id}/slots", @live_action == :slots}
      ]} />
      <div class="-mt-3 text-right">
        <.link navigate={~p"/channels/#{@channel.id}/settings"} class="text-xs muted hover:underline">
          Channel settings →
        </.link>
      </div>

      <.week :if={@live_action == :week} days={@days} today={@today} channel={@channel} />
      <.slots :if={@live_action == :slots} slots={@slots} form={@form} editing={@editing} />
    </Layouts.app>
    """
  end

  attr :days, :list, required: true
  attr :today, Date, required: true
  attr :channel, :map, required: true

  defp week(assigns) do
    ~H"""
    <.empty :if={@days == []} text="No posts in this window. Add a slot, then plan the week.">
      <.link patch={~p"/channels/#{@channel.id}/slots"} class="btn btn-sm btn-primary">
        Add a slot
      </.link>
    </.empty>

    <section :for={{date, posts} <- @days} class="space-y-2">
      <h2 class="text-xs uppercase tracking-wider muted">
        {Calendar.strftime(date, "%A %d %B")}
        <span
          :if={date == @today}
          class="ml-1 rounded bg-base-content text-base-100 px-1.5 py-0.5 normal-case tracking-normal"
        >
          Today
        </span>
      </h2>
      <ul class="rounded-lg border hairline divide-y divide-base-300">
        <li :for={p <- posts} class="flex items-center gap-4 px-3 py-2.5">
          <div class="mono text-sm w-12 shrink-0">
            {local(p.scheduled_at, @channel.timezone, "%H:%M")}
          </div>
          <div class="w-10 shrink-0">
            <img
              :if={p.slide_paths != []}
              src={slide_src(hd(p.slide_paths))}
              class="slide-thumb w-10 rounded border hairline"
              alt=""
            />
            <div
              :if={p.slide_paths == []}
              class="slide-thumb w-10 rounded border border-dashed hairline"
            />
          </div>
          <div class="min-w-0 flex-1">
            <div class={["text-sm truncate", p.status == "rejected" && "faint line-through"]}>
              {PostText.title(p) || post_type_label(p.post_type)}
            </div>
            <div class="text-xs muted truncate">
              {post_type_label(p.post_type)}
              <span :if={p.status == "planned" && p.generate_at}>
                · writing from {local(p.generate_at, @channel.timezone, "%a %H:%M")}
              </span>
              <span :if={p.error}>· {p.error}</span>
              <span :if={p.reject_reason}>· {String.replace(p.reject_reason, "_", " ")}</span>
            </div>
          </div>
          <.status_badge status={p.status} />
          <button
            :if={p.status == "needs_review"}
            phx-click="approve"
            phx-value-id={p.id}
            class="btn btn-sm btn-primary"
          >
            Schedule
          </button>
          <.link navigate={~p"/posts/#{p.id}"} class="btn btn-sm btn-ghost">Open</.link>
        </li>
      </ul>
    </section>
    """
  end

  attr :slots, :list, required: true
  attr :form, :any, required: true
  attr :editing, :any, required: true

  defp slots(assigns) do
    ~H"""
    <div class="grid xl:grid-cols-[minmax(0,1fr)_340px] gap-6 items-start">
      <section>
        <.empty
          :if={@slots == []}
          text="No slots yet. Each slot creates one post on the chosen days."
        />
        <ul :if={@slots != []} class="rounded-lg border hairline divide-y divide-base-300">
          <li :for={s <- @slots} class={["px-3 py-3 flex items-center gap-4", !s.active && "faint"]}>
            <div class="mono text-lg w-16">{Calendar.strftime(s.time_of_day, "%H:%M")}</div>
            <div class="min-w-0 flex-1 space-y-1">
              <div class="text-sm font-medium">{post_type_label(s.post_type)}</div>
              <div class="flex gap-1">
                <span
                  :for={{name, i} <- Enum.with_index(weekday_names(), 1)}
                  class={[
                    "w-7 text-center rounded text-[10px] py-0.5",
                    if(i in s.weekdays,
                      do: "bg-base-content text-base-100",
                      else: "border hairline faint"
                    )
                  ]}
                >
                  {String.slice(name, 0, 2)}
                </span>
              </div>
              <div class="text-xs muted">
                Written {s.lead_hours}h before{if s.extra_instructions && s.extra_instructions != "",
                  do: " · " <> s.extra_instructions}
              </div>
            </div>
            <button phx-click="toggle_slot" phx-value-id={s.id} class="btn btn-xs btn-ghost">
              {if s.active, do: "Pause", else: "Resume"}
            </button>
            <button phx-click="edit_slot" phx-value-id={s.id} class="btn btn-xs btn-outline">
              Edit
            </button>
            <button
              phx-click="delete_slot"
              phx-value-id={s.id}
              data-confirm="Delete this slot? Untouched upcoming posts from it are removed."
              class="btn btn-xs btn-ghost"
            >
              <.icon name="hero-trash" class="size-3.5" />
            </button>
          </li>
        </ul>
      </section>

      <section class="rounded-lg border hairline p-4">
        <h2 class="text-sm font-semibold mb-3">{if @editing, do: "Edit slot", else: "New slot"}</h2>
        <.form for={@form} phx-change="validate_slot" phx-submit="save_slot" class="space-y-1">
          <.input
            field={@form[:post_type]}
            type="select"
            label="Post type"
            options={Enum.map(Schedule.post_types(), &{post_type_label(&1), &1})}
          />
          <.input field={@form[:time_of_day]} type="time" label="Time (channel timezone)" />
          <fieldset class="fieldset mb-2">
            <span class="label mb-1">Days</span>
            <input type="hidden" name="schedule[weekdays][]" value="" />
            <div class="flex gap-1">
              <label
                :for={{name, i} <- Enum.with_index(weekday_names(), 1)}
                class="cursor-pointer"
              >
                <input
                  type="checkbox"
                  name="schedule[weekdays][]"
                  value={i}
                  checked={i in (@form[:weekdays].value || [])}
                  class="peer sr-only"
                />
                <span class="block w-9 text-center rounded border hairline text-xs py-1 peer-checked:bg-base-content peer-checked:text-base-100">
                  {String.slice(name, 0, 2)}
                </span>
              </label>
            </div>
            <p :for={{msg, _} <- @form[:weekdays].errors} class="text-xs mt-1">{msg}</p>
          </fieldset>
          <.input
            field={@form[:lead_hours]}
            type="number"
            label="Write it how many hours before?"
            min="0"
            max="168"
          />
          <.input
            field={@form[:extra_instructions]}
            type="textarea"
            label="Instructions for the agent (optional)"
            placeholder="e.g. Only India matches. Or: focus on Indian startups."
          />
          <.input field={@form[:active]} type="checkbox" label="Active" />
          <div class="flex gap-2 pt-2">
            <button class="btn btn-sm btn-primary" phx-disable-with="Saving…">Save slot</button>
            <button :if={@editing} type="button" phx-click="cancel_edit" class="btn btn-sm btn-ghost">
              Cancel
            </button>
          </div>
        </.form>
      </section>
    </div>
    """
  end
end
