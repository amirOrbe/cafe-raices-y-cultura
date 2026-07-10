defmodule CRCWeb.Client.PedidosLive do
  use CRCWeb, :live_view

  alias CRCWeb.Components.SiteComponents

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Mis pedidos", nav_open: false)}
  end

  def handle_event("toggle_nav", _params, socket) do
    {:noreply, assign(socket, :nav_open, !socket.assigns.nav_open)}
  end

  def handle_event("close_nav", _params, socket) do
    {:noreply, assign(socket, :nav_open, false)}
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex flex-col bg-base-200">
      <SiteComponents.site_navbar
        nav_open={@nav_open}
        current_page={:pedidos}
        current_user={@current_user}
      />

      <main class="flex-1 w-full max-w-2xl mx-auto px-4 py-8">
        <div class="card bg-base-100 shadow-sm">
          <div class="card-body items-center text-center py-16">
            <div class="text-6xl mb-4">🛍️</div>
            <h1 class="text-2xl font-bold text-base-content mb-2">Mis pedidos</h1>
            <p class="text-base-content/60 max-w-xs">
              Aquí aparecerán tus pedidos y cuentas cuando estén disponibles.
            </p>
            <.link navigate="/" class="btn btn-primary mt-6">
              Regresar al inicio
            </.link>
          </div>
        </div>
      </main>

      <SiteComponents.site_footer />
    </div>
    """
  end
end
