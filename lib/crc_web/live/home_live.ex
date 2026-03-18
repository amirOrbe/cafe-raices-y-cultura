defmodule CRCWeb.HomeLive do
  @moduledoc "Single-page home LiveView for Café Raíces y Cultura."

  use CRCWeb, :live_view

  alias CRCWeb.Components.SiteComponents

  @impl true
  def mount(_params, _session, socket) do
    # Carousel always uses local photos shuffled randomly — every visit shows a different order
    photos = carousel_photos() |> Enum.shuffle()

    socket =
      socket
      |> assign(:page_title, "Café Raíces y Cultura")
      |> assign(:photos, photos)
      |> assign(:active_slide, 0)
      |> assign(:nav_open, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("carousel_next", _params, socket) do
    total = length(socket.assigns.photos)
    next = rem(socket.assigns.active_slide + 1, total)
    {:noreply, assign(socket, :active_slide, next)}
  end

  def handle_event("carousel_goto", %{"index" => index}, socket) do
    {:noreply, assign(socket, :active_slide, String.to_integer(index))}
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
      <SiteComponents.site_navbar nav_open={@nav_open} current_page={:home} />
      <main class="flex-1">
        <.hero_section photos={@photos} active_slide={@active_slide} />
        <.about_section />
        <.contact_section />
      </main>
      <SiteComponents.site_footer />
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Placeholder data (shown when DB is empty)
  # ---------------------------------------------------------------------------

  # All 19 real CRC photos — shuffled on every mount so each visit looks different
  defp carousel_photos do
    [
      %{url: "/images/carousel/crc-01.jpg", caption: "Café Raíces y Cultura"},
      %{url: "/images/carousel/crc-02.jpg", caption: "Un espacio para conectar"},
      %{url: "/images/carousel/crc-03.jpg", caption: "Café de origen seleccionado"},
      %{url: "/images/carousel/crc-04.jpg", caption: "Arte y sabor en cada taza"},
      %{url: "/images/carousel/crc-05.jpg", caption: "Tu refugio en Santa María la Ribera"},
      %{url: "/images/carousel/crc-06.jpg", caption: "Café Raíces y Cultura"},
      %{url: "/images/carousel/crc-07.jpg", caption: "Hecho con amor y detalle"},
      %{url: "/images/carousel/crc-08.jpg", caption: "Raíces que nos sostienen"},
      %{url: "/images/carousel/crc-09.jpg", caption: "Cultura que inspira"},
      %{url: "/images/carousel/crc-10.jpg", caption: "Un proyecto familiar"},
      %{url: "/images/carousel/crc-11.jpg", caption: "Granos de origen seleccionado"},
      %{url: "/images/carousel/crc-12.jpg", caption: "Santa María la Ribera · CDMX"},
      %{url: "/images/carousel/crc-13.jpg", caption: "Café Raíces y Cultura"},
      %{url: "/images/carousel/crc-14.jpg", caption: "Cada taza, una historia"},
      %{url: "/images/carousel/crc-15.jpg", caption: "Bienvenidos a CRC"},
      %{url: "/images/carousel/crc-16.jpg", caption: "Arte, café y cultura"},
      %{url: "/images/carousel/crc-17.jpg", caption: "Compromiso con la comunidad"},
      %{url: "/images/carousel/crc-18.jpg", caption: "Lo artesanal en cada detalle"},
      %{url: "/images/carousel/crc-19.jpg", caption: "Ven y descúbrenos"}
    ]
  end

  # ---------------------------------------------------------------------------
  # Hero / Carousel
  # ---------------------------------------------------------------------------

  defp hero_section(%{photos: []} = assigns) do
    ~H"""
    <section id="inicio" class="relative pt-16 h-64 sm:h-80 md:h-[500px] lg:h-[600px] bg-primary flex items-center justify-center">
      <div class="text-center text-primary-content px-4">
        <h1 class="text-3xl sm:text-5xl font-bold mb-4">Café Raíces y Cultura</h1>
        <p class="text-lg sm:text-xl opacity-90">Santa María la Ribera · CDMX</p>
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
          <div class={"absolute inset-0 transition-opacity duration-700 #{if index == @active_slide, do: "opacity-100 z-10", else: "opacity-0 z-0"}"}>
            <img
              src={photo.url}
              alt={photo.caption || "Café Raíces y Cultura"}
              class="w-full h-full object-cover"
              loading={if index == 0, do: "eager", else: "lazy"}
            />
            <div class="absolute inset-0 bg-gradient-to-t from-black/60 via-black/10 to-transparent"></div>
            <div :if={photo.caption} class="absolute bottom-12 md:bottom-16 left-0 right-0 text-center px-4">
              <p class="text-white text-base sm:text-lg md:text-2xl font-medium drop-shadow-lg">
                {photo.caption}
              </p>
            </div>
          </div>
        <% end %>
      </div>

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

      <!-- Headline overlay -->
      <div class="absolute inset-x-0 top-1/2 -translate-y-1/2 z-20 text-center px-4 pointer-events-none">
        <h1 class="text-2xl sm:text-4xl md:text-5xl lg:text-6xl font-bold text-white drop-shadow-xl leading-tight">
          Café Raíces y Cultura
        </h1>
        <p class="mt-2 text-sm sm:text-base md:text-lg text-white/90 drop-shadow">
          Santa María la Ribera · Ciudad de México
        </p>
      </div>
    </section>
    """
  end

  # ---------------------------------------------------------------------------
  # Nosotros (About) — contenido real del café
  # ---------------------------------------------------------------------------

  defp about_section(assigns) do
    ~H"""
    <section id="nosotros" class="py-16 sm:py-20 lg:py-24 bg-base-100">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">

        <!-- Header -->
        <div class="text-center mb-12 sm:mb-16">
          <span class="inline-block text-primary font-semibold text-sm uppercase tracking-widest mb-3">
            Nuestra historia
          </span>
          <h2 class="text-3xl sm:text-4xl font-bold text-base-content leading-tight">
            Un espacio para conectar
          </h2>
        </div>

        <!-- Intro + imagen -->
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-10 lg:gap-16 items-center mb-16 sm:mb-20">
          <!-- Imagen -->
          <div class="relative rounded-2xl overflow-hidden shadow-xl aspect-[4/3]">
            <img
              src="https://images.unsplash.com/photo-1600093463592-8e36ae95ef56?w=800&auto=format&fit=crop"
              alt="Interior de Café Raíces y Cultura"
              class="w-full h-full object-cover"
              loading="lazy"
            />
            <div class="absolute inset-0 bg-gradient-to-tr from-primary/20 to-transparent"></div>
          </div>

          <!-- Texto intro -->
          <div>
            <p class="text-base-content/70 text-base sm:text-lg leading-relaxed mb-6">
              En un rincón acogedor de la ciudad,
              <strong class="text-base-content">Café Raíces y Cultura</strong>
              se erige como un santuario donde el café se convierte en un puente entre las personas
              y sus historias. Este proyecto familiar nació con la intención de ofrecer más que una
              simple taza de café; es un lugar donde las raíces y la cultura se entrelazan para
              crear experiencias significativas.
            </p>
            <!-- Horarios -->
            <div class="grid grid-cols-2 gap-4">
              <div class="bg-base-200 rounded-xl p-4 text-center">
                <p class="text-xl font-bold text-primary">Lun – Vie</p>
                <p class="text-sm text-base-content/60 mt-1">8:00 – 21:00</p>
              </div>
              <div class="bg-base-200 rounded-xl p-4 text-center">
                <p class="text-xl font-bold text-primary">Sáb – Dom</p>
                <p class="text-sm text-base-content/60 mt-1">9:00 – 22:00</p>
              </div>
            </div>
          </div>
        </div>

        <!-- 4 pilares -->
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-5 sm:gap-6 mb-14">

          <!-- Raíces -->
          <div class="bg-base-200 border border-base-300 rounded-2xl p-6 hover:shadow-md transition-shadow">
            <div class="w-12 h-12 bg-primary/10 rounded-2xl flex items-center justify-center mb-4">
              <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6 text-primary" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M12 3v1m0 16v1m8.66-13l-.87.5M4.21 15.5l-.87.5M20.66 15.5l-.87-.5M4.21 8.5l-.87-.5M21 12h-1M4 12H3m15.07-7.07l-.7.7M6.63 17.37l-.7.7M17.37 17.37l-.7-.7M6.63 6.63l-.7-.7" />
              </svg>
            </div>
            <h3 class="text-base font-bold text-base-content mb-2">Raíces que Sostienen</h3>
            <p class="text-sm text-base-content/60 leading-relaxed">
              Nuestras raíces son profundas, nutridas por la historia y el esfuerzo de quienes
              han guiado este camino. Son el ADN que nos sostiene y nos conecta con el pasado
              para guiarnos hacia el futuro.
            </p>
          </div>

          <!-- Cultura -->
          <div class="bg-base-200 border border-base-300 rounded-2xl p-6 hover:shadow-md transition-shadow">
            <div class="w-12 h-12 bg-secondary/10 rounded-2xl flex items-center justify-center mb-4">
              <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6 text-secondary" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M9.663 17h4.673M12 3v1m6.364 1.636l-.707.707M21 12h-1M4 12H3m3.343-5.657l-.707-.707m2.828 9.9a5 5 0 117.072 0l-.548.547A3.374 3.374 0 0014 18.469V19a2 2 0 11-4 0v-.531c0-.895-.356-1.754-.988-2.386l-.548-.547z" />
              </svg>
            </div>
            <h3 class="text-base font-bold text-base-content mb-2">Cultura que Inspira</h3>
            <p class="text-sm text-base-content/60 leading-relaxed">
              Más que una cafetería, somos un espacio cultural vibrante. Promovemos actividades
              artísticas que unen a las personas y generan un impacto positivo. Somos un faro
              de colaboración y creatividad.
            </p>
          </div>

          <!-- Comunidad -->
          <div class="bg-base-200 border border-base-300 rounded-2xl p-6 hover:shadow-md transition-shadow">
            <div class="w-12 h-12 bg-accent/10 rounded-2xl flex items-center justify-center mb-4">
              <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6 text-accent" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0z" />
              </svg>
            </div>
            <h3 class="text-base font-bold text-base-content mb-2">Compromiso con la Comunidad</h3>
            <p class="text-sm text-base-content/60 leading-relaxed">
              Creemos en la trazabilidad del café, mostrando el impacto de quienes lo producen.
              Nuestra visión es fomentar comunidades comprometidas que trabajen juntas para
              mejorar el ámbito cafetalero.
            </p>
          </div>

          <!-- Valores -->
          <div class="bg-base-200 border border-base-300 rounded-2xl p-6 hover:shadow-md transition-shadow">
            <div class="w-12 h-12 bg-primary/10 rounded-2xl flex items-center justify-center mb-4">
              <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6 text-primary" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M4.318 6.318a4.5 4.5 0 000 6.364L12 20.364l7.682-7.682a4.5 4.5 0 00-6.364-6.364L12 7.636l-1.318-1.318a4.5 4.5 0 00-6.364 0z" />
              </svg>
            </div>
            <h3 class="text-base font-bold text-base-content mb-2">Valores que Nos Definen</h3>
            <p class="text-sm text-base-content/60 leading-relaxed">
              Empatía, respeto, colaboración e integridad son el pilar de cada acción. Promovemos
              el trabajo en equipo, la responsabilidad social y la conciencia del entorno con
              perseverancia y resiliencia.
            </p>
          </div>

        </div>

        <!-- Cierre -->
        <div class="text-center max-w-2xl mx-auto">
          <p class="text-base-content/60 text-base sm:text-lg leading-relaxed">
            En CRC somos personas cálidas y versátiles, siempre en busca de nuevos horizontes.
            Ven y descubre un espacio donde el <strong class="text-base-content">café</strong>,
            el <strong class="text-base-content">arte</strong> y la
            <strong class="text-base-content">cultura</strong>
            convergen para nutrir y transformar nuestro entorno.
          </p>
          <p class="mt-4 text-primary font-semibold">
            ¡Te esperamos en Café Raíces y Cultura para compartir una experiencia única y auténtica!
          </p>
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
    <section id="contacto" class="py-16 sm:py-20 lg:py-24 bg-base-200">
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
            <!-- Dirección -->
            <div class="flex gap-4">
              <div class="w-10 h-10 bg-primary/10 rounded-xl flex items-center justify-center flex-shrink-0 mt-0.5">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 text-primary" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
                </svg>
              </div>
              <div>
                <p class="font-semibold text-base-content">Dirección</p>
                <a
                  href="https://maps.app.goo.gl/zWn8XyzHjHwZS9RA9"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="text-base-content/70 mt-0.5 hover:text-primary transition-colors block"
                >
                  Dr. Mariano Azuela #80 Local A<br />
                  Col. Santa María la Ribera, CDMX 06400
                </a>
              </div>
            </div>

            <!-- Horario -->
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

            <!-- Redes sociales -->
            <div>
              <p class="font-semibold text-base-content mb-4">Síguenos</p>
              <div class="flex gap-3">
                <!-- Instagram -->
                <a
                  href="https://www.instagram.com/crc.2020/"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="w-10 h-10 bg-base-300 hover:bg-primary hover:text-primary-content rounded-xl flex items-center justify-center transition-all"
                  aria-label="Instagram"
                >
                  <svg class="h-5 w-5" viewBox="0 0 24 24" fill="currentColor">
                    <path d="M12 2.163c3.204 0 3.584.012 4.85.07 3.252.148 4.771 1.691 4.919 4.919.058 1.265.069 1.645.069 4.849 0 3.205-.012 3.584-.069 4.849-.149 3.225-1.664 4.771-4.919 4.919-1.266.058-1.644.07-4.85.07-3.204 0-3.584-.012-4.849-.07-3.26-.149-4.771-1.699-4.919-4.92-.058-1.265-.07-1.644-.07-4.849 0-3.204.013-3.583.07-4.849.149-3.227 1.664-4.771 4.919-4.919 1.266-.057 1.645-.069 4.849-.069zm0-2.163c-3.259 0-3.667.014-4.947.072-4.358.2-6.78 2.618-6.98 6.98-.059 1.281-.073 1.689-.073 4.948 0 3.259.014 3.668.072 4.948.2 4.358 2.618 6.78 6.98 6.98 1.281.058 1.689.072 4.948.072 3.259 0 3.668-.014 4.948-.072 4.354-.2 6.782-2.618 6.979-6.98.059-1.28.073-1.689.073-4.948 0-3.259-.014-3.667-.072-4.947-.196-4.354-2.617-6.78-6.979-6.98-1.281-.059-1.69-.073-4.949-.073zm0 5.838c-3.403 0-6.162 2.759-6.162 6.162s2.759 6.163 6.162 6.163 6.162-2.759 6.162-6.163c0-3.403-2.759-6.162-6.162-6.162zm0 10.162c-2.209 0-4-1.79-4-4 0-2.209 1.791-4 4-4s4 1.791 4 4c0 2.21-1.791 4-4 4zm6.406-11.845c-.796 0-1.441.645-1.441 1.44s.645 1.44 1.441 1.44c.795 0 1.439-.645 1.439-1.44s-.644-1.44-1.439-1.44z"/>
                  </svg>
                </a>
                <!-- Facebook -->
                <a
                  href="https://www.facebook.com/profile.php?id=100057557755021"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="w-10 h-10 bg-base-300 hover:bg-primary hover:text-primary-content rounded-xl flex items-center justify-center transition-all"
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
                  class="w-10 h-10 bg-base-300 hover:bg-primary hover:text-primary-content rounded-xl flex items-center justify-center transition-all"
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
              src="https://maps.google.com/maps?q=Dr.+Mariano+Azuela+80,+Santa+María+la+Ribera,+Cuauhtémoc,+06400+Ciudad+de+México,+CDMX&output=embed&z=17"
              class="w-full h-64 sm:h-80 lg:h-96"
              style="border: 0"
              allowfullscreen=""
              loading="lazy"
              referrerpolicy="no-referrer-when-downgrade"
              title="Ubicación de Café Raíces y Cultura — Dr. Mariano Azuela #80 Local A, Santa María la Ribera"
            ></iframe>
          </div>
        </div>
      </div>
    </section>
    """
  end
end
