defmodule CRCWeb.Router do
  use CRCWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {CRCWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", CRCWeb do
    pipe_through :browser

    live "/", HomeLive
  end

  # Future scopes — ready to expand
  # scope "/admin", CRCWeb.Admin, as: :admin do
  #   pipe_through [:browser, :require_admin]
  #   live "/", DashboardLive
  #   live "/menu", MenuLive
  #   live "/reservaciones", BookingsLive
  # end

  # scope "/mesa", CRCWeb.Waiter, as: :waiter do
  #   pipe_through [:browser, :require_waiter]
  #   live "/:table", OrderLive
  # end

  # scope "/cocina", CRCWeb.Kitchen, as: :kitchen do
  #   pipe_through [:browser, :require_staff]
  #   live "/", DisplayLive
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:crc, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: CRCWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
