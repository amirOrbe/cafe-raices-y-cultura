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
  Layout for the administration panel — a slim top bar (logo on `/admin`,
  "Volver al panel" everywhere else) instead of a persistent sidebar. Every
  destination now lives in the card grid rendered on `/admin` itself (see
  `CRCWeb.AdminComponents.nav_sections/0` + `nav_card/1`).
  """
  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  attr :inner_content, :any, default: nil

  attr :current_path, :string,
    default: nil,
    doc: "set by CRCWeb.UserAuth's :require_admin on_mount hook"

  def admin(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200 flex flex-col">
      <header class="sticky top-0 z-20 bg-primary text-primary-content px-4 sm:px-6 h-14 flex items-center justify-between shadow-md">
        <%= if assigns[:current_path] == "/admin" do %>
          <span class="font-bold text-sm sm:text-base tracking-tight">CRC Admin</span>
        <% else %>
          <.link
            navigate="/admin"
            class="flex items-center gap-1.5 text-sm font-medium hover:opacity-80 transition-opacity"
          >
            <.icon name="hero-arrow-left" class="size-4 shrink-0" />
            <span class="hidden sm:inline">Volver al panel</span>
          </.link>
        <% end %>

        <div class="flex items-center gap-2 sm:gap-3">
          <.theme_toggle />
          <.link
            navigate="/"
            class="p-2 rounded-lg hover:bg-primary-content/15 transition-colors"
            title="Ver sitio"
          >
            <.icon name="hero-globe-alt" class="size-4.5" />
          </.link>
          <form action="/cerrar-sesion" method="post">
            <input type="hidden" name="_method" value="delete" />
            <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
            <button
              type="submit"
              class="p-2 rounded-lg hover:bg-primary-content/15 transition-colors"
              title="Cerrar sesión"
            >
              <.icon name="hero-arrow-right-on-rectangle" class="size-4.5" />
            </button>
          </form>
        </div>
      </header>

      <main class="flex-1 p-4 sm:p-6 lg:p-8">
        <.flash_group flash={@flash} />
        {@inner_content}
      </main>
    </div>
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
