defmodule CRCWeb.MenuLive do
  @moduledoc """
  Full-page menu LiveView at /menu.
  Displays all categories with tabs and item cards matching the CRC design.
  """

  use CRCWeb, :live_view

  alias CRC.Catalog
  alias CRCWeb.Components.SiteComponents

  @impl true
  def mount(_params, _session, socket) do
    categories = Catalog.list_categories()

    socket =
      socket
      |> assign(:page_title, "Menú — Café Raíces y Cultura")
      |> assign(:categories, categories)
      |> assign(:active_category, List.first(categories))
      |> assign(:nav_open, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("select_category", %{"id" => id}, socket) do
    category =
      Enum.find(socket.assigns.categories, fn c ->
        to_string(c.id) == id or c.id == id
      end)

    {:noreply, assign(socket, :active_category, category)}
  end

  def handle_event("toggle_nav", _params, socket) do
    {:noreply, assign(socket, :nav_open, !socket.assigns.nav_open)}
  end

  def handle_event("close_nav", _params, socket) do
    {:noreply, assign(socket, :nav_open, false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex flex-col bg-base-100">
      <SiteComponents.site_navbar nav_open={@nav_open} current_page={:menu} current_user={@current_user} />

      <main class="flex-1 pt-16">
        <section class="py-14 sm:py-20 lg:py-24 bg-base-100">
          <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">

            <!-- Header -->
            <div class="text-center mb-10 sm:mb-14">
              <span class="inline-block text-primary font-semibold text-xs sm:text-sm uppercase tracking-widest mb-3">
                Lo que ofrecemos
              </span>
              <h1 class="text-3xl sm:text-5xl font-bold text-base-content">
                Nuestro Menú
              </h1>
              <p class="mt-3 text-base-content/50 text-sm sm:text-base max-w-lg mx-auto">
                Hecho en casa, con procesos orgánicos y atención al detalle.
              </p>
            </div>

            <!-- Menu empty state -->
            <div :if={@categories == []} class="text-center py-20 sm:py-28">
              <p class="text-5xl mb-6">☕</p>
              <h2 class="text-2xl sm:text-3xl font-bold text-base-content mb-3">
                Nuestra carta está en camino
              </h2>
              <p class="text-base-content/50 text-sm sm:text-base max-w-sm mx-auto">
                Estamos preparando todo con cariño. Muy pronto encontrarás aquí
                nuestra selección completa de bebidas y platillos.
              </p>
            </div>

            <!-- Category tabs -->
            <div :if={@categories != []} class="flex gap-2 sm:gap-3 overflow-x-auto pb-3 mb-8 sm:mb-10 scrollbar-hide">
              <%= for category <- @categories do %>
                <button
                  phx-click="select_category"
                  phx-value-id={category.id}
                  class={[
                    "whitespace-nowrap flex-shrink-0 px-4 sm:px-5 py-2 sm:py-2.5 rounded-xl text-sm sm:text-base font-semibold transition-all",
                    if(@active_category && @active_category.id == category.id,
                      do: "bg-primary text-primary-content shadow-sm",
                      else: "bg-transparent text-base-content/70 border border-base-300 hover:border-primary hover:text-primary"
                    )
                  ]}
                >
                  {category.name}
                </button>
              <% end %>
            </div>

            <!-- Items grid -->
            <div :if={@active_category && length(@active_category.menu_items) > 0}
                 class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 sm:gap-5">
              <%= for item <- @active_category.menu_items do %>
                <SiteComponents.menu_item_card item={item} />
              <% end %>
            </div>

            <!-- Empty state for category with no items -->
            <div :if={@active_category && length(@active_category.menu_items) == 0}
                 class="text-center py-16 text-base-content/40">
              <p class="text-lg">Próximamente más opciones en esta categoría.</p>
            </div>

            <!-- Bottom nav -->
            <div class="text-center mt-14 sm:mt-16 pt-8 border-t border-base-300">
              <a href="/" class="text-sm text-base-content/40 hover:text-primary transition-colors inline-flex items-center gap-1">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
                </svg>
                Volver al inicio
              </a>
            </div>

          </div>
        </section>
      </main>

      <SiteComponents.site_footer />
    </div>
    """
  end

end
