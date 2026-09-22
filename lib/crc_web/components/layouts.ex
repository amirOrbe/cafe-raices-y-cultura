defmodule CRCWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use CRCWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="navbar px-4 sm:px-6 lg:px-8">
      <div class="flex-1">
        <a href="/" class="flex-1 flex w-fit items-center gap-2">
          <img src={~p"/images/logo.svg"} width="36" />
          <span class="text-sm font-semibold">v{Application.spec(:phoenix, :vsn)}</span>
        </a>
      </div>
      <div class="flex-none">
        <ul class="flex flex-column px-1 space-x-4 items-center">
          <li>
            <a href="https://phoenixframework.org/" class="btn btn-ghost">Website</a>
          </li>
          <li>
            <a href="https://github.com/phoenixframework/phoenix" class="btn btn-ghost">GitHub</a>
          </li>
          <li>
            <.theme_toggle />
          </li>
          <li>
            <a href="https://hexdocs.pm/phoenix/overview.html" class="btn btn-primary">
              Get Started <span aria-hidden="true">&rarr;</span>
            </a>
          </li>
        </ul>
      </div>
    </header>

    <main class="px-4 py-20 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-2xl space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Layout for the administration panel with a lateral sidebar.
  """
  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  attr :inner_content, :any, default: nil

  attr :current_path, :string,
    default: nil,
    doc: "set by CRCWeb.UserAuth's :require_admin on_mount hook"

  def admin(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200">
      <%!-- Backdrop móvil --%>
      <div
        id="admin-backdrop"
        class="fixed inset-0 z-30 bg-black/50 hidden lg:hidden"
        phx-click={
          JS.add_class("hidden", to: "#admin-backdrop")
          |> JS.remove_class("-translate-x-0", to: "#admin-sidebar")
          |> JS.add_class("-translate-x-full", to: "#admin-sidebar")
        }
      />

      <%!-- Sidebar --%>
      <aside
        id="admin-sidebar"
        class="fixed inset-y-0 left-0 z-40 w-64 bg-primary text-primary-content flex flex-col shadow-xl
               -translate-x-full lg:translate-x-0 transition-transform duration-300 ease-in-out"
      >
        <%!-- Logo --%>
        <div class="px-6 py-5 border-b border-primary-content/20 flex items-center justify-between">
          <div>
            <a href="/admin" class="flex items-center gap-2">
              <span class="text-lg font-bold tracking-tight">CRC Admin</span>
            </a>
            <p class="text-xs text-primary-content/50 mt-0.5">Panel de Administración</p>
          </div>
          <%!-- Cerrar sidebar en móvil --%>
          <button
            class="lg:hidden p-1.5 rounded-lg hover:bg-primary-content/15 transition-colors"
            phx-click={
              JS.add_class("hidden", to: "#admin-backdrop")
              |> JS.remove_class("-translate-x-0", to: "#admin-sidebar")
              |> JS.add_class("-translate-x-full", to: "#admin-sidebar")
            }
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>

        <%!-- Navegación --%>
        <nav class="flex-1 px-3 py-5 space-y-1 overflow-y-auto">
          <%= for section <- nav_sections() do %>
            <div :if={section[:label]} class="pt-3 pb-1">
              <p class="px-3 text-xs font-semibold text-primary-content/40 uppercase tracking-wider">
                {section.label}
              </p>
            </div>
            <.nav_link :for={item <- section.items} item={item} current_path={assigns[:current_path]} />
          <% end %>
        </nav>

        <%!-- Usuario y logout --%>
        <div class="px-3 py-4 border-t border-primary-content/20 space-y-3">
          <div class="flex items-center justify-between px-3">
            <span class="text-xs text-primary-content/50">Apariencia</span>
            <.theme_toggle />
          </div>
          <a
            href="/"
            class="flex items-center gap-3 px-3 py-2.5 rounded-lg hover:bg-primary-content/15 transition-colors text-sm text-primary-content/80"
          >
            <.icon name="hero-arrow-left" class="size-4 shrink-0" /> Ver sitio
          </a>
          <form action="/cerrar-sesion" method="post">
            <input type="hidden" name="_method" value="delete" />
            <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
            <button
              type="submit"
              class="w-full flex items-center gap-3 px-3 py-2.5 rounded-lg hover:bg-primary-content/15 transition-colors text-sm text-primary-content/80"
            >
              <.icon name="hero-arrow-right-on-rectangle" class="size-4 shrink-0" /> Cerrar sesión
            </button>
          </form>
        </div>
      </aside>

      <%!-- Contenido principal --%>
      <div class="lg:ml-64 min-h-screen flex flex-col">
        <%!-- Top bar móvil --%>
        <header class="lg:hidden sticky top-0 z-20 bg-primary text-primary-content px-4 h-14 flex items-center justify-between shadow-md">
          <button
            class="p-1.5 rounded-lg hover:bg-primary-content/15 transition-colors"
            phx-click={
              JS.remove_class("hidden", to: "#admin-backdrop")
              |> JS.remove_class("-translate-x-full", to: "#admin-sidebar")
              |> JS.add_class("-translate-x-0", to: "#admin-sidebar")
            }
          >
            <.icon name="hero-bars-3" class="size-6" />
          </button>
          <span class="font-bold text-sm tracking-tight">CRC Admin</span>
          <div class="w-9" />
        </header>

        <main class="flex-1 p-4 sm:p-6 lg:p-8">
          <.flash_group flash={@flash} />
          {@inner_content}
        </main>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Admin sidebar navigation
  # ---------------------------------------------------------------------------

  # Grouped as data (rather than ~25 hand-copied <a> tags) so adding, moving,
  # or renaming a link is a one-line change instead of a copy/paste edit, and
  # so nav_link/1 can highlight the active page in one place.
  defp nav_sections do
    [
      %{
        items: [
          %{path: "/admin", label: "Dashboard", icon: "hero-home"},
          %{path: "/bitacora", label: "Bitácora de Turno", icon: "hero-clipboard-document-check"}
        ]
      },
      %{
        label: "Clientes",
        items: [
          %{path: "/admin/clientes", label: "Clientes", icon: "hero-identification"},
          %{path: "/admin/lealtad", label: "Lealtad", icon: "hero-ticket"}
        ]
      },
      %{
        label: "Carta y Menú",
        items: [
          %{path: "/admin/platillos", label: "Platillos", icon: "hero-clipboard-document-list"},
          %{
            path: "/admin/platillos/categorias",
            label: "Categorías de platillos",
            icon: "hero-squares-2x2"
          },
          %{path: "/admin/paquetes", label: "Paquetes", icon: "hero-gift"}
        ]
      },
      %{
        label: "Inventario",
        items: [
          %{
            path: "/admin/inventario",
            label: "Inventario (stock)",
            icon: "hero-clipboard-document-list"
          },
          %{path: "/admin/proveedores", label: "Proveedores", icon: "hero-truck"},
          %{path: "/admin/insumos", label: "Insumos", icon: "hero-archive-box"},
          %{
            path: "/admin/insumos/categorias",
            label: "Categorías de insumos",
            icon: "hero-tag"
          },
          %{path: "/admin/produccion", label: "Producción Interna", icon: "hero-beaker"}
        ]
      },
      %{
        label: "Operaciones del local",
        items: [
          %{path: "/admin/mesas", label: "Mesas", icon: "hero-table-cells"},
          %{path: "/admin/descuentos", label: "Descuentos", icon: "hero-tag"}
        ]
      },
      %{
        label: "Eventos y Colaboraciones",
        items: [
          %{path: "/admin/eventos", label: "Eventos", icon: "hero-calendar"},
          %{path: "/admin/colaboradores", label: "Colaboradores", icon: "hero-user-group"},
          %{path: "/admin/eventos/tipos", label: "Tipos de evento", icon: "hero-tag"}
        ]
      },
      %{
        label: "Reportes y Finanzas",
        items: [
          %{path: "/admin/finanzas", label: "Finanzas", icon: "hero-scale"},
          %{path: "/admin/ventas", label: "Ventas", icon: "hero-chart-bar"},
          %{path: "/admin/rendimiento", label: "Rendimiento", icon: "hero-clock"}
        ]
      },
      %{
        label: "Personal",
        items: [
          %{path: "/admin/usuarios", label: "Usuarios", icon: "hero-users"},
          %{path: "/admin/horarios", label: "Horarios", icon: "hero-calendar-days"},
          %{path: "/admin/asistencia", label: "Asistencia", icon: "hero-finger-print"},
          %{
            path: "/admin/calendario",
            label: "Calendario de actividades",
            icon: "hero-calendar"
          },
          %{path: "/admin/cumpleanos", label: "Cumpleaños", icon: "hero-cake"}
        ]
      },
      %{
        label: "Sistema",
        items: [
          %{path: "/admin/configuracion", label: "Configuración", icon: "hero-cog-6-tooth"}
        ]
      }
    ]
  end

  attr :item, :map, required: true
  attr :current_path, :string, default: nil

  defp nav_link(assigns) do
    active? = assigns.current_path == assigns.item.path
    assigns = assign(assigns, :active?, active?)

    ~H"""
    <a
      href={@item.path}
      class={[
        "flex items-center gap-3 px-3 py-2.5 rounded-lg transition-colors text-sm font-medium",
        if(@active?,
          do: "bg-primary-content/15 font-semibold",
          else: "hover:bg-primary-content/15"
        )
      ]}
      aria-current={@active? && "page"}
    >
      <.icon name={@item.icon} class="size-5 shrink-0" /> {@item.label}
    </a>
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
        title={gettext("Sin conexión a internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Intentando reconectar")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Algo salió mal")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Intentando reconectar")}
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
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=cafe-light]_&]:left-1/3 [[data-theme=cafe-dark]_&]:left-2/3 transition-[left]" />

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
        data-phx-theme="cafe-light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="cafe-dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
