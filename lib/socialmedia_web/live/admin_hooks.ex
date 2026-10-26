defmodule SocialmediaWeb.AdminHooks do
  @moduledoc "Sidebar data for every admin page, kept live via post updates."
  import Phoenix.Component
  import Phoenix.LiveView
  alias Socialmedia.{Channels, Posts}

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket), do: Posts.subscribe()

    socket =
      socket
      |> assign(:current_path, "/")
      |> assign_nav()
      |> attach_hook(:nav_refresh, :handle_info, fn
        {:post_updated, _}, socket -> {:cont, assign_nav(socket)}
        _, socket -> {:cont, socket}
      end)
      |> attach_hook(:nav_path, :handle_params, fn _params, url, socket ->
        {:cont, assign(socket, :current_path, URI.parse(url).path)}
      end)

    {:cont, socket}
  end

  def assign_nav(socket) do
    now = DateTime.utc_now()
    counts = Posts.status_counts(now, DateTime.add(now, 8 * 86_400))

    channels =
      for ch <- Channels.list_channels() do
        c = Map.get(counts, ch.id, %{})
        %{channel: ch, review: Map.get(c, "needs_review", 0), failed: Map.get(c, "failed", 0)}
      end

    assign(socket, :nav_channels, channels)
  end
end
