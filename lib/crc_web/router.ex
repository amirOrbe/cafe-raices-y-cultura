defmodule CRCWeb.Router do
  use CRCWeb, :router

  import CRCWeb.UserAuth,
    only: [
      fetch_current_user: 2,
      redirect_if_authenticated: 2,
      require_authenticated_user: 2,
      require_admin: 2
    ]

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {CRCWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :require_auth do
    plug :require_authenticated_user
  end

  pipeline :require_admin_role do
    plug :require_admin
  end

  # ---------------------------------------------------------------------------
  # Public routes — no authentication required
  # ---------------------------------------------------------------------------

  scope "/", CRCWeb do
    get "/sitemap.xml", SitemapController, :index
  end

  scope "/", CRCWeb do
    pipe_through :browser

    live_session :public,
      on_mount: [{CRCWeb.UserAuth, :fetch_current_user}] do
      live "/", HomeLive
      live "/menu", MenuLive
      live "/colaboraciones", ColaboracionesLive
    end
  end

  # ---------------------------------------------------------------------------
  # Authentication — only accessible without an active session
  # ---------------------------------------------------------------------------

  scope "/", CRCWeb do
    pipe_through [:browser, :redirect_if_authenticated]

    get "/iniciar-sesion", SessionController, :new
    post "/iniciar-sesion", SessionController, :create
  end

  # ---------------------------------------------------------------------------
  # Logout — requires active session
  # ---------------------------------------------------------------------------

  scope "/", CRCWeb do
    pipe_through [:browser, :require_auth]

    delete "/cerrar-sesion", SessionController, :delete
  end

  # ---------------------------------------------------------------------------
  # Admin panel — requires admin role
  # ---------------------------------------------------------------------------

  scope "/admin", CRCWeb.Admin, as: :admin do
    pipe_through [:browser, :require_auth, :require_admin_role]

    live_session :admin,
      on_mount: [{CRCWeb.UserAuth, :require_admin}],
      layout: {CRCWeb.Layouts, :admin} do
      live "/", DashboardLive
      live "/usuarios", UsersLive
    end
  end

  # ---------------------------------------------------------------------------
  # Stations — requires active session
  # ---------------------------------------------------------------------------

  # scope "/mesa", CRCWeb.Waiter, as: :waiter do
  #   pipe_through [:browser, :require_auth]
  #   live "/:mesa", OrderLive
  # end

  # scope "/cocina", CRCWeb.Kitchen, as: :kitchen do
  #   pipe_through [:browser, :require_auth]
  #   live "/", DisplayLive
  # end

  # ---------------------------------------------------------------------------
  # Development tools
  # ---------------------------------------------------------------------------

  if Application.compile_env(:crc, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: CRCWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
