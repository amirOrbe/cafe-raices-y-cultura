defmodule CRCWeb.Components.SiteComponents do
  @moduledoc "Shared site-wide UI components: navbar, footer, menu item card."

  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: CRCWeb.Endpoint,
    router: CRCWeb.Router,
    statics: CRCWeb.static_paths()

  # ---------------------------------------------------------------------------
  # Navbar
  # ---------------------------------------------------------------------------

  attr :nav_open, :boolean, default: false
  attr :current_page, :atom, default: :home  # :home | :menu | :colaboraciones

  def site_navbar(assigns) do
    ~H"""
    <nav class="fixed top-0 left-0 right-0 z-50 bg-base-100/95 backdrop-blur-sm border-b border-base-300 shadow-sm">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="flex items-center justify-between h-16">

          <!-- Logo / Brand -->
          <a href="/" class="flex items-center group" aria-label="Café Raíces y Cultura — Inicio">
            <img
              src="/images/brand/logo-color.png"
              alt="Café Raíces y Cultura"
              class="h-11 w-auto transition-opacity group-hover:opacity-80"
            />
          </a>

          <!-- Desktop links -->
          <div class="hidden md:flex items-center gap-6">
            <a
              href={if @current_page == :home, do: "#nosotros", else: "/#nosotros"}
              class="text-sm font-medium text-base-content/70 hover:text-primary transition-colors"
            >
              Nosotros
            </a>
            <a
              href={~p"/menu"}
              class={"text-sm font-medium transition-colors #{if @current_page == :menu, do: "text-primary font-semibold", else: "text-base-content/70 hover:text-primary"}"}
            >
              Menú
            </a>
            <a
              href={~p"/colaboraciones"}
              class={"btn btn-sm #{if @current_page == :colaboraciones, do: "btn-neutral", else: "btn-primary"}"}
            >
              Colabora
            </a>
          </div>

          <!-- Mobile hamburger -->
          <button
            phx-click="toggle_nav"
            class="md:hidden btn btn-ghost btn-sm p-1"
            aria-label="Abrir menú"
          >
            <svg :if={!@nav_open} xmlns="http://www.w3.org/2000/svg" class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16M4 18h16" />
            </svg>
            <svg :if={@nav_open} xmlns="http://www.w3.org/2000/svg" class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>
      </div>

      <!-- Mobile dropdown -->
      <div :if={@nav_open} class="md:hidden border-t border-base-300 bg-base-100 px-4 py-3 space-y-2">
        <a
          href={if @current_page == :home, do: "#nosotros", else: "/#nosotros"}
          phx-click="close_nav"
          class="block py-2 text-base font-medium text-base-content/80 hover:text-primary"
        >
          Nosotros
        </a>
        <a href={~p"/menu"} phx-click="close_nav" class="block py-2 text-base font-medium text-base-content/80 hover:text-primary">
          Menú
        </a>
        <a
          href={~p"/colaboraciones"}
          phx-click="close_nav"
          class="block py-2"
        >
          <span class="btn btn-primary btn-sm w-full">Colabora con nosotros</span>
        </a>
      </div>
    </nav>
    """
  end

  # ---------------------------------------------------------------------------
  # Footer
  # ---------------------------------------------------------------------------

  def site_footer(assigns) do
    ~H"""
    <footer class="bg-neutral text-neutral-content py-8 sm:py-10">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="flex flex-col sm:flex-row items-center justify-between gap-4">
          <a href="/" aria-label="Café Raíces y Cultura — Inicio">
            <img
              src="/images/brand/logo-white.png"
              alt="Café Raíces y Cultura"
              class="h-12 w-auto opacity-90 hover:opacity-100 transition-opacity"
            />
          </a>

          <nav class="flex gap-5 text-sm text-neutral-content/70">
            <a href="/#nosotros" class="hover:text-neutral-content transition-colors">Nosotros</a>
            <a href={~p"/menu"} class="hover:text-neutral-content transition-colors">Menú</a>
            <a href={~p"/colaboraciones"} class="hover:text-neutral-content transition-colors">Colaboraciones</a>
            <a href="/#contacto" class="hover:text-neutral-content transition-colors">Contacto</a>
          </nav>

          <div class="flex items-center gap-4">
            <p class="text-xs text-neutral-content/50">
              © {Date.utc_today().year} Café Raíces y Cultura
            </p>
            <a href="/iniciar-sesion" class="text-xs text-neutral-content/30 hover:text-neutral-content/50 transition-colors">
              Acceso personal
            </a>
          </div>
        </div>
      </div>
    </footer>
    """
  end

  # ---------------------------------------------------------------------------
  # Menu item card  (matches the screenshot design)
  # ---------------------------------------------------------------------------

  attr :item, :map, required: true

  def menu_item_card(assigns) do
    ~H"""
    <div class="bg-base-100 border border-base-300 rounded-2xl p-5 sm:p-6 shadow-sm hover:shadow-md transition-shadow flex flex-col gap-3">
      <!-- Name + Price row -->
      <div class="flex items-start justify-between gap-4">
        <h3 class="text-base sm:text-lg font-bold text-base-content leading-snug">
          {@item.name}
        </h3>
        <span class="text-base sm:text-lg font-bold text-primary whitespace-nowrap flex-shrink-0">
          ${format_price(@item.price)}
        </span>
      </div>

      <!-- Description -->
      <p :if={not is_nil(Map.get(@item, :description)) and Map.get(@item, :description) != ""} class="text-sm text-base-content/60 leading-relaxed">
        {Map.get(@item, :description)}
      </p>

      <!-- Badge -->
      <div :if={Map.get(@item, :featured)} class="mt-auto">
        <span class="inline-block bg-accent/20 text-accent-content border border-accent/40 text-xs font-semibold px-3 py-1 rounded-full">
          Recomendado
        </span>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp format_price(%Decimal{} = price) do
    price |> Decimal.round(0) |> Decimal.to_string()
  end

  defp format_price(price), do: "#{price}"
end
