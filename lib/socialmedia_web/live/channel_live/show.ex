defmodule SocialmediaWeb.ChannelLive.Show do
  @moduledoc """
  One channel: create a post and see its posts by day.
  """
  use SocialmediaWeb, :live_view
  import SocialmediaWeb.AdminComponents
  alias Socialmedia.{Channels, Content, Posts}
  alias SocialmediaWeb.PostText

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    channel = Channels.get_channel!(id)

    {:ok,
     socket
     |> assign(channel: channel, page_title: channel.handle)
     |> load_posts()
     |> assign_create(nil)}
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

  ## Events: posts

  @impl true
  def handle_event("approve", %{"id" => id}, socket) do
    case Posts.approve(Posts.get_post!(id)) do
      {:ok, _} -> {:noreply, put_flash(socket, :info, "Scheduled")}
      {:error, r} -> {:noreply, put_flash(socket, :error, "Can't schedule: #{inspect(r)}")}
    end
  end

  ## Events: create

  def handle_event("create_change", %{"create" => params}, socket),
    do: {:noreply, assign_create(socket, params)}

  def handle_event("create", %{"create" => params}, socket) do
    ch = socket.assigns.channel
    note = String.trim(params["note"] || "")

    with true <- params["post_type"] in socket.assigns.post_types || {:error, :bad_type},
         {:ok, at} <- made_for(ch, params),
         {:ok, _post} <-
           Content.create(ch, %{
             post_type: params["post_type"],
             scheduled_at: at,
             admin_note: if(note != "", do: note)
           }) do
      {:noreply,
       socket
       |> put_flash(:info, "Creating it now. It's uploaded to S3 when done.")
       |> assign_create(Map.take(params, ["post_type", "date"]))}
    else
      {:error, reason} -> {:noreply, put_flash(socket, :error, explain(reason))}
    end
  end

  defp explain(:bad_type), do: "Pick a post type."
  defp explain(:bad_date), do: "Pick a match day from today on."
  defp explain(other), do: inspect(other)

  # The time is picked when scheduling. A fixture is made for the match day
  # chosen here, anything else for tomorrow (the agent uses it for dates).
  defp made_for(ch, %{"post_type" => "fixture"} = params) do
    today = DateTime.now!(ch.timezone) |> DateTime.to_date()

    case Date.from_iso8601(params["date"] || "") do
      {:ok, date} ->
        if Date.compare(date, today) == :lt,
          do: {:error, :bad_date},
          else: {:ok, Channels.made_for(ch, date)}

      _ ->
        {:error, :bad_date}
    end
  end

  defp made_for(ch, _params), do: {:ok, Channels.made_for(ch)}

  defp assign_create(socket, params) do
    ch = socket.assigns.channel
    types = Channels.post_types(ch)
    params = params || %{}
    type = if params["post_type"] in types, do: params["post_type"], else: List.first(types)

    date =
      params["date"] || ch.timezone |> DateTime.now!() |> DateTime.to_date() |> Date.to_iso8601()

    form =
      to_form(%{"post_type" => type, "date" => date, "note" => params["note"] || ""},
        as: :create
      )

    assign(socket, post_types: types, create_form: form)
  end

  ## Render

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      nav_channels={@nav_channels}
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
        </:actions>
      </.page_header>

      <div class="-mt-3 text-right">
        <.link navigate={~p"/channels/#{@channel.id}/settings"} class="text-xs muted hover:underline">
          Channel settings →
        </.link>
      </div>

      <.create_panel
        form={@create_form}
        post_types={@post_types}
        channel={@channel}
      />
      <.week days={@days} today={@today} channel={@channel} />
    </Layouts.app>
    """
  end

  attr :form, :any, required: true
  attr :post_types, :list, required: true
  attr :channel, :map, required: true

  defp create_panel(assigns) do
    ~H"""
    <section class="rounded-lg border-2 border-base-content p-4">
      <.form
        for={@form}
        id="create-form"
        phx-change="create_change"
        phx-submit="create"
        class={[
          "grid gap-3 md:items-end",
          if(@form[:post_type].value == "fixture",
            do: "md:grid-cols-[180px_180px_minmax(0,1fr)_auto]",
            else: "md:grid-cols-[180px_minmax(0,1fr)_auto]"
          )
        ]}
      >
        <.input
          field={@form[:post_type]}
          type="select"
          label="Post type"
          options={Enum.map(@post_types, &{post_type_label(&1), &1})}
        />
        <.input
          :if={@form[:post_type].value == "fixture"}
          field={@form[:date]}
          type="date"
          label="Match day"
        />
        <.input
          field={@form[:note]}
          type="text"
          label="Note for the agent (optional)"
          placeholder={
            if @form[:post_type].value == "fixture",
              do: "optional: name one match to make only that one",
              else: "e.g. warmer tone, a startup from Bengaluru"
          }
        />
        <div class="fieldset mb-2">
          <button id="create-button" class="btn btn-primary" phx-disable-with="Queuing…">
            <.icon name="hero-sparkles" class="size-4" /> Create
          </button>
        </div>
      </.form>
      <p class="text-xs muted mt-1">
        {if @form[:post_type].value == "fixture",
          do:
            "Claude finds every relevant match that day (up to 6). Each becomes its own fixture post with its own result post: enter the score there after the match.",
          else: "One click makes one post: Claude writes it, it's rendered, then uploaded to S3."} Pull it on the Content page and pick its time when you schedule it.
      </p>
    </section>
    """
  end

  attr :days, :list, required: true
  attr :today, Date, required: true
  attr :channel, :map, required: true

  defp week(assigns) do
    ~H"""
    <.empty :if={@days == []} text="No posts yet. Create one above." />

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
end
