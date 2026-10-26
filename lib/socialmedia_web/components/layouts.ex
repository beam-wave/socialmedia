defmodule SocialmediaWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use SocialmediaWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Admin shell: channel sidebar on the left, page content on the right.
  Expects `nav_channels` and `current_path` from `SocialmediaWeb.AdminHooks`.
  """
  attr :flash, :map, required: true
  attr :nav_channels, :list, default: []
  attr :current_path, :string, default: "/"
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="min-h-screen lg:grid lg:grid-cols-[240px_1fr]">
      <aside class="border-b lg:border-b-0 lg:border-r hairline lg:sticky lg:top-0 lg:h-screen flex flex-col">
        <div class="px-5 pt-5 pb-4 flex items-center justify-between">
          <.link navigate={~p"/"} class="font-semibold tracking-tight">Content desk</.link>
          <.theme_toggle />
        </div>

        <nav class="px-3 text-sm space-y-0.5">
          <.nav_item path={~p"/content"} current={@current_path} icon="hero-inbox-stack">
            Content
            <span
              :if={(ready = Enum.sum(Enum.map(@nav_channels, & &1.review))) > 0}
              class="ml-auto rounded-full bg-base-content text-base-100 px-1.5 text-[10px] font-semibold tabular-nums"
            >
              {ready}
            </span>
          </.nav_item>
          <.nav_item path={~p"/"} current={@current_path} icon="hero-squares-2x2">
            This week
          </.nav_item>
        </nav>

        <div class="px-5 pt-6 pb-2 text-[11px] uppercase tracking-wider faint">Channels</div>
        <nav class="px-3 text-sm space-y-0.5 overflow-y-auto">
          <.link
            :for={%{channel: ch, review: review, failed: failed} <- @nav_channels}
            navigate={~p"/channels/#{ch.id}"}
            class={[
              "flex items-center justify-between rounded-md px-2 py-1.5 transition-colors",
              if(String.starts_with?(@current_path, "/channels/#{ch.id}"),
                do: "surface font-medium",
                else: "row-hover"
              )
            ]}
          >
            <span class={["truncate", !ch.active && "faint line-through"]}>{ch.handle}</span>
            <span class="flex items-center gap-1">
              <span
                :if={failed > 0}
                title="Failed"
                class="rounded-full border-2 border-base-content px-1.5 text-[10px] font-semibold"
              >
                !{failed}
              </span>
              <span
                :if={review > 0}
                title="Ready to schedule"
                class="rounded-full bg-base-content text-base-100 px-1.5 text-[10px] font-semibold tabular-nums"
              >
                {review}
              </span>
            </span>
          </.link>
          <.link
            navigate={~p"/channels/new"}
            class="flex items-center gap-1.5 rounded-md px-2 py-1.5 muted row-hover"
          >
            <.icon name="hero-plus" class="size-3.5" /> Add channel
          </.link>
        </nav>

        <div class="mt-auto px-5 py-4 border-t hairline text-xs space-y-2">
          <a href="/oban" class="muted hover:text-base-content inline-flex items-center gap-1">
            <.icon name="hero-queue-list" class="size-3.5" /> Jobs
          </a>
        </div>
      </aside>

      <main class="px-4 sm:px-8 py-8 min-w-0">
        <div class="mx-auto max-w-6xl space-y-6">
          {render_slot(@inner_block)}
        </div>
      </main>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  attr :path, :string, required: true
  attr :current, :string, required: true
  attr :icon, :string, required: true
  slot :inner_block, required: true

  defp nav_item(assigns) do
    ~H"""
    <.link
      navigate={@path}
      class={[
        "flex items-center gap-2 rounded-md px-2 py-1.5 transition-colors",
        if(@current == @path, do: "surface font-medium", else: "row-hover")
      ]}
    >
      <.icon name={@icon} class="size-4" />
      {render_slot(@inner_block)}
    </.link>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
