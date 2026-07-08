defmodule CRCWeb.Client.PedidosLive do
  use CRCWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Mis pedidos")}
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-md mx-auto px-4 py-10 text-center">
      <p class="text-4xl mb-4">🛍️</p>
      <h1 class="text-2xl font-bold text-base-content mb-2">Mis pedidos</h1>
      <p class="text-base-content/60">Aquí aparecerán tus pedidos y cuentas. Próximamente.</p>
      <a href="/cliente/perfil" class="btn btn-primary mt-6">Volver a mi perfil</a>
    </div>
    """
  end
end
