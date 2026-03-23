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
  # Rutas públicas sin autenticación
  # ---------------------------------------------------------------------------

  scope "/", CRCWeb do
    get "/sitemap.xml", SitemapController, :index
  end

  scope "/", CRCWeb do
    pipe_through :browser

    live "/", HomeLive
    live "/menu", MenuLive
    live "/colaboraciones", ColaboracionesLive
  end

  # ---------------------------------------------------------------------------
  # Autenticación — solo accesibles sin sesión activa
  # ---------------------------------------------------------------------------

  scope "/", CRCWeb do
    pipe_through [:browser, :redirect_if_authenticated]

    get "/iniciar-sesion", SessionController, :new
    post "/iniciar-sesion", SessionController, :create
  end

  # ---------------------------------------------------------------------------
  # Cerrar sesión — requiere sesión activa
  # ---------------------------------------------------------------------------

  scope "/", CRCWeb do
    pipe_through [:browser, :require_auth]

    delete "/cerrar-sesion", SessionController, :delete
  end

  # ---------------------------------------------------------------------------
  # Panel de administración — requiere rol admin
  # ---------------------------------------------------------------------------

  # scope "/admin", CRCWeb.Admin, as: :admin do
  #   pipe_through [:browser, :require_auth, :require_admin_role]
  #   live "/", DashboardLive
  #   live "/usuarios", UsersLive
  #   live "/menu", MenuLive
  #   live "/reservaciones", BookingsLive
  # end

  # ---------------------------------------------------------------------------
  # Estaciones — requiere sesión activa
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
  # Herramientas de desarrollo
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
