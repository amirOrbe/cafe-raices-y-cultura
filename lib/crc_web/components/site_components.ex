defmodule CRCWeb.Components.SiteComponents do
  @moduledoc "Shared site-wide UI components: navbar, footer, and menu item card."

  use Phoenix.Component

  import CRCWeb.CoreComponents, only: [icon: 1]

  use Phoenix.VerifiedRoutes,
    endpoint: CRCWeb.Endpoint,
    router: CRCWeb.Router,
    statics: CRCWeb.static_paths()

  # ---------------------------------------------------------------------------
  # Navbar component
  # ---------------------------------------------------------------------------

  attr :nav_open, :boolean, default: false
  attr :current_page, :atom, default: :home  # :home | :menu | :colaboraciones (colaboraciones page keeps its atom as-is)
  attr :current_user, :map, default: nil

  def site_navbar(assigns) do
    ~H"""
    <nav class="fixed top-0 left-0 right-0 z-50 bg-base-100/95 backdrop-blur-sm border-b border-base-300 shadow-sm">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="flex items-center justify-between h-16 gap-4">

          <%!-- Logo --%>
          <a href="/" class="flex items-center shrink-0 group" aria-label="Café Raíces y Cultura — Inicio">
            <img
              src="/images/brand/logo-color.png"
              alt="Café Raíces y Cultura"
              class="h-11 w-auto transition-opacity group-hover:opacity-80"
            />
          </a>

          <%!-- Desktop links (public) --%>
          <div class="hidden md:flex items-center gap-5 flex-1">
            <a
              href={if @current_page == :home, do: "#nosotros", else: "/#nosotros"}
              class="text-sm font-medium text-base-content/70 hover:text-primary transition-colors whitespace-nowrap"
            >
              Nosotros
            </a>
            <a
              href={~p"/menu"}
              class={"text-sm font-medium transition-colors whitespace-nowrap #{if @current_page == :menu, do: "text-primary font-semibold", else: "text-base-content/70 hover:text-primary"}"}
            >
              Menú
            </a>
            <a
              href={~p"/colaboraciones"}
              class={"btn btn-sm whitespace-nowrap #{if @current_page == :colaboraciones, do: "btn-neutral", else: "btn-primary"}"}
            >
              Colabora
            </a>
          </div>

          <%!-- Right side: staff links dropdown + hamburger --%>
          <div class="flex items-center gap-2 shrink-0">

            <%!-- Desktop: staff dropdown (visible md+) --%>
            <%= if @current_user do %>
              <div class="hidden md:block">
                <div class="dropdown dropdown-end">
                  <button tabindex="0" class="flex items-center gap-2 px-2.5 py-1.5 rounded-lg bg-base-200 border border-base-300 hover:bg-base-300 transition-colors cursor-pointer">
                    <div class="size-6 rounded-full bg-primary flex items-center justify-center text-primary-content text-xs font-bold shrink-0">
                      {String.first(@current_user.name) |> String.upcase()}
                    </div>
                    <span class="text-xs font-medium text-base-content/80 max-w-[100px] truncate hidden lg:block">
                      {@current_user.name}
                    </span>
                    <%= if @current_user.station do %>
                      <span class="badge badge-xs badge-ghost hidden lg:inline-flex">{@current_user.station}</span>
                    <% end %>
                    <svg xmlns="http://www.w3.org/2000/svg" class="size-3 text-base-content/40" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
                    </svg>
                  </button>
                  <ul tabindex="0" class="dropdown-content z-50 menu menu-sm bg-base-100 rounded-2xl shadow-xl border border-base-300 w-52 mt-2 p-2 space-y-0.5">
                    <%!-- User info header --%>
                    <li class="px-3 py-2 border-b border-base-200 mb-1 pointer-events-none">
                      <p class="text-sm font-semibold text-base-content">{@current_user.name}</p>
                      <p class="text-xs text-base-content/50">
                        {if @current_user.role == "admin", do: "Administrador", else: "Empleado"}
                        {if @current_user.station, do: " · #{@current_user.station}", else: ""}
                      </p>
                    </li>
                    <%!-- Admin links --%>
                    <%= if @current_user.role == "admin" do %>
                      <li>
                        <a href="/admin" class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm hover:bg-base-200">
                          <.icon name="hero-squares-2x2" class="size-4 text-base-content/50" />
                          Panel
                        </a>
                      </li>
                      <li>
                        <a href="/mesa" class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm hover:bg-base-200">
                          <.icon name="hero-clipboard-document-list" class="size-4 text-base-content/50" />
                          Comandas
                        </a>
                      </li>
                      <li>
                        <a href="/mesa/historial" class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm hover:bg-base-200">
                          <.icon name="hero-clock" class="size-4 text-base-content/50" />
                          Historial
                        </a>
                      </li>
                      <li>
                        <a href="/cocina" class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm hover:bg-base-200">
                          <.icon name="hero-fire" class="size-4 text-base-content/50" />
                          Cocina
                        </a>
                      </li>
                      <li>
                        <a href="/barra" class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm hover:bg-base-200">
                          <.icon name="hero-beaker" class="size-4 text-base-content/50" />
                          Barra
                        </a>
                      </li>
                    <% end %>
                    <%!-- Empleado links --%>
                    <%= if @current_user.role == "empleado" do %>
                      <%= if @current_user.station == "sala" do %>
                        <li>
                          <a href="/mesa" class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm hover:bg-base-200">
                            <.icon name="hero-clipboard-document-list" class="size-4 text-base-content/50" />
                            Comandas
                          </a>
                        </li>
                        <li>
                          <a href="/mesa/historial" class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm hover:bg-base-200">
                            <.icon name="hero-clock" class="size-4 text-base-content/50" />
                            Historial
                          </a>
                        </li>
                      <% end %>
                      <%= if @current_user.station == "cocina" do %>
                        <li>
                          <a href="/cocina" class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm hover:bg-base-200">
                            <.icon name="hero-fire" class="size-4 text-base-content/50" />
                            Cocina
                          </a>
                        </li>
                      <% end %>
                      <%= if @current_user.station == "barra" do %>
                        <li>
                          <a href="/barra" class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm hover:bg-base-200">
                            <.icon name="hero-beaker" class="size-4 text-base-content/50" />
                            Barra
                          </a>
                        </li>
                      <% end %>
                    <% end %>
                    <%!-- Divider + logout --%>
                    <li class="border-t border-base-200 mt-1 pt-1">
                      <form action="/cerrar-sesion" method="post">
                        <input type="hidden" name="_method" value="delete" />
                        <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
                        <button type="submit" class="flex items-center gap-2 w-full rounded-lg px-3 py-2 text-sm text-error hover:bg-error/10 transition-colors">
                          <.icon name="hero-arrow-right-on-rectangle" class="size-4" />
                          Cerrar sesión
                        </button>
                      </form>
                    </li>
                  </ul>
                </div>
              </div>
            <% else %>
              <a href="/iniciar-sesion" class="hidden md:inline-flex btn btn-sm btn-ghost text-base-content/60 hover:text-base-content">
                Iniciar sesión
              </a>
            <% end %>

            <%!-- Hamburger (mobile only) --%>
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
      </div>

      <%!-- Mobile dropdown --%>
      <div :if={@nav_open} class="md:hidden border-t border-base-300 bg-base-100 px-4 py-3 space-y-1">
        <%!-- Public links --%>
        <a
          href={if @current_page == :home, do: "#nosotros", else: "/#nosotros"}
          phx-click="close_nav"
          class="flex items-center gap-3 py-2.5 px-2 text-base font-medium text-base-content/80 hover:text-primary rounded-lg hover:bg-base-200 transition-colors"
        >
          Nosotros
        </a>
        <a href={~p"/menu"} phx-click="close_nav" class="flex items-center gap-3 py-2.5 px-2 text-base font-medium text-base-content/80 hover:text-primary rounded-lg hover:bg-base-200 transition-colors">
          Menú
        </a>
        <a href={~p"/colaboraciones"} phx-click="close_nav" class="flex items-center gap-3 py-2.5 px-2 text-base font-medium text-base-content/80 hover:text-primary rounded-lg hover:bg-base-200 transition-colors">
          Colaboraciones
        </a>

        <%= if @current_user do %>
          <%!-- User identity --%>
          <div class="flex items-center gap-3 py-3 px-2 mt-2 border-t border-base-300">
            <div class="size-9 rounded-full bg-primary flex items-center justify-center text-primary-content text-sm font-bold shrink-0">
              {String.first(@current_user.name) |> String.upcase()}
            </div>
            <div class="min-w-0">
              <p class="text-sm font-semibold text-base-content truncate">{@current_user.name}</p>
              <p class="text-xs text-base-content/50">
                {if @current_user.role == "admin", do: "Administrador", else: "Empleado"}
                {if @current_user.station, do: " · #{@current_user.station}", else: ""}
              </p>
            </div>
          </div>

          <%!-- Staff links --%>
          <div class="space-y-1 pb-1">
            <%= if @current_user.role == "admin" do %>
              <a href="/admin" phx-click="close_nav" class="flex items-center gap-3 py-2.5 px-2 text-sm font-medium text-base-content rounded-lg hover:bg-base-200 transition-colors">
                <.icon name="hero-squares-2x2" class="size-5 text-primary" /> Panel de administración
              </a>
              <a href="/mesa" phx-click="close_nav" class="flex items-center gap-3 py-2.5 px-2 text-sm font-medium text-base-content rounded-lg hover:bg-base-200 transition-colors">
                <.icon name="hero-clipboard-document-list" class="size-5 text-primary" /> Comandas
              </a>
              <a href="/mesa/historial" phx-click="close_nav" class="flex items-center gap-3 py-2.5 px-2 text-sm font-medium text-base-content rounded-lg hover:bg-base-200 transition-colors">
                <.icon name="hero-clock" class="size-5 text-primary" /> Historial de comandas
              </a>
              <a href="/cocina" phx-click="close_nav" class="flex items-center gap-3 py-2.5 px-2 text-sm font-medium text-base-content rounded-lg hover:bg-base-200 transition-colors">
                <.icon name="hero-fire" class="size-5 text-primary" /> Cocina
              </a>
              <a href="/barra" phx-click="close_nav" class="flex items-center gap-3 py-2.5 px-2 text-sm font-medium text-base-content rounded-lg hover:bg-base-200 transition-colors">
                <.icon name="hero-beaker" class="size-5 text-primary" /> Barra
              </a>
            <% end %>
            <%= if @current_user.role == "empleado" do %>
              <%= if @current_user.station == "sala" do %>
                <a href="/mesa" phx-click="close_nav" class="flex items-center gap-3 py-2.5 px-2 text-sm font-medium text-base-content rounded-lg hover:bg-base-200 transition-colors">
                  <.icon name="hero-clipboard-document-list" class="size-5 text-primary" /> Comandas
                </a>
                <a href="/mesa/historial" phx-click="close_nav" class="flex items-center gap-3 py-2.5 px-2 text-sm font-medium text-base-content rounded-lg hover:bg-base-200 transition-colors">
                  <.icon name="hero-clock" class="size-5 text-primary" /> Historial
                </a>
              <% end %>
              <%= if @current_user.station == "cocina" do %>
                <a href="/cocina" phx-click="close_nav" class="flex items-center gap-3 py-2.5 px-2 text-sm font-medium text-base-content rounded-lg hover:bg-base-200 transition-colors">
                  <.icon name="hero-fire" class="size-5 text-primary" /> Cocina
                </a>
              <% end %>
              <%= if @current_user.station == "barra" do %>
                <a href="/barra" phx-click="close_nav" class="flex items-center gap-3 py-2.5 px-2 text-sm font-medium text-base-content rounded-lg hover:bg-base-200 transition-colors">
                  <.icon name="hero-beaker" class="size-5 text-primary" /> Barra
                </a>
              <% end %>
            <% end %>
          </div>

          <%!-- Logout --%>
          <div class="border-t border-base-300 pt-2">
            <form action="/cerrar-sesion" method="post">
              <input type="hidden" name="_method" value="delete" />
              <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
              <button type="submit" class="flex items-center gap-3 w-full py-2.5 px-2 text-sm font-medium text-error rounded-lg hover:bg-error/10 transition-colors">
                <.icon name="hero-arrow-right-on-rectangle" class="size-5" /> Cerrar sesión
              </button>
            </form>
          </div>
        <% else %>
          <div class="border-t border-base-300 pt-2">
            <a href="/iniciar-sesion" phx-click="close_nav" class="flex items-center justify-center py-2.5 px-2 text-sm text-base-content/60 hover:text-base-content rounded-lg hover:bg-base-200 transition-colors">
              Iniciar sesión
            </a>
          </div>
        <% end %>
      </div>
    </nav>
    """
  end

  # ---------------------------------------------------------------------------
  # Footer component
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
  # Menu item card
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

      <!-- Ingredient quantities -->
      <% ingredients = Map.get(@item, :menu_item_ingredients, []) %>
      <%= if is_list(ingredients) and ingredients != [] do %>
        <div class="flex flex-wrap gap-1.5">
          <%= for mii <- ingredients do %>
            <span class="inline-flex items-center gap-1 text-xs bg-base-200 text-base-content/60 rounded-full px-2.5 py-0.5">
              {mii.product.name}
              <span class="font-medium text-base-content/80">{format_qty(mii.quantity)}{mii.product.unit}</span>
            </span>
          <% end %>
        </div>
      <% end %>

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
  # Private helpers
  # ---------------------------------------------------------------------------

  defp format_price(%Decimal{} = price) do
    price |> Decimal.round(0) |> Decimal.to_string()
  end

  defp format_price(price), do: "#{price}"

  defp format_qty(%Decimal{} = qty) do
    str = qty |> Decimal.round(3) |> Decimal.to_string()

    if String.contains?(str, ".") do
      str |> String.trim_trailing("0") |> String.trim_trailing(".")
    else
      str
    end
  end

  defp format_qty(qty), do: "#{qty}"
end
