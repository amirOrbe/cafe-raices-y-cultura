defmodule CRCWeb.Components.SiteComponents do
  @moduledoc "Shared site-wide UI components: navbar, footer, and menu item card."

  use Phoenix.Component

  import CRCWeb.CoreComponents, only: [icon: 1]
  alias Phoenix.LiveView.JS

  use Phoenix.VerifiedRoutes,
    endpoint: CRCWeb.Endpoint,
    router: CRCWeb.Router,
    statics: CRCWeb.static_paths()

  # ---------------------------------------------------------------------------
  # Navbar component
  # ---------------------------------------------------------------------------

  attr :nav_open, :boolean, default: false
  # :home | :menu | :colaboraciones (colaboraciones page keeps its atom as-is)
  attr :current_page, :atom, default: :home
  attr :current_user, :map, default: nil

  def site_navbar(assigns) do
    ~H"""
    <%!-- contents wrapper lets us have nav + mobile overlay as sibling elements --%>
    <div class="contents">
    <nav class="fixed top-0 left-0 right-0 z-50 bg-base-100/95 backdrop-blur-sm border-b border-base-300 shadow-sm">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="flex items-center justify-between h-16 gap-4">
          <%!-- Logo --%>
          <a
            href="/"
            class="flex items-center shrink-0 group"
            aria-label="Café Raíces y Cultura — Inicio"
          >
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
                  <button
                    tabindex="0"
                    class="flex items-center gap-2 px-2.5 py-1.5 rounded-lg bg-base-200 border border-base-300 hover:bg-base-300 transition-colors cursor-pointer"
                  >
                    <div class="size-6 rounded-full bg-primary flex items-center justify-center text-primary-content text-xs font-bold shrink-0 overflow-hidden">
                      <%= if @current_user.avatar_url do %>
                        <img
                          src={@current_user.avatar_url}
                          alt={@current_user.name}
                          class="size-6 object-cover"
                        />
                      <% else %>
                        {String.first(@current_user.name) |> String.upcase()}
                      <% end %>
                    </div>
                    <span class="text-xs font-medium text-base-content/80 max-w-[100px] truncate hidden lg:block">
                      {@current_user.name}
                    </span>
                    <%= if @current_user.stations != [] do %>
                      <span class="badge badge-xs badge-ghost hidden lg:inline-flex">
                        {Enum.join(@current_user.stations, " · ")}
                      </span>
                    <% end %>
                    <svg
                      xmlns="http://www.w3.org/2000/svg"
                      class="size-3 text-base-content/40"
                      fill="none"
                      viewBox="0 0 24 24"
                      stroke="currentColor"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M19 9l-7 7-7-7"
                      />
                    </svg>
                  </button>
                  <ul
                    tabindex="0"
                    class="dropdown-content z-50 menu menu-sm bg-base-100 rounded-2xl shadow-xl border border-base-300 w-52 mt-2 p-2 space-y-0.5"
                  >
                    <%!-- User info header --%>
                    <li class="px-3 py-2 border-b border-base-200 mb-1 pointer-events-none">
                      <p class="text-sm font-semibold text-base-content">{@current_user.name}</p>
                      <p class="text-xs text-base-content/50">
                        {case @current_user.role do
                          "admin" -> "Administrador"
                          "empleado" -> "Empleado"
                          "cliente" -> "Cliente"
                          _ -> ""
                        end}
                        {if @current_user.stations != [],
                          do: " · #{Enum.join(@current_user.stations, " · ")}",
                          else: ""}
                      </p>
                    </li>
                    <%!-- Cliente links --%>
                    <%= if @current_user.role == "cliente" do %>
                      <li>
                        <a
                          href="/cliente/perfil"
                          class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm hover:bg-base-200"
                        >
                          <.icon name="hero-user-circle" class="size-4 text-base-content/50" />
                          Mi perfil
                        </a>
                      </li>
                      <li>
                        <a
                          href="/cliente/pedidos"
                          class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm hover:bg-base-200"
                        >
                          <.icon name="hero-shopping-bag" class="size-4 text-base-content/50" />
                          Mis pedidos
                        </a>
                      </li>
                    <% end %>
                    <%!-- Staff links (empleado / admin only) --%>
                    <%= if @current_user.role in ["admin", "empleado"] do %>
                      <li>
                        <a
                          href="/mi-perfil"
                          class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm hover:bg-base-200"
                        >
                          <.icon name="hero-user-circle" class="size-4 text-base-content/50" />
                          Mi Perfil
                        </a>
                      </li>
                      <li>
                        <a
                          href="/bitacora"
                          class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm hover:bg-base-200"
                        >
                          <.icon
                            name="hero-clipboard-document-check"
                            class="size-4 text-base-content/50"
                          /> Bitácora de Turno
                        </a>
                      </li>
                      <li>
                        <a
                          href="/produccion"
                          class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm hover:bg-base-200"
                        >
                          <.icon name="hero-beaker" class="size-4 text-base-content/50" /> Producción
                        </a>
                      </li>
                      <%= if @current_user.role == "empleado" do %>
                        <li>
                          <a
                            href="/calendario"
                            class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm hover:bg-base-200"
                          >
                            <.icon name="hero-table-cells" class="size-4 text-base-content/50" /> Calendario
                          </a>
                        </li>
                      <% end %>
                    <% end %>
                    <%!-- Admin links --%>
                    <%= if @current_user.role == "admin" do %>
                      <li>
                        <a
                          href="/admin"
                          class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm hover:bg-base-200"
                        >
                          <.icon name="hero-squares-2x2" class="size-4 text-base-content/50" /> Panel
                        </a>
                      </li>
                      <li>
                        <a
                          href="/mi-horario"
                          class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm hover:bg-base-200"
                        >
                          <.icon name="hero-calendar-days" class="size-4 text-base-content/50" />
                          Mi horario
                        </a>
                      </li>
                      <li>
                        <a
                          href="/mesa"
                          class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm hover:bg-base-200"
                        >
                          <.icon
                            name="hero-clipboard-document-list"
                            class="size-4 text-base-content/50"
                          /> Comandas
                        </a>
                      </li>
                      <li>
                        <a
                          href="/mesa/historial"
                          class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm hover:bg-base-200"
                        >
                          <.icon name="hero-clock" class="size-4 text-base-content/50" /> Historial
                        </a>
                      </li>
                      <li>
                        <a
                          href="/cocina"
                          class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm hover:bg-base-200"
                        >
                          <.icon name="hero-fire" class="size-4 text-base-content/50" /> Cocina
                        </a>
                      </li>
                      <li>
                        <a
                          href="/barra"
                          class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm hover:bg-base-200"
                        >
                          <.icon name="hero-beaker" class="size-4 text-base-content/50" /> Barra
                        </a>
                      </li>
                    <% end %>
                    <%!-- Empleado links --%>
                    <%= if @current_user.role == "empleado" do %>
                      <li>
                        <a
                          href="/mi-horario"
                          class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm hover:bg-base-200"
                        >
                          <.icon name="hero-calendar-days" class="size-4 text-base-content/50" />
                          Mi horario
                        </a>
                      </li>
                      <%= if "sala" in @current_user.stations do %>
                        <li>
                          <a
                            href="/mesa"
                            class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm hover:bg-base-200"
                          >
                            <.icon
                              name="hero-clipboard-document-list"
                              class="size-4 text-base-content/50"
                            /> Comandas
                          </a>
                        </li>
                        <li>
                          <a
                            href="/mesa/historial"
                            class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm hover:bg-base-200"
                          >
                            <.icon name="hero-clock" class="size-4 text-base-content/50" /> Historial
                          </a>
                        </li>
                      <% end %>
                      <%= if "cocina" in @current_user.stations do %>
                        <li>
                          <a
                            href="/cocina"
                            class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm hover:bg-base-200"
                          >
                            <.icon name="hero-fire" class="size-4 text-base-content/50" /> Cocina
                          </a>
                        </li>
                      <% end %>
                      <%= if "barra" in @current_user.stations do %>
                        <li>
                          <a
                            href="/barra"
                            class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm hover:bg-base-200"
                          >
                            <.icon name="hero-beaker" class="size-4 text-base-content/50" /> Barra
                          </a>
                        </li>
                      <% end %>
                    <% end %>
                    <%!-- Divider + logout --%>
                    <li class="border-t border-base-200 mt-1 pt-1">
                      <form action="/cerrar-sesion" method="post">
                        <input type="hidden" name="_method" value="delete" />
                        <input
                          type="hidden"
                          name="_csrf_token"
                          value={Phoenix.Controller.get_csrf_token()}
                        />
                        <button
                          type="submit"
                          class="flex items-center gap-2 w-full rounded-lg px-3 py-2 text-sm text-error hover:bg-error/10 transition-colors"
                        >
                          <.icon name="hero-arrow-right-on-rectangle" class="size-4" /> Cerrar sesión
                        </button>
                      </form>
                    </li>
                  </ul>
                </div>
              </div>
            <% else %>
              <a
                href="/iniciar-sesion"
                class="hidden md:inline-flex btn btn-sm btn-ghost text-base-content/60 hover:text-base-content"
              >
                Iniciar sesión
              </a>
            <% end %>

            <%!-- Hamburger (mobile only) --%>
            <button
              phx-click="toggle_nav"
              class="md:hidden btn btn-ghost btn-sm p-1"
              aria-label="Abrir menú"
            >
              <svg
                :if={!@nav_open}
                xmlns="http://www.w3.org/2000/svg"
                class="h-6 w-6"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M4 6h16M4 12h16M4 18h16"
                />
              </svg>
              <svg
                :if={@nav_open}
                xmlns="http://www.w3.org/2000/svg"
                class="h-6 w-6"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M6 18L18 6M6 6l12 12"
                />
              </svg>
            </button>
          </div>
        </div>
      </div>

    </nav>

    <%!-- Mobile nav overlay — rendered OUTSIDE <nav> so it is a true fixed fullscreen panel.
         backdrop (z-40) blocks page interactions; panel (z-50) scrolls independently. --%>
    <%= if @nav_open do %>
      <%!-- Backdrop: invisible, captures taps outside the panel to close the menu --%>
      <div
        class="fixed inset-0 z-40 md:hidden"
        phx-click="close_nav"
        aria-hidden="true"
      >
      </div>

      <%!-- Scrollable panel: starts right below the navbar (top-16 = 64px) --%>
      <div class="fixed inset-x-0 top-16 bottom-0 z-50 md:hidden bg-base-100 border-t border-base-300 overflow-y-auto overscroll-contain shadow-lg">
        <div class="px-4 py-3 space-y-1 pb-10">
          <%!-- Public links --%>
          <a
            href={if @current_page == :home, do: "#nosotros", else: "/#nosotros"}
            phx-click="close_nav"
            class="flex items-center gap-3 py-2.5 px-2 text-base font-medium text-base-content/80 hover:text-primary rounded-lg hover:bg-base-200 transition-colors"
          >
            Nosotros
          </a>
          <a
            href={~p"/menu"}
            phx-click="close_nav"
            class="flex items-center gap-3 py-2.5 px-2 text-base font-medium text-base-content/80 hover:text-primary rounded-lg hover:bg-base-200 transition-colors"
          >
            Menú
          </a>
          <a
            href={~p"/colaboraciones"}
            phx-click="close_nav"
            class="flex items-center gap-3 py-2.5 px-2 text-base font-medium text-base-content/80 hover:text-primary rounded-lg hover:bg-base-200 transition-colors"
          >
            Colaboraciones
          </a>

          <%= if @current_user do %>
            <%!-- User identity --%>
            <div class="flex items-center gap-3 py-3 px-2 mt-2 border-t border-base-300">
              <div class="size-9 rounded-full bg-primary flex items-center justify-center text-primary-content text-sm font-bold shrink-0 overflow-hidden">
                <%= if @current_user.avatar_url do %>
                  <img
                    src={@current_user.avatar_url}
                    alt={@current_user.name}
                    class="size-9 object-cover"
                  />
                <% else %>
                  {String.first(@current_user.name) |> String.upcase()}
                <% end %>
              </div>
              <div class="min-w-0">
                <p class="text-sm font-semibold text-base-content truncate">{@current_user.name}</p>
                <p class="text-xs text-base-content/50">
                  {case @current_user.role do
                    "admin" -> "Administrador"
                    "empleado" -> "Empleado"
                    "cliente" -> "Cliente"
                    _ -> ""
                  end}
                  {if @current_user.stations != [],
                    do: " · #{Enum.join(@current_user.stations, " · ")}",
                    else: ""}
                </p>
              </div>
            </div>

            <%!-- Cliente links --%>
            <%= if @current_user.role == "cliente" do %>
              <div class="space-y-1 pb-1">
                <a
                  href="/cliente/perfil"
                  phx-click="close_nav"
                  class="flex items-center gap-3 py-2.5 px-2 text-sm font-medium text-base-content rounded-lg hover:bg-base-200 transition-colors"
                >
                  <.icon name="hero-user-circle" class="size-5 text-primary" /> Mi perfil
                </a>
                <a
                  href="/cliente/pedidos"
                  phx-click="close_nav"
                  class="flex items-center gap-3 py-2.5 px-2 text-sm font-medium text-base-content rounded-lg hover:bg-base-200 transition-colors"
                >
                  <.icon name="hero-shopping-bag" class="size-5 text-primary" /> Mis pedidos
                </a>
              </div>
            <% end %>

            <%!-- Staff links (empleado / admin only) --%>
            <%= if @current_user.role in ["admin", "empleado"] do %>
            <div class="space-y-1 pb-1">
              <a
                href="/mi-perfil"
                phx-click="close_nav"
                class="flex items-center gap-3 py-2.5 px-2 text-sm font-medium text-base-content rounded-lg hover:bg-base-200 transition-colors"
              >
                <.icon name="hero-user-circle" class="size-5 text-primary" /> Mi Perfil
              </a>
              <a
                href="/bitacora"
                phx-click="close_nav"
                class="flex items-center gap-3 py-2.5 px-2 text-sm font-medium text-base-content rounded-lg hover:bg-base-200 transition-colors"
              >
                <.icon name="hero-clipboard-document-check" class="size-5 text-primary" />
                Bitácora de Turno
              </a>
              <a
                href="/produccion"
                phx-click="close_nav"
                class="flex items-center gap-3 py-2.5 px-2 text-sm font-medium text-base-content rounded-lg hover:bg-base-200 transition-colors"
              >
                <.icon name="hero-beaker" class="size-5 text-primary" /> Producción
              </a>
              <%= if @current_user.role == "empleado" do %>
                <a
                  href="/calendario"
                  phx-click="close_nav"
                  class="flex items-center gap-3 py-2.5 px-2 text-sm font-medium text-base-content rounded-lg hover:bg-base-200 transition-colors"
                >
                  <.icon name="hero-table-cells" class="size-5 text-primary" /> Calendario de actividades
                </a>
              <% end %>
              <%= if @current_user.role == "admin" do %>
                <a
                  href="/admin"
                  phx-click="close_nav"
                  class="flex items-center gap-3 py-2.5 px-2 text-sm font-medium text-base-content rounded-lg hover:bg-base-200 transition-colors"
                >
                  <.icon name="hero-squares-2x2" class="size-5 text-primary" /> Panel de administración
                </a>
                <a
                  href="/mi-horario"
                  phx-click="close_nav"
                  class="flex items-center gap-3 py-2.5 px-2 text-sm font-medium text-base-content rounded-lg hover:bg-base-200 transition-colors"
                >
                  <.icon name="hero-calendar-days" class="size-5 text-primary" /> Mi horario
                </a>
                <a
                  href="/mesa"
                  phx-click="close_nav"
                  class="flex items-center gap-3 py-2.5 px-2 text-sm font-medium text-base-content rounded-lg hover:bg-base-200 transition-colors"
                >
                  <.icon name="hero-clipboard-document-list" class="size-5 text-primary" /> Comandas
                </a>
                <a
                  href="/mesa/historial"
                  phx-click="close_nav"
                  class="flex items-center gap-3 py-2.5 px-2 text-sm font-medium text-base-content rounded-lg hover:bg-base-200 transition-colors"
                >
                  <.icon name="hero-clock" class="size-5 text-primary" /> Historial de comandas
                </a>
                <a
                  href="/cocina"
                  phx-click="close_nav"
                  class="flex items-center gap-3 py-2.5 px-2 text-sm font-medium text-base-content rounded-lg hover:bg-base-200 transition-colors"
                >
                  <.icon name="hero-fire" class="size-5 text-primary" /> Cocina
                </a>
                <a
                  href="/barra"
                  phx-click="close_nav"
                  class="flex items-center gap-3 py-2.5 px-2 text-sm font-medium text-base-content rounded-lg hover:bg-base-200 transition-colors"
                >
                  <.icon name="hero-beaker" class="size-5 text-primary" /> Barra
                </a>
              <% end %>
              <%= if @current_user.role == "empleado" do %>
                <a
                  href="/mi-horario"
                  phx-click="close_nav"
                  class="flex items-center gap-3 py-2.5 px-2 text-sm font-medium text-base-content rounded-lg hover:bg-base-200 transition-colors"
                >
                  <.icon name="hero-calendar-days" class="size-5 text-primary" /> Mi horario
                </a>
                <%= if "sala" in @current_user.stations do %>
                  <a
                    href="/mesa"
                    phx-click="close_nav"
                    class="flex items-center gap-3 py-2.5 px-2 text-sm font-medium text-base-content rounded-lg hover:bg-base-200 transition-colors"
                  >
                    <.icon name="hero-clipboard-document-list" class="size-5 text-primary" /> Comandas
                  </a>
                  <a
                    href="/mesa/historial"
                    phx-click="close_nav"
                    class="flex items-center gap-3 py-2.5 px-2 text-sm font-medium text-base-content rounded-lg hover:bg-base-200 transition-colors"
                  >
                    <.icon name="hero-clock" class="size-5 text-primary" /> Historial
                  </a>
                <% end %>
                <%= if "cocina" in @current_user.stations do %>
                  <a
                    href="/cocina"
                    phx-click="close_nav"
                    class="flex items-center gap-3 py-2.5 px-2 text-sm font-medium text-base-content rounded-lg hover:bg-base-200 transition-colors"
                  >
                    <.icon name="hero-fire" class="size-5 text-primary" /> Cocina
                  </a>
                <% end %>
                <%= if "barra" in @current_user.stations do %>
                  <a
                    href="/barra"
                    phx-click="close_nav"
                    class="flex items-center gap-3 py-2.5 px-2 text-sm font-medium text-base-content rounded-lg hover:bg-base-200 transition-colors"
                  >
                    <.icon name="hero-beaker" class="size-5 text-primary" /> Barra
                  </a>
                <% end %>
              <% end %>
            </div>
            <% end %>

            <%!-- Logout --%>
            <div class="border-t border-base-300 pt-2">
              <form action="/cerrar-sesion" method="post">
                <input type="hidden" name="_method" value="delete" />
                <input
                  type="hidden"
                  name="_csrf_token"
                  value={Phoenix.Controller.get_csrf_token()}
                />
                <button
                  type="submit"
                  class="flex items-center gap-3 w-full py-2.5 px-2 text-sm font-medium text-error rounded-lg hover:bg-error/10 transition-colors"
                >
                  <.icon name="hero-arrow-right-on-rectangle" class="size-5" /> Cerrar sesión
                </button>
              </form>
            </div>
          <% else %>
            <div class="border-t border-base-300 pt-2">
              <a
                href="/iniciar-sesion"
                phx-click="close_nav"
                class="flex items-center justify-center py-2.5 px-2 text-sm text-base-content/60 hover:text-base-content rounded-lg hover:bg-base-200 transition-colors"
              >
                Iniciar sesión
              </a>
            </div>
          <% end %>
        </div>
      </div>
    <% end %>
    </div>
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
            <a href={~p"/colaboraciones"} class="hover:text-neutral-content transition-colors">
              Colaboraciones
            </a>
            <a href="/#contacto" class="hover:text-neutral-content transition-colors">Contacto</a>
          </nav>

          <div class="flex items-center gap-4">
            <p class="text-xs text-neutral-content/50">
              © {Date.utc_today().year} Café Raíces y Cultura
            </p>
            <a
              href="/iniciar-sesion"
              class="text-xs text-neutral-content/30 hover:text-neutral-content/50 transition-colors"
            >
              Acceso personal
            </a>
          </div>
        </div>

        <div class="mt-6 pt-5 border-t border-neutral-content/10 text-center">
          <p class="text-xs text-neutral-content/30">
            Desarrollado por{" "}
            <a
              href="https://livecraft.com.mx/"
              target="_blank"
              rel="noopener noreferrer"
              class="hover:text-neutral-content/60 transition-colors underline underline-offset-2"
            >
              LiveCraft
            </a>
          </p>
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
    desc = Map.get(assigns.item, :description)
    has_desc = is_binary(desc) && String.trim(desc) != ""
    # Only show "ver más" when the description is long enough to actually be
    # clipped at 2 lines (~80 chars covers most card widths).
    needs_expand = has_desc && String.length(String.trim(desc)) > 80
    assigns = assign(assigns, :desc, desc)
    assigns = assign(assigns, :has_desc, has_desc)
    assigns = assign(assigns, :needs_expand, needs_expand)

    ~H"""
    <div class="bg-base-100 border border-base-300 rounded-2xl overflow-hidden shadow-sm hover:shadow-md transition-shadow flex flex-col">
      <%!-- Photo --%>
      <%= if Map.get(@item, :image_url) do %>
        <div class="aspect-[4/3] overflow-hidden">
          <img
            src={@item.image_url}
            alt={@item.name}
            class="w-full h-full object-cover"
            loading="lazy"
          />
        </div>
      <% end %>

      <div class="p-5 sm:p-6 flex flex-col gap-3 flex-1">
        <%!-- Name + Price --%>
        <div class="flex items-start justify-between gap-4">
          <h3 class="text-base sm:text-lg font-bold text-base-content leading-snug">
            {@item.name}
          </h3>
          <span class="text-base sm:text-lg font-bold text-primary whitespace-nowrap flex-shrink-0">
            ${format_price(@item.price)}
          </span>
        </div>

        <%!-- Description --%>
        <%= if @has_desc do %>
          <p class={"text-sm text-base-content/60 leading-relaxed #{if @needs_expand, do: "line-clamp-2", else: ""}"}>
            {@desc}
          </p>
          <%= if @needs_expand do %>
            <button
              class="text-xs text-primary font-semibold -mt-1 self-start hover:underline focus:outline-none"
              phx-click={JS.show(to: "#item-detail-#{@item.id}", display: "flex")}
            >
              ver más
            </button>
          <% end %>
        <% end %>

        <%!-- Featured badge --%>
        <div :if={Map.get(@item, :featured)} class="mt-auto">
          <span class="inline-block bg-accent/20 text-accent-content border border-accent/40 text-xs font-semibold px-3 py-1 rounded-full">
            Recomendado
          </span>
        </div>
      </div>
    </div>

    <%!-- ── Detail modal — only rendered when description is long enough ── --%>
    <%= if @needs_expand do %>
      <div
        id={"item-detail-#{@item.id}"}
        class="hidden fixed inset-0 z-50 items-center justify-center p-4"
      >
        <%!-- Backdrop — click to close --%>
        <div
          class="absolute inset-0 bg-black/60 backdrop-blur-sm"
          phx-click={JS.hide(to: "#item-detail-#{@item.id}")}
        >
        </div>

        <%!-- Modal card — centrado, responsive. z-10 garantiza que quede sobre el backdrop --%>
        <div class="relative z-10 w-full max-w-sm bg-base-100 rounded-2xl shadow-2xl overflow-hidden mx-auto">
          <%!-- Photo header (if available) --%>
          <%= if Map.get(@item, :image_url) do %>
            <div class="aspect-[16/9] overflow-hidden">
              <img
                src={@item.image_url}
                alt={@item.name}
                class="w-full h-full object-cover"
              />
            </div>
          <% end %>

          <%!-- Content --%>
          <div class="p-5 space-y-3">
            <%!-- Name + Price + Close button in one row — avoids any overlap --%>
            <div class="flex items-start gap-2">
              <h3 class="flex-1 text-lg font-bold text-base-content leading-snug">{@item.name}</h3>
              <span class="text-xl font-bold text-primary whitespace-nowrap shrink-0">
                ${format_price(@item.price)}
              </span>
              <button
                class="btn btn-sm btn-circle btn-ghost shrink-0 -mt-0.5"
                phx-click={JS.hide(to: "#item-detail-#{@item.id}")}
                aria-label="Cerrar"
              >
                <.icon name="hero-x-mark" class="size-4" />
              </button>
            </div>
            <p class="text-sm text-base-content/70 leading-relaxed whitespace-pre-line">
              {@desc}
            </p>
            <div :if={Map.get(@item, :featured)}>
              <span class="inline-block bg-accent/20 text-accent-content border border-accent/40 text-xs font-semibold px-3 py-1 rounded-full">
                Recomendado
              </span>
            </div>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp format_price(%Decimal{} = price) do
    price |> Decimal.round(0) |> Decimal.to_string()
  end

  defp format_price(price), do: "#{price}"


  # ---------------------------------------------------------------------------
  # Contextual help banner
  # ---------------------------------------------------------------------------

  @doc """
  Renders a collapsible info banner explaining the purpose of a form or page.

  ## Attributes
    - `title`   — Short headline, e.g. "¿Para qué sirve este formulario?"
    - `inner_block` — Content (text, lists, etc.) rendered inside the banner.

  ## Example
      <SiteComponents.help_banner title="¿Cómo funciona el precio neto?">
        <p>El <strong>precio neto</strong> es el costo real de adquisición por unidad...</p>
      </SiteComponents.help_banner>
  """
  attr :title, :string, default: "¿Cómo funciona esto?"
  slot :inner_block, required: true

  def help_banner(assigns) do
    ~H"""
    <details class="group rounded-xl border border-info/30 bg-info/5 text-sm mb-4">
      <summary class="flex cursor-pointer items-center gap-2 px-4 py-3 font-medium text-info list-none select-none">
        <.icon name="hero-information-circle" class="size-4 shrink-0" />
        <span class="flex-1">{@title}</span>
        <.icon
          name="hero-chevron-down"
          class="size-4 shrink-0 transition-transform group-open:rotate-180"
        />
      </summary>
      <div class="px-4 pb-4 text-base-content/70 space-y-1.5 text-xs leading-relaxed">
        {render_slot(@inner_block)}
      </div>
    </details>
    """
  end
end
