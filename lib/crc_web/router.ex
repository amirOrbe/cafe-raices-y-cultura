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
    plug :touch_session
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
      live "/confirmar-email", EmailConfirmLive
      # Customer-facing bill page — no login required
      live "/cuenta/:token", CuentaLive
      live "/recuperar-contrasena", ForgotPasswordLive
      live "/recuperar-contrasena/:token", ResetPasswordLive
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
  # Staff tools — any authenticated user (all roles)
  # ---------------------------------------------------------------------------

  scope "/", CRCWeb do
    pipe_through [:browser, :require_auth]

    live_session :staff,
      on_mount: [{CRCWeb.UserAuth, :require_authenticated_user}] do
      live "/bitacora", BitacoraLive
      live "/produccion", ProduccionLive
    end
  end

  # ---------------------------------------------------------------------------
  # Employee self-service — any authenticated non-client user
  # ---------------------------------------------------------------------------

  scope "/", CRCWeb.Employee, as: :employee do
    pipe_through [:browser, :require_auth]

    live_session :employee,
      on_mount: [{CRCWeb.UserAuth, :require_authenticated_user}] do
      live "/mi-horario", MyScheduleLive
      live "/mi-perfil", ProfileLive
      live "/calendario", CalendarioLive
    end
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
      live "/platillos", PlatillosLive
      live "/platillos/categorias", CategoriesLive
      live "/paquetes", PackagesLive
      live "/proveedores", SuppliersLive
      live "/insumos", ProductsLive
      live "/insumos/categorias", ProductCategoriesLive
      live "/insumos/merma", MermaLive
      live "/inventario", InventarioLive
      live "/eventos", EventsLive
      live "/colaboradores", CollaboratorsLive
      live "/eventos/tipos", EventTypesLive
      live "/ventas", VentasLive
      live "/ventas/manual", VentaManualLive
      live "/rendimiento", RendimientoLive
      live "/finanzas", FinanzasLive
      live "/mesas", MesasLive
      live "/descuentos", DescuentosLive
      live "/horarios", HorariosLive
      live "/asistencia", AsistenciaLive
      live "/calendario", CalendarioLive
      live "/cumpleanos", CumpleanosLive
      live "/configuracion", ConfiguracionLive
      live "/produccion", ProduccionLive
    end
  end

  # ---------------------------------------------------------------------------
  # Stations — requires active session
  # ---------------------------------------------------------------------------

  scope "/mesa", CRCWeb.Waiter, as: :waiter do
    pipe_through [:browser, :require_auth]

    live_session :waiter,
      on_mount: [{CRCWeb.UserAuth, :require_authenticated_user}] do
      live "/", TableLive
      live "/historial", HistorialLive
      live "/:id", OrderLive
    end
  end

  scope "/cocina", CRCWeb.Kitchen, as: :kitchen do
    pipe_through [:browser, :require_auth]

    live_session :kitchen,
      on_mount: [{CRCWeb.UserAuth, :require_authenticated_user}] do
      live "/", DisplayLive
    end
  end

  scope "/barra", CRCWeb.Barra, as: :barra do
    pipe_through [:browser, :require_auth]

    live_session :barra,
      on_mount: [{CRCWeb.UserAuth, :require_authenticated_user}] do
      live "/", DisplayLive
    end
  end

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

  # ---------------------------------------------------------------------------
  # Rolling session — touch the cookie on every request so the 8-hour
  # inactivity timer resets whenever the user opens the app.
  # ---------------------------------------------------------------------------

  defp touch_session(conn, _opts) do
    if get_session(conn, "user_id") do
      put_session(conn, "_active_at", System.system_time(:second))
    else
      conn
    end
  end
end
