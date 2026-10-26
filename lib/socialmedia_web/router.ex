defmodule SocialmediaWeb.Router do
  use SocialmediaWeb, :router
  import Oban.Web.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SocialmediaWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :admin do
    plug SocialmediaWeb.Plugs.AdminAuth
  end

  scope "/", SocialmediaWeb do
    pipe_through [:browser, :admin]

    live_session :admin, on_mount: SocialmediaWeb.AdminHooks do
      live "/", DashboardLive, :index
      live "/content", ContentLive, :index
      live "/channels/new", ChannelLive.Settings, :new
      live "/channels/:id", ChannelLive.Show, :week
      live "/channels/:id/settings", ChannelLive.Settings, :edit
      live "/posts/:id", PostLive.Show, :show
    end

    oban_dashboard("/oban")
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:socialmedia, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: SocialmediaWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
