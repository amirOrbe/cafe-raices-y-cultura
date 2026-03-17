defmodule CRCWeb.HomeLive do
  use CRCWeb, :live_view

  alias CRC.Catalog
  alias CRC.Media

  @impl true
  def mount(_params, _session, socket) do
    photos = Media.list_photos()
    categories = Catalog.list_categories()

    socket =
      socket
      |> assign(:page_title, "Café Raíces y Cultura")
      |> assign(:photos, photos)
      |> assign(:active_slide, 0)
      |> assign(:categories, categories)
      |> assign(:active_category, List.first(categories))
      |> assign(:nav_open, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("carousel_next", _params, socket) do
    total = length(socket.assigns.photos)
    next = rem(socket.assigns.active_slide + 1, total)
    {:noreply, assign(socket, :active_slide, next)}
  end

  def handle_event("carousel_prev", _params, socket) do
    total = length(socket.assigns.photos)
    prev = rem(socket.assigns.active_slide - 1 + total, total)
    {:noreply, assign(socket, :active_slide, prev)}
  end

  def handle_event("carousel_goto", %{"index" => index}, socket) do
    {:noreply, assign(socket, :active_slide, String.to_integer(index))}
  end

  def handle_event("select_category", %{"id" => id}, socket) do
    category =
      Enum.find(socket.assigns.categories, fn c -> to_string(c.id) == id end)

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
    <div class="min-h-screen flex flex-col">
      <.navbar nav_open={@nav_open} />
      <main class="flex-1">
        <.hero_section photos={@photos} active_slide={@active_slide} />
        <.about_section />
        <.menu_section categories={@categories} active_category={@active_category} />
        <.booking_section />
        <.contact_section />
      </main>
      <.footer />
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp format_price(%Decimal{} = price) do
    price
    |> Decimal.round(0)
    |> Decimal.to_string()
  end

  defp format_price(price), do: "#{price}"

  # ---------------------------------------------------------------------------
  # Navbar
  # ---------------------------------------------------------------------------

  defp navbar(assigns) do
    ~H"""
    <nav class="fixed top-0 left-0 right-0 z-50 bg-base-100/95 backdrop-blur-sm border-b border-base-300 shadow-sm">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="flex items-center justify-between h-16">
          <!-- Logo / Brand -->
          <a href="#inicio" class="flex items-center gap-2 group">
            <div class="w-8 h-8 rounded-full bg-primary flex items-center justify-center text-primary-content font-bold text-sm">
              CRC
            </div>
            <span class="font-semibold text-base-content text-sm sm:text-base leading-tight">
              Café Raíces y Cultura
            </span>
          </a>

          <!-- Desktop nav links -->
          <div class="hidden md:flex items-center gap-6">
            <a href="#nosotros" class="text-sm font-medium text-base-content/70 hover:text-primary transition-colors">
              Nosotros
            </a>
            <a href="#menu" class="text-sm font-medium text-base-content/70 hover:text-primary transition-colors">
              Menú
            </a>
            <a href="#booking" class="btn btn-primary btn-sm">
              Reservar
            </a>
          </div>

          <!-- Mobile hamburger -->
          <button
            phx-click="toggle_nav"
            phx-value-stop="true"
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

      <!-- Mobile menu -->
      <div :if={@nav_open} class="md:hidden border-t border-base-300 bg-base-100 px-4 py-3 space-y-2">
        <a href="#nosotros" phx-click="close_nav" class="block py-2 text-base font-medium text-base-content/80 hover:text-primary">
          Nosotros
        </a>
        <a href="#menu" phx-click="close_nav" class="block py-2 text-base font-medium text-base-content/80 hover:text-primary">
          Menú
        </a>
        <a href="#booking" phx-click="close_nav" class="block py-2">
          <span class="btn btn-primary btn-sm w-full">Reservar experiencia</span>
        </a>
      </div>
    </nav>
    """
  end

  # ---------------------------------------------------------------------------
  # Hero / Carousel
  # ---------------------------------------------------------------------------

  defp hero_section(%{photos: []} = assigns) do
    ~H"""
    <section id="inicio" class="relative pt-16 h-64 sm:h-80 md:h-[500px] lg:h-[600px] bg-primary flex items-center justify-center">
      <div class="text-center text-primary-content px-4">
        <h1 class="text-3xl sm:text-5xl font-bold mb-4">Café Raíces y Cultura</h1>
        <p class="text-lg sm:text-xl opacity-90">Coquimbo 709, Lindavista Sur · CDMX</p>
      </div>
    </section>
    """
  end

  defp hero_section(assigns) do
    ~H"""
    <section
      id="inicio"
      class="relative pt-16 h-64 sm:h-80 md:h-[500px] lg:h-[600px] overflow-hidden"
      phx-hook="CarouselAutoplay"
    >
      <!-- Slides -->
      <div class="relative w-full h-full">
        <%= for {photo, index} <- Enum.with_index(@photos) do %>
          <div
            class={"absolute inset-0 transition-opacity duration-700 #{if index == @active_slide, do: "opacity-100 z-10", else: "opacity-0 z-0"}"}
          >
            <img
              src={photo.url}
              alt={photo.caption || "Café Raíces y Cultura"}
              class="w-full h-full object-cover"
              loading={if index == 0, do: "eager", else: "lazy"}
            />
            <!-- Gradient overlay -->
            <div class="absolute inset-0 bg-gradient-to-t from-black/60 via-black/10 to-transparent"></div>
            <!-- Caption -->
            <div :if={photo.caption} class="absolute bottom-12 md:bottom-16 left-0 right-0 text-center px-4">
              <p class="text-white text-base sm:text-lg md:text-2xl font-medium drop-shadow-lg">
                {photo.caption}
              </p>
            </div>
          </div>
        <% end %>
      </div>

      <!-- Prev / Next controls -->
      <button
        phx-click="carousel_prev"
        class="absolute left-3 sm:left-4 top-1/2 -translate-y-1/2 z-20 btn btn-circle btn-sm sm:btn-md bg-black/30 border-0 text-white hover:bg-black/60"
        aria-label="Anterior"
      >
        <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
        </svg>
      </button>

      <button
        phx-click="carousel_next"
        class="absolute right-3 sm:right-4 top-1/2 -translate-y-1/2 z-20 btn btn-circle btn-sm sm:btn-md bg-black/30 border-0 text-white hover:bg-black/60"
        aria-label="Siguiente"
      >
        <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
        </svg>
      </button>

      <!-- Dot indicators -->
      <div class="absolute bottom-4 left-0 right-0 z-20 flex justify-center gap-2">
        <%= for {_photo, index} <- Enum.with_index(@photos) do %>
          <button
            phx-click="carousel_goto"
            phx-value-index={index}
            class={"rounded-full transition-all #{if index == @active_slide, do: "w-6 h-2.5 bg-white", else: "w-2.5 h-2.5 bg-white/50 hover:bg-white/75"}"}
            aria-label={"Ir a la foto #{index + 1}"}
          />
        <% end %>
      </div>

      <!-- Hero headline overlay -->
      <div class="absolute inset-x-0 top-1/2 -translate-y-1/2 z-20 text-center px-4 pointer-events-none">
        <h1 class="text-2xl sm:text-4xl md:text-5xl lg:text-6xl font-bold text-white drop-shadow-xl leading-tight">
          Café Raíces y Cultura
        </h1>
        <p class="mt-2 text-sm sm:text-base md:text-lg text-white/90 drop-shadow">
          Lindavista Sur · Ciudad de México
        </p>
      </div>
    </section>
    """
  end

  # ---------------------------------------------------------------------------
  # Nosotros (About)
  # ---------------------------------------------------------------------------

  defp about_section(assigns) do
    ~H"""
    <section id="nosotros" class="py-16 sm:py-20 lg:py-24 bg-base-100">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-10 lg:gap-16 items-center">
          <!-- Image -->
          <div class="order-2 lg:order-1">
            <div class="relative rounded-2xl overflow-hidden shadow-xl aspect-[4/3]">
              <img
                src="https://images.unsplash.com/photo-1600093463592-8e36ae95ef56?w=800&auto=format&fit=crop"
                alt="Interior de Café Raíces y Cultura"
                class="w-full h-full object-cover"
                loading="lazy"
              />
              <div class="absolute inset-0 bg-gradient-to-tr from-primary/20 to-transparent"></div>
            </div>
          </div>

          <!-- Text -->
          <div class="order-1 lg:order-2">
            <span class="inline-block text-primary font-semibold text-sm uppercase tracking-widest mb-3">
              Nuestra historia
            </span>
            <h2 class="text-3xl sm:text-4xl font-bold text-base-content mb-6 leading-tight">
              Donde el café se convierte en cultura
            </h2>
            <div class="space-y-4 text-base-content/70 text-base sm:text-lg leading-relaxed">
              <p>
                En <strong class="text-base-content">Café Raíces y Cultura</strong> creemos que una buena taza de café
                es el punto de partida para grandes conversaciones, ideas y momentos que perduran.
              </p>
              <p>
                Nos ubicamos en el corazón de Lindavista Sur, CDMX, con un espacio diseñado para
                que te sientas como en casa. Trabajamos con granos de origen seleccionado y métodos
                de preparación que respetan cada terroir.
              </p>
              <p>
                Más que una cafetería, somos un espacio donde las <strong class="text-base-content">raíces</strong>
                —nuestros ingredientes, nuestra gente, nuestra gastronomía— se abrazan con la
                <strong class="text-base-content">cultura</strong> viva de la ciudad.
              </p>
            </div>

            <!-- Quick info -->
            <div class="mt-8 grid grid-cols-2 gap-4">
              <div class="bg-base-200 rounded-xl p-4 text-center">
                <p class="text-2xl font-bold text-primary">Lun–Vie</p>
                <p class="text-sm text-base-content/60 mt-1">8:00 – 21:00</p>
              </div>
              <div class="bg-base-200 rounded-xl p-4 text-center">
                <p class="text-2xl font-bold text-primary">Sáb–Dom</p>
                <p class="text-sm text-base-content/60 mt-1">9:00 – 22:00</p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
    """
  end

  # ---------------------------------------------------------------------------
  # Menú
  # ---------------------------------------------------------------------------

  defp menu_section(%{categories: []} = assigns) do
    ~H"""
    <section id="menu" class="py-16 bg-base-200">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 text-center">
        <h2 class="text-3xl font-bold text-base-content mb-4">Nuestro Menú</h2>
        <p class="text-base-content/60">Próximamente...</p>
      </div>
    </section>
    """
  end

  defp menu_section(assigns) do
    ~H"""
    <section id="menu" class="py-16 sm:py-20 lg:py-24 bg-base-200">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <!-- Header -->
        <div class="text-center mb-10 sm:mb-14">
          <span class="inline-block text-primary font-semibold text-sm uppercase tracking-widest mb-3">
            Lo que ofrecemos
          </span>
          <h2 class="text-3xl sm:text-4xl font-bold text-base-content">Nuestro Menú</h2>
        </div>

        <!-- Category tabs -->
        <div class="flex gap-2 sm:gap-3 overflow-x-auto pb-2 mb-8 menu-scroll snap-x">
          <%= for category <- @categories do %>
            <button
              phx-click="select_category"
              phx-value-id={category.id}
              class={"btn btn-sm sm:btn-md whitespace-nowrap snap-start flex-shrink-0 #{if @active_category && @active_category.id == category.id, do: "btn-primary", else: "btn-ghost border border-base-300"}"}
            >
              {category.name}
            </button>
          <% end %>
        </div>

        <!-- Menu items grid -->
        <div :if={@active_category} class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 sm:gap-6">
          <%= for item <- @active_category.menu_items do %>
            <.menu_card item={item} />
          <% end %>
        </div>

        <!-- CTA -->
        <div class="text-center mt-10 sm:mt-14">
          <a href="#booking" class="btn btn-primary btn-lg">
            Reserva tu experiencia
          </a>
        </div>
      </div>
    </section>
    """
  end

  defp menu_card(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-sm hover:shadow-md transition-shadow border border-base-300">
      <div class="card-body p-4 sm:p-5">
        <div class="flex items-start justify-between gap-3">
          <div class="flex-1 min-w-0">
            <h3 class="card-title text-base sm:text-lg font-semibold text-base-content leading-tight">
              {@item.name}
            </h3>
            <p :if={@item.description} class="text-sm text-base-content/60 mt-1.5 leading-relaxed line-clamp-2">
              {@item.description}
            </p>
          </div>
          <div class="flex-shrink-0 text-right">
            <span class="text-lg font-bold text-primary">
              ${format_price(@item.price)}
            </span>
          </div>
        </div>
        <div :if={@item.featured} class="mt-2">
          <span class="badge badge-accent badge-sm text-xs">Recomendado</span>
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Booking — coming soon (event experiences)
  # ---------------------------------------------------------------------------

  defp booking_section(assigns) do
    ~H"""
    <section id="booking" class="py-16 sm:py-20 lg:py-24 bg-base-200">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">

        <!-- Header -->
        <div class="text-center mb-12 sm:mb-16">
          <div class="inline-flex items-center gap-2 bg-accent/20 text-accent-content border border-accent/30 rounded-full px-4 py-1.5 text-xs font-semibold uppercase tracking-widest mb-4">
            <span class="w-2 h-2 rounded-full bg-accent animate-pulse"></span>
            Próximamente
          </div>
          <h2 class="text-3xl sm:text-4xl font-bold text-base-content mt-2">
            Reserva tu experiencia
          </h2>
          <p class="mt-4 text-base-content/60 text-base sm:text-lg max-w-xl mx-auto">
            Próximamente podrás apartar el café para vivirlo a tu manera —
            solo, con amigos o con quienes más quieres.
          </p>
        </div>

        <!-- Experience cards -->
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-5 sm:gap-6 mb-12">

          <!-- Coffee Party -->
          <div class="card bg-base-100 border border-base-300 shadow-sm hover:shadow-md transition-shadow">
            <div class="card-body p-6">
              <div class="w-12 h-12 bg-primary/10 rounded-2xl flex items-center justify-center mb-4">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6 text-primary" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0z" />
                </svg>
              </div>
              <h3 class="text-lg font-bold text-base-content">Coffee Party</h3>
              <p class="text-sm text-base-content/60 mt-2 leading-relaxed">
                Celebra con tu grupo en un ambiente acogedor. Menú especial, espacio privado
                y toda la vibra de Raíces y Cultura para tu reunión.
              </p>
              <div class="mt-4 flex flex-wrap gap-2">
                <span class="badge badge-ghost text-xs">Grupos de 6–20</span>
                <span class="badge badge-ghost text-xs">Menú personalizado</span>
              </div>
            </div>
          </div>

          <!-- Sesión de lectura -->
          <div class="card bg-base-100 border border-base-300 shadow-sm hover:shadow-md transition-shadow">
            <div class="card-body p-6">
              <div class="w-12 h-12 bg-primary/10 rounded-2xl flex items-center justify-center mb-4">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6 text-primary" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253" />
                </svg>
              </div>
              <h3 class="text-lg font-bold text-base-content">Rincón de Lectura</h3>
              <p class="text-sm text-base-content/60 mt-2 leading-relaxed">
                Reserva un espacio tranquilo para leer, escribir o simplemente desconectarte
                con una buena taza. Tu refugio en la ciudad.
              </p>
              <div class="mt-4 flex flex-wrap gap-2">
                <span class="badge badge-ghost text-xs">Individual o en pareja</span>
                <span class="badge badge-ghost text-xs">Ambiente relajado</span>
              </div>
            </div>
          </div>

          <!-- Encuentro con amigos -->
          <div class="card bg-base-100 border border-base-300 shadow-sm hover:shadow-md transition-shadow sm:col-span-2 lg:col-span-1">
            <div class="card-body p-6">
              <div class="w-12 h-12 bg-primary/10 rounded-2xl flex items-center justify-center mb-4">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6 text-primary" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M4.318 6.318a4.5 4.5 0 000 6.364L12 20.364l7.682-7.682a4.5 4.5 0 00-6.364-6.364L12 7.636l-1.318-1.318a4.5 4.5 0 00-6.364 0z" />
                </svg>
              </div>
              <h3 class="text-lg font-bold text-base-content">Encuentro con Amigos</h3>
              <p class="text-sm text-base-content/60 mt-2 leading-relaxed">
                Reúnete con quienes más quieres. Aparta una mesa, trae a tu gente
                y deja que Café Raíces y Cultura sea el escenario perfecto.
              </p>
              <div class="mt-4 flex flex-wrap gap-2">
                <span class="badge badge-ghost text-xs">Pequeños grupos</span>
                <span class="badge badge-ghost text-xs">Ambiente íntimo</span>
              </div>
            </div>
          </div>

        </div>

        <!-- CTA — contact via WhatsApp meanwhile -->
        <div class="text-center">
          <p class="text-base-content/50 text-sm mb-4">
            Mientras habilitamos el sistema de reservas, escríbenos directamente:
          </p>
          <a
            href="https://wa.me/525551234567?text=Hola%2C%20me%20interesa%20reservar%20una%20experiencia%20en%20Café%20Raíces%20y%20Cultura"
            target="_blank"
            rel="noopener noreferrer"
            class="btn btn-primary btn-lg gap-2"
          >
            <svg class="h-5 w-5" viewBox="0 0 24 24" fill="currentColor">
              <path d="M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347m-5.421 7.403h-.004a9.87 9.87 0 01-5.031-1.378l-.361-.214-3.741.982.998-3.648-.235-.374a9.86 9.86 0 01-1.51-5.26c.001-5.45 4.436-9.884 9.888-9.884 2.64 0 5.122 1.03 6.988 2.898a9.825 9.825 0 012.893 6.994c-.003 5.45-4.437 9.884-9.885 9.884m8.413-18.297A11.815 11.815 0 0012.05 0C5.495 0 .16 5.335.157 11.892c0 2.096.547 4.142 1.588 5.945L.057 24l6.305-1.654a11.882 11.882 0 005.683 1.448h.005c6.554 0 11.89-5.335 11.893-11.893a11.821 11.821 0 00-3.48-8.413z"/>
            </svg>
            Contáctanos por WhatsApp
          </a>
        </div>

      </div>
    </section>
    """
  end

  # ---------------------------------------------------------------------------
  # Contacto / Redes / Mapa
  # ---------------------------------------------------------------------------

  defp contact_section(assigns) do
    ~H"""
    <section id="contacto" class="py-16 sm:py-20 lg:py-24 bg-base-100">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="text-center mb-10 sm:mb-14">
          <span class="inline-block text-primary font-semibold text-sm uppercase tracking-widest mb-3">
            Encuéntranos
          </span>
          <h2 class="text-3xl sm:text-4xl font-bold text-base-content">Visítanos</h2>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-10 lg:gap-16 items-start">
          <!-- Contact info + Social -->
          <div class="space-y-8">
            <!-- Address -->
            <div class="flex gap-4">
              <div class="w-10 h-10 bg-primary/10 rounded-xl flex items-center justify-center flex-shrink-0 mt-0.5">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 text-primary" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
                </svg>
              </div>
              <div>
                <p class="font-semibold text-base-content">Dirección</p>
                <p class="text-base-content/70 mt-0.5">
                  Coquimbo 709, Lindavista Sur<br />
                  Ciudad de México, CDMX 07300
                </p>
              </div>
            </div>

            <!-- Phone -->
            <div class="flex gap-4">
              <div class="w-10 h-10 bg-primary/10 rounded-xl flex items-center justify-center flex-shrink-0 mt-0.5">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 text-primary" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 5a2 2 0 012-2h3.28a1 1 0 01.948.684l1.498 4.493a1 1 0 01-.502 1.21l-2.257 1.13a11.042 11.042 0 005.516 5.516l1.13-2.257a1 1 0 011.21-.502l4.493 1.498a1 1 0 01.684.949V19a2 2 0 01-2 2h-1C9.716 21 3 14.284 3 6V5z" />
                </svg>
              </div>
              <div>
                <p class="font-semibold text-base-content">Teléfono</p>
                <a href="tel:+525551234567" class="text-base-content/70 hover:text-primary transition-colors mt-0.5 block">
                  55 5123-4567
                </a>
              </div>
            </div>

            <!-- Hours -->
            <div class="flex gap-4">
              <div class="w-10 h-10 bg-primary/10 rounded-xl flex items-center justify-center flex-shrink-0 mt-0.5">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 text-primary" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
              </div>
              <div>
                <p class="font-semibold text-base-content">Horario</p>
                <p class="text-base-content/70 mt-0.5">
                  Lunes – Viernes: 8:00 – 21:00<br />
                  Sábado – Domingo: 9:00 – 22:00
                </p>
              </div>
            </div>

            <!-- Social media -->
            <div>
              <p class="font-semibold text-base-content mb-4">Síguenos</p>
              <div class="flex gap-3">
                <!-- Instagram -->
                <a
                  href="https://www.instagram.com/crc.2020/"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="w-10 h-10 bg-base-200 hover:bg-primary hover:text-primary-content rounded-xl flex items-center justify-center transition-all group"
                  aria-label="Instagram"
                >
                  <svg class="h-5 w-5" viewBox="0 0 24 24" fill="currentColor">
                    <path d="M12 2.163c3.204 0 3.584.012 4.85.07 3.252.148 4.771 1.691 4.919 4.919.058 1.265.069 1.645.069 4.849 0 3.205-.012 3.584-.069 4.849-.149 3.225-1.664 4.771-4.919 4.919-1.266.058-1.644.07-4.85.07-3.204 0-3.584-.012-4.849-.07-3.26-.149-4.771-1.699-4.919-4.92-.058-1.265-.07-1.644-.07-4.849 0-3.204.013-3.583.07-4.849.149-3.227 1.664-4.771 4.919-4.919 1.266-.057 1.645-.069 4.849-.069zm0-2.163c-3.259 0-3.667.014-4.947.072-4.358.2-6.78 2.618-6.98 6.98-.059 1.281-.073 1.689-.073 4.948 0 3.259.014 3.668.072 4.948.2 4.358 2.618 6.78 6.98 6.98 1.281.058 1.689.072 4.948.072 3.259 0 3.668-.014 4.948-.072 4.354-.2 6.782-2.618 6.979-6.98.059-1.28.073-1.689.073-4.948 0-3.259-.014-3.667-.072-4.947-.196-4.354-2.617-6.78-6.979-6.98-1.281-.059-1.69-.073-4.949-.073zm0 5.838c-3.403 0-6.162 2.759-6.162 6.162s2.759 6.163 6.162 6.163 6.162-2.759 6.162-6.163c0-3.403-2.759-6.162-6.162-6.162zm0 10.162c-2.209 0-4-1.79-4-4 0-2.209 1.791-4 4-4s4 1.791 4 4c0 2.21-1.791 4-4 4zm6.406-11.845c-.796 0-1.441.645-1.441 1.44s.645 1.44 1.441 1.44c.795 0 1.439-.645 1.439-1.44s-.644-1.44-1.439-1.44z"/>
                  </svg>
                </a>
                <!-- Facebook placeholder -->
                <a
                  href="#"
                  class="w-10 h-10 bg-base-200 hover:bg-primary hover:text-primary-content rounded-xl flex items-center justify-center transition-all"
                  aria-label="Facebook"
                >
                  <svg class="h-5 w-5" viewBox="0 0 24 24" fill="currentColor">
                    <path d="M24 12.073c0-6.627-5.373-12-12-12s-12 5.373-12 12c0 5.99 4.388 10.954 10.125 11.854v-8.385H7.078v-3.47h3.047V9.43c0-3.007 1.792-4.669 4.533-4.669 1.312 0 2.686.235 2.686.235v2.953H15.83c-1.491 0-1.956.925-1.956 1.874v2.25h3.328l-.532 3.47h-2.796v8.385C19.612 23.027 24 18.062 24 12.073z"/>
                  </svg>
                </a>
                <!-- WhatsApp -->
                <a
                  href="https://wa.me/525551234567"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="w-10 h-10 bg-base-200 hover:bg-primary hover:text-primary-content rounded-xl flex items-center justify-center transition-all"
                  aria-label="WhatsApp"
                >
                  <svg class="h-5 w-5" viewBox="0 0 24 24" fill="currentColor">
                    <path d="M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347m-5.421 7.403h-.004a9.87 9.87 0 01-5.031-1.378l-.361-.214-3.741.982.998-3.648-.235-.374a9.86 9.86 0 01-1.51-5.26c.001-5.45 4.436-9.884 9.888-9.884 2.64 0 5.122 1.03 6.988 2.898a9.825 9.825 0 012.893 6.994c-.003 5.45-4.437 9.884-9.885 9.884m8.413-18.297A11.815 11.815 0 0012.05 0C5.495 0 .16 5.335.157 11.892c0 2.096.547 4.142 1.588 5.945L.057 24l6.305-1.654a11.882 11.882 0 005.683 1.448h.005c6.554 0 11.89-5.335 11.893-11.893a11.821 11.821 0 00-3.48-8.413z"/>
                  </svg>
                </a>
              </div>
            </div>
          </div>

          <!-- Google Maps embed -->
          <div class="rounded-2xl overflow-hidden shadow-xl border border-base-300">
            <iframe
              src="https://www.google.com/maps/embed?pb=!1m18!1m12!1m3!1d3762.123456789!2d-99.14!3d19.48!2m3!1f0!2f0!3f0!3m2!1i1024!2i768!4f13.1!3m3!1m2!1s0x85d1f8b6f4a3e5c1%3A0x123456789abcdef!2sCoquimbo%20709%2C%20Lindavista%20Sur%2C%2007300%20Ciudad%20de%20M%C3%A9xico%2C%20CDMX!5e0!3m2!1ses!2smx!4v1234567890"
              class="w-full h-64 sm:h-80 lg:h-96"
              style="border: 0"
              allowfullscreen=""
              loading="lazy"
              referrerpolicy="no-referrer-when-downgrade"
              title="Ubicación de Café Raíces y Cultura"
            ></iframe>
          </div>
        </div>
      </div>
    </section>
    """
  end

  # ---------------------------------------------------------------------------
  # Footer
  # ---------------------------------------------------------------------------

  defp footer(assigns) do
    ~H"""
    <footer class="bg-neutral text-neutral-content py-8 sm:py-10">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="flex flex-col sm:flex-row items-center justify-between gap-4">
          <div class="flex items-center gap-2">
            <div class="w-7 h-7 rounded-full bg-primary flex items-center justify-center text-primary-content font-bold text-xs">
              CRC
            </div>
            <span class="font-semibold text-sm">Café Raíces y Cultura</span>
          </div>

          <nav class="flex gap-5 text-sm text-neutral-content/70">
            <a href="#nosotros" class="hover:text-neutral-content transition-colors">Nosotros</a>
            <a href="#menu" class="hover:text-neutral-content transition-colors">Menú</a>
            <a href="#booking" class="hover:text-neutral-content transition-colors">Booking</a>
            <a href="#contacto" class="hover:text-neutral-content transition-colors">Contacto</a>
          </nav>

          <p class="text-xs text-neutral-content/50">
            © {Date.utc_today().year} Café Raíces y Cultura
          </p>
        </div>
      </div>
    </footer>
    """
  end
end
