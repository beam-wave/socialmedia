defmodule SocialmediaWeb.ChannelLive.Settings do
  @moduledoc "Create or edit a channel: identity, agent skill, Instagram connection, template defaults."
  use SocialmediaWeb, :live_view
  import SocialmediaWeb.AdminComponents
  alias Socialmedia.{Channels, Paths}
  alias Socialmedia.Channels.Channel
  alias Socialmedia.Instagram.Graph

  @impl true
  def mount(params, _session, socket) do
    channel =
      case params do
        %{"id" => id} -> Channels.get_channel!(id)
        _ -> %Channel{base_data: %{}}
      end

    {:ok,
     socket
     |> assign(
       channel: channel,
       page_title: if(channel.id, do: "#{channel.handle} settings", else: "New channel"),
       skills: list_dirs(Path.join([Paths.agent_dir(), ".claude", "skills"])),
       templates: list_dirs(Paths.channels_dir()) |> Enum.reject(&String.starts_with?(&1, "_")),
       base_json: Jason.encode!(channel.base_data || %{}, pretty: true),
       json_error: nil,
       check: nil
     )
     |> assign_form(Channels.change_channel(channel))}
  end

  defp assign_form(socket, cs), do: assign(socket, :form, to_form(cs))

  defp list_dirs(dir) do
    case File.ls(dir) do
      {:ok, names} -> names |> Enum.filter(&File.dir?(Path.join(dir, &1))) |> Enum.sort()
      _ -> []
    end
  end

  @impl true
  def handle_event("validate", %{"channel" => params}, socket) do
    {params, socket} = take_json(params, socket)
    cs = Channels.change_channel(socket.assigns.channel, params) |> Map.put(:action, :validate)
    {:noreply, assign_form(socket, cs)}
  end

  def handle_event("save", %{"channel" => params}, socket) do
    {params, socket} = take_json(params, socket)

    if socket.assigns.json_error do
      {:noreply, put_flash(socket, :error, "Fix the template defaults JSON first")}
    else
      save(socket, params)
    end
  end

  def handle_event("check_token", _, socket) do
    ch = socket.assigns.channel

    check =
      case ch.access_token && Graph.me(ch.access_token) do
        nil -> {:error, "Save a token first"}
        {:ok, %{"username" => u, "user_id" => id}} -> {:ok, "Connected as @#{u} (user id #{id})"}
        {:ok, body} -> {:ok, "Connected: #{inspect(body)}"}
        {:error, e} -> {:error, to_string(e)}
      end

    {:noreply, assign(socket, :check, check)}
  end

  defp save(socket, params) do
    # Blank token field means "keep the current token"
    params =
      if params["access_token"] in [nil, ""], do: Map.delete(params, "access_token"), else: params

    result =
      if socket.assigns.channel.id,
        do: Channels.update_channel(socket.assigns.channel, params),
        else: Channels.create_channel(params)

    case result do
      {:ok, ch} ->
        {:noreply,
         socket
         |> put_flash(:info, "Saved")
         |> push_navigate(to: ~p"/channels/#{ch.id}/settings")}

      {:error, cs} ->
        {:noreply, assign_form(socket, cs)}
    end
  end

  defp take_json(params, socket) do
    raw = Map.get(params, "base_data_json", socket.assigns.base_json)

    case Jason.decode(raw) do
      {:ok, map} when is_map(map) ->
        {params |> Map.delete("base_data_json") |> Map.put("base_data", map),
         assign(socket, base_json: raw, json_error: nil)}

      _ ->
        {Map.delete(params, "base_data_json"),
         assign(socket, base_json: raw, json_error: "Not valid JSON object")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      nav_channels={@nav_channels}
      current_path={@current_path}
    >
      <div :if={@channel.id} class="text-xs muted">
        <.link navigate={~p"/channels/#{@channel.id}"} class="hover:underline">
          ← {@channel.handle}
        </.link>
      </div>
      <.page_header
        title={if @channel.id, do: "Settings", else: "New channel"}
        subtitle="Identity, agent skill, Instagram connection and template defaults."
      />

      <.form for={@form} phx-change="validate" phx-submit="save" class="space-y-8 max-w-3xl">
        <section class="grid sm:grid-cols-[200px_1fr] gap-x-8 gap-y-2">
          <div>
            <h2 class="text-sm font-semibold">Channel</h2>
            <p class="text-xs muted mt-1">Pausing a channel stops planning new posts.</p>
          </div>
          <div class="grid sm:grid-cols-2 gap-x-4">
            <.input field={@form[:name]} label="Name" />
            <.input field={@form[:handle]} label="Instagram handle" placeholder="@mid.innings" />
            <.input field={@form[:timezone]} label="Timezone" placeholder="Asia/Kolkata" />
            <div class="pt-7"><.input field={@form[:active]} type="checkbox" label="Active" /></div>
          </div>
        </section>

        <section class="grid sm:grid-cols-[200px_1fr] gap-x-8 gap-y-2 border-t hairline pt-6">
          <div>
            <h2 class="text-sm font-semibold">Content</h2>
            <p class="text-xs muted mt-1">
              The skill tells the agent how to write. The template draws the slides.
            </p>
          </div>
          <div class="grid sm:grid-cols-2 gap-x-4">
            <.input
              field={@form[:skill]}
              type="select"
              label="Agent skill"
              options={@skills}
              prompt="Pick a skill"
            />
            <.input
              field={@form[:template_dir]}
              type="select"
              label="Template"
              options={@templates}
              prompt="Pick a template"
            />
            <div class="sm:col-span-2">
              <label class="label mb-1 text-sm" for="base_data_json">Template defaults (JSON)</label>
              <textarea
                id="base_data_json"
                name="channel[base_data_json]"
                rows="8"
                phx-debounce="400"
                class="textarea w-full mono text-xs"
              >{@base_json}</textarea>
              <p :if={@json_error} class="text-xs font-semibold mt-1">{@json_error}</p>
              <p class="text-xs muted mt-1">
                Merged under every post: theme, format, lang, tags.
                <code class="mono">series_start</code>
                {~s({"n": 1})} is the first Day N / quote number; each new post takes the next one.
              </p>
            </div>
          </div>
        </section>

        <section class="grid sm:grid-cols-[200px_1fr] gap-x-8 gap-y-2 border-t hairline pt-6">
          <div>
            <h2 class="text-sm font-semibold">Instagram</h2>
            <p class="text-xs muted mt-1">
              Business or Creator account, via a Meta app (Instagram API with Instagram Login).
            </p>
          </div>
          <div class="space-y-1">
            <div class="grid sm:grid-cols-2 gap-x-4">
              <.input field={@form[:ig_user_id]} label="Instagram user id" />
              <.input
                field={@form[:access_token]}
                type="password"
                value=""
                label="Access token"
                placeholder={
                  if @channel.access_token,
                    do: "•••••• saved (leave blank to keep)",
                    else: "Long-lived token"
                }
                autocomplete="off"
              />
            </div>
            <p class="text-xs muted">
              Token expires: {if @channel.token_expires_at,
                do: local(@channel.token_expires_at, "Etc/UTC", "%d %b %Y"),
                else: "unknown"}. Refreshed weekly on prod.
            </p>
            <div class="flex items-center gap-3 pt-1">
              <button
                :if={@channel.id}
                type="button"
                phx-click="check_token"
                class="btn btn-sm btn-outline"
              >
                Test connection
              </button>
              <span :if={@check} class={["text-xs", elem(@check, 0) == :error && "font-semibold"]}>
                {elem(@check, 1)}
              </span>
            </div>
            <div class="pt-3">
              <.input
                field={@form[:dry_run]}
                type="checkbox"
                label="Dry run (never post this channel, even on prod)"
              />
            </div>
          </div>
        </section>

        <div class="border-t hairline pt-6">
          <button class="btn btn-primary" phx-disable-with="Saving…">Save</button>
        </div>
      </.form>
    </Layouts.app>
    """
  end
end
