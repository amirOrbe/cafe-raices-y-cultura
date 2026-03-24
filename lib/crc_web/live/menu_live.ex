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
    categories = case Catalog.list_categories() do
      [] -> placeholder_categories()
      real -> real
    end

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

            <!-- Category tabs -->
            <div class="flex gap-2 sm:gap-3 overflow-x-auto pb-3 mb-8 sm:mb-10 scrollbar-hide">
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

            <!-- Empty state -->
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

  # ---------------------------------------------------------------------------
  # Placeholder data (shown when DB is empty / seeds not run)
  # ---------------------------------------------------------------------------

  defp placeholder_categories do
    [
      %{
        id: "cafe-filtrados", name: "Café Filtrados",
        menu_items: [
          %{name: "Espresso",         description: "Extracción pura de nuestro blend. Intenso y equilibrado.",            price: "40",  featured: false},
          %{name: "Americano",        description: "Espresso suavizado con agua caliente. Largo y aromático.",             price: "45",  featured: false},
          %{name: "Flat White",       description: "Doble espresso con leche vaporizada suave y microespuma sedosa.",      price: "50",  featured: false},
          %{name: "Cappuccino",       description: "Espresso con leche vaporizada y espuma cremosa.",                      price: "55",  featured: true},
          %{name: "Latte",            description: "Espresso generoso con leche vaporizada suave.",                        price: "55",  featured: false},
          %{name: "Café de Olla",     description: "Filtrado artesanal con canela y piloncillo. Sabor de raíces.",         price: "55",  featured: false},
          %{name: "Matcha Culinario", description: "Matcha con leche vaporizada. Suave y reconfortante.",                  price: "65",  featured: true},
          %{name: "Chocolate",        description: "Cacao artesanal con leche entera. Espeso y profundo.",                 price: "65",  featured: false},
          %{name: "Mocca",            description: "Espresso con chocolate y leche vaporizada.",                           price: "75",  featured: false}
        ]
      },
      %{
        id: "sin-cafeina", name: "Sin Cafeína",
        menu_items: [
          %{name: "Earl Grey",                       description: "Té negro con bergamota. Clásico y aromático.",                                         price: "60", featured: false},
          %{name: "Cúrcuma y Jengibre",              description: "Infusión cálida antiinflamatoria y reconfortante.",                                     price: "60", featured: false},
          %{name: "Masala Chai",                     description: "Blend de especias indias con leche vegetal.",                                           price: "60", featured: true},
          %{name: "Tisana Frutos Rojos",             description: "Infusión frutal sin cafeína, llena de color y sabor.",                                  price: "60", featured: false},
          %{name: "Grano Nacional — Atlixco",        description: "Café filtrado de origen Atlixco de las Flores, Puebla. Notas dulces y florales.",       price: "65", featured: true},
          %{name: "Cafecito Internacional",          description: "Selección de granos de origen único de distintas partes del mundo.",                    price: "85", featured: false}
        ]
      },
      %{
        id: "oleos-y-mocktails", name: "Oleos y Mocktails",
        menu_items: [
          %{name: "Cold Brew",                  description: "Infusión en frío de 18 horas. Suave, con cuerpo y sin acidez.",         price: "55", featured: true},
          %{name: "Limonada Clásica",           description: "Limón amarillo, agua mineral y un toque de miel.",                      price: "60", featured: false},
          %{name: "Limonada Frutos Silvestres", description: "Limonada con mezcla de frutos silvestres de temporada.",                price: "60", featured: false},
          %{name: "Limonada Rosa",              description: "Limonada con frutos rojos y agua mineral. Floral y refrescante.",       price: "60", featured: true},
          %{name: "Espresso Tonic",             description: "Doble espresso sobre agua tónica. Amargo, burbujeante y vibrante.",     price: "60", featured: false},
          %{name: "Smoothie Frutal",            description: "Mezcla de frutas frescas de temporada. Natural y sin azúcar añadida.", price: "65", featured: false},
          %{name: "Citric Brew",                description: "Cold brew con cítricos frescos. Intenso y muy refrescante.",            price: "70", featured: false},
          %{name: "Jamaica Brew",               description: "Cold brew con infusión de jamaica. Frutal y profundo.",                 price: "75", featured: false},
          %{name: "Torito",                     description: "Bebida fresca de inspiración veracruzana con cacahuate y vainilla.",    price: "80", featured: false},
          %{name: "De Temporada",               description: "Creación especial con ingredientes de temporada. Pregunta por la del día.", price: "85", featured: true}
        ]
      },
      %{
        id: "extras", name: "Extras",
        menu_items: [
          %{name: "Leche Vegetal",     description: "Avena, almendra o soya. Pregunta disponibilidad.", price: "15", featured: false},
          %{name: "Carga de Espresso", description: "Shot extra de espresso para tu bebida.",            price: "15", featured: false},
          %{name: "Vaso de Leche",     description: "Leche entera fría o caliente.",                    price: "25", featured: false}
        ]
      },
      %{
        id: "sandwises", name: "Sanduíses",
        menu_items: [
          %{name: "Vegetariano", description: "Champis, chile morrón, queso gouda, tomate cherry y pepinillos.",                                                         price: "85",  featured: false},
          %{name: "Clásico",     description: "Pechuga de pavo, tomate cherry y arugula.",                                                                               price: "95",  featured: false},
          %{name: "Grilled Cheese", description: "Mezcla de quesos artesanales y salsa pomodoro casera.",                                                                price: "95",  featured: false},
          %{name: "El Exótico",  description: "Chistorra, queso gouda, cebolla caramelizada, cherrys sofritos, arugula y dip de aguacate.",                              price: "110", featured: false},
          %{name: "El Favorito", description: "Arrachera, queso gouda, dip de aguacate, tomate cherry, champis, morrón y arugula.",                                      price: "115", featured: true}
        ]
      },
      %{
        id: "pan-pizza", name: "Pan Pizza",
        menu_items: [
          %{name: "Sencilla",             description: "Queso gouda, salsa de tomate y finas hierbas.",                                                                  price: "75", featured: false},
          %{name: "Vegetariano",          description: "Champis, chile morrón, queso gouda, tomate cherry y arugula.",                                                   price: "80", featured: false},
          %{name: "Quesos",               description: "Salsa de tomate, finas hierbas y generosa mezcla de quesos.",                                                    price: "85", featured: true},
          %{name: "El Viejo y Confiable", description: "Salsa de tomate, pepperoni y queso gouda. El clásico de siempre.",                                               price: "85", featured: false},
          %{name: "El Mexa",              description: "Salsa de tomate, frijoles, jalapeño, chistorra, queso gouda, cebolla morada y champis.",                         price: "95", featured: true}
        ]
      },
      %{
        id: "para-almorzar", name: "Para Almorzar",
        menu_items: [
          %{name: "Pan Tostado Mexa",   description: "Dos rebanadas de pan campesino con miel, azúcar, fruta y jalea.",                             price: "50", featured: false},
          %{name: "Fruta de Temporada", description: "Fruta picada, quesos y arugula acompañada con yoghurt, miel y granola.",                      price: "55", featured: false},
          %{name: "Avena Trasnochada",  description: "Avena suave remojada en leche con toque dulce, fruta de temporada y semillas.",               price: "65", featured: false},
          %{name: "Toast Francés",      description: "Pan campesino suave y dulce con crema de avellanas, fruta fresca y miel.",                    price: "95", featured: true}
        ]
      }
    ]
  end
end
