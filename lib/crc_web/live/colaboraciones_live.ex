defmodule CRCWeb.ColaboracionesLive do
  @moduledoc "Full-page collaborations LiveView at /colaboraciones."

  use CRCWeb, :live_view

  alias CRCWeb.Components.SiteComponents

  # ── Static data (update here as events are confirmed / archived) ─────────────

  @upcoming [
    %{
      title: "Sesión DJ — Electrónica Latinoamericana",
      date: "Abril 2026",
      confirmed: false,
      description:
        "Una noche dedicada al sonido electrónico con raíces latinoamericanas. DJ invitado por confirmar.",
      tags: ["Música", "Noche"]
    },
    %{
      title: "Lectura Abierta de Poesía",
      date: "Mayo 2026",
      confirmed: false,
      description:
        "Espacio abierto para poetas de la comunidad. Micrófono libre, taza de café y palabras que conectan.",
      tags: ["Literatura", "Comunidad"]
    }
  ]

  @historico [
    %{
      mes: "Mar",
      year: "2026",
      title: "Barista Invitado — Coctelería de Café Vol. 2",
      tipo: "Café de especialidad",
      nota: "Segunda edición con nuevas propuestas de autor."
    },
    %{
      mes: "Feb",
      year: "2026",
      title: "Tarde de Poesía Contemporánea",
      tipo: "Literatura",
      nota: "Poetas de la colonia y de la ciudad tomaron el micrófono."
    },
    %{
      mes: "Ene",
      year: "2026",
      title: "Sesión DJ — House & Experimental",
      tipo: "Música",
      nota: "Primera noche musical del año, sold out."
    },
    %{
      mes: "Dic",
      year: "2025",
      title: "Sesión DJ — Fin de Año",
      tipo: "Música",
      nota: "Noche especial para despedir el 2025 entre música y café."
    },
    %{
      mes: "Nov",
      year: "2025",
      title: "Barista Invitado — Coctelería de Café Vol. 1",
      tipo: "Café de especialidad",
      nota: "Primera edición: espresso, fermentados y propuestas de autor."
    },
    %{
      mes: "Oct",
      year: "2025",
      title: "Lectura de Poesía — Noche de Voces",
      tipo: "Literatura",
      nota: "Inaugural del ciclo de lecturas en CRC."
    }
  ]

  @tipo_badge_colors %{
    "Música" => "badge-primary",
    "Literatura" => "badge-secondary",
    "Café de especialidad" => "badge-accent",
    "Comunidad" => "badge-neutral"
  }

  # ── LiveView callbacks ────────────────────────────────────────────────────────

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Colaboraciones — Café Raíces y Cultura")
      |> assign(:nav_open, false)
      |> assign(:upcoming, @upcoming)
      |> assign(:historico, @historico)

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_nav", _params, socket) do
    {:noreply, assign(socket, :nav_open, !socket.assigns.nav_open)}
  end

  def handle_event("close_nav", _params, socket) do
    {:noreply, assign(socket, :nav_open, false)}
  end

  # ── Render ────────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :tipo_colors, @tipo_badge_colors)

    ~H"""
    <div class="min-h-screen flex flex-col">
      <SiteComponents.site_navbar nav_open={@nav_open} current_page={:colaboraciones} />
      <main class="flex-1 pt-16">

        <!-- Hero -->
        <div class="bg-primary text-primary-content py-14 sm:py-20">
          <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 text-center">
            <span class="inline-block text-primary-content/70 font-semibold text-sm uppercase tracking-widest mb-3">
              Comunidad & Cultura
            </span>
            <h1 class="text-4xl sm:text-5xl font-bold mb-4">Colaboraciones</h1>
            <p class="text-primary-content/80 text-base sm:text-xl max-w-2xl mx-auto">
              CRC nació como punto de encuentro. Músicos, poetas, baristas y artistas
              han encontrado en nuestro espacio el escenario perfecto para compartir
              su trabajo con la comunidad de Santa María la Ribera.
            </p>
          </div>
        </div>

        <!-- Próximas colaboraciones -->
        <section class="py-16 sm:py-20 bg-base-100">
          <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
            <div class="text-center mb-12">
              <span class="inline-block bg-accent/15 text-accent font-semibold text-xs uppercase tracking-widest px-3 py-1 rounded-full mb-3">
                En camino
              </span>
              <h2 class="text-2xl sm:text-3xl font-bold text-base-content">
                Próximas colaboraciones
              </h2>
              <p class="mt-3 text-base-content/60 max-w-xl mx-auto">
                Lo que viene en CRC. Las fechas se confirman por WhatsApp e Instagram.
              </p>
            </div>

            <div class="grid grid-cols-1 sm:grid-cols-2 gap-6 max-w-4xl mx-auto">
              <div :for={ev <- @upcoming}
                class="relative bg-base-200 border border-base-300 rounded-2xl p-6 hover:shadow-md transition-shadow">
                <!-- "Por confirmar" badge -->
                <span :if={!ev.confirmed}
                  class="absolute top-4 right-4 text-xs font-medium text-base-content/40 bg-base-300 px-2 py-0.5 rounded-full">
                  Por confirmar
                </span>
                <div class="mb-4 flex items-center gap-2">
                  <span class="text-sm font-semibold text-accent">
                    <%= ev.date %>
                  </span>
                </div>
                <h3 class="text-base font-bold text-base-content mb-2"><%= ev.title %></h3>
                <p class="text-sm text-base-content/60 leading-relaxed mb-4">
                  <%= ev.description %>
                </p>
                <div class="flex flex-wrap gap-2">
                  <span :for={tag <- ev.tags} class="badge badge-ghost text-xs">
                    <%= tag %>
                  </span>
                </div>
              </div>
            </div>
          </div>
        </section>

        <!-- Tipos de colaboración -->
        <section class="py-16 sm:py-20 bg-base-200">
          <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">

            <div class="text-center mb-12">
              <h2 class="text-2xl sm:text-3xl font-bold text-base-content">
                ¿Qué hacemos juntos?
              </h2>
              <p class="mt-3 text-base-content/60 max-w-xl mx-auto">
                Estas son las formas en las que artistas y creadores han dado vida a CRC.
              </p>
            </div>

            <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">

              <!-- Sesiones de DJ -->
              <div class="bg-base-100 border border-base-300 rounded-2xl p-6 hover:shadow-md transition-shadow group">
                <div class="w-12 h-12 bg-primary/10 rounded-2xl flex items-center justify-center mb-5 group-hover:bg-primary/20 transition-colors">
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6 text-primary" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M9 19V6l12-3v13M9 19c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2zm12-3c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2zM9 10l12-3" />
                  </svg>
                </div>
                <h3 class="text-lg font-bold text-base-content mb-2">Sesiones de DJ</h3>
                <p class="text-sm text-base-content/60 leading-relaxed mb-4">
                  Noches en las que el café se transforma. DJs locales han traído desde house
                  hasta música latinoamericana experimental, creando una atmósfera única
                  entre tazas y personas.
                </p>
                <div class="flex flex-wrap gap-2">
                  <span class="badge badge-ghost text-xs">Música en vivo</span>
                  <span class="badge badge-ghost text-xs">Noche</span>
                </div>
              </div>

              <!-- Lecturas de poesía -->
              <div class="bg-base-100 border border-base-300 rounded-2xl p-6 hover:shadow-md transition-shadow group">
                <div class="w-12 h-12 bg-secondary/10 rounded-2xl flex items-center justify-center mb-5 group-hover:bg-secondary/20 transition-colors">
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6 text-secondary" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.572L16.732 3.732z" />
                  </svg>
                </div>
                <h3 class="text-lg font-bold text-base-content mb-2">Lecturas de Poesía</h3>
                <p class="text-sm text-base-content/60 leading-relaxed mb-4">
                  Poetas de la ciudad y del barrio han tomado el micrófono en CRC para
                  compartir su voz. Tardes de verso y café que conectan al público con
                  la literatura contemporánea mexicana.
                </p>
                <div class="flex flex-wrap gap-2">
                  <span class="badge badge-ghost text-xs">Literatura</span>
                  <span class="badge badge-ghost text-xs">Arte oral</span>
                </div>
              </div>

              <!-- Baristas invitados -->
              <div class="bg-base-100 border border-base-300 rounded-2xl p-6 hover:shadow-md transition-shadow group sm:col-span-2 lg:col-span-1">
                <div class="w-12 h-12 bg-accent/10 rounded-2xl flex items-center justify-center mb-5 group-hover:bg-accent/20 transition-colors">
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6 text-accent" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M12 6V4m0 2a2 2 0 100 4m0-4a2 2 0 110 4m-6 8a2 2 0 100-4m0 4a2 2 0 110-4m0 4v2m0-6V4m6 6v10m6-2a2 2 0 100-4m0 4a2 2 0 110-4m0 4v2m0-6V4" />
                  </svg>
                </div>
                <h3 class="text-lg font-bold text-base-content mb-2">Baristas Invitados</h3>
                <p class="text-sm text-base-content/60 leading-relaxed mb-4">
                  Baristas especializados han visitado CRC para compartir su técnica y
                  creatividad a través de la coctelería de especialidad. Propuestas que
                  van más allá del espresso y exploran el café como ingrediente de autor.
                </p>
                <div class="flex flex-wrap gap-2">
                  <span class="badge badge-ghost text-xs">Coctelería</span>
                  <span class="badge badge-ghost text-xs">Café de especialidad</span>
                </div>
              </div>

            </div>
          </div>
        </section>

        <!-- Histórico -->
        <section class="py-16 sm:py-20 bg-base-100">
          <div class="max-w-3xl mx-auto px-4 sm:px-6 lg:px-8">

            <div class="text-center mb-12">
              <span class="inline-block bg-primary/10 text-primary font-semibold text-xs uppercase tracking-widest px-3 py-1 rounded-full mb-3">
                Memoria
              </span>
              <h2 class="text-2xl sm:text-3xl font-bold text-base-content">
                Lo que hemos construido juntos
              </h2>
              <p class="mt-3 text-base-content/60 max-w-xl mx-auto">
                Cada colaboración deja huella. Aquí el registro de lo que hemos
                creado con artistas y creadores de la ciudad.
              </p>
            </div>

            <!-- Timeline -->
            <div class="relative">
              <!-- vertical line -->
              <div class="absolute left-16 top-0 bottom-0 w-px bg-base-300 hidden sm:block"></div>

              <div class="space-y-6">
                <div :for={ev <- @historico}
                  class="flex gap-4 sm:gap-6 items-start group">

                  <!-- Date stamp -->
                  <div class="w-14 flex-shrink-0 text-center">
                    <div class="text-xs font-bold text-primary uppercase"><%= ev.mes %></div>
                    <div class="text-xs text-base-content/40"><%= ev.year %></div>
                  </div>

                  <!-- Dot -->
                  <div class="hidden sm:flex items-center justify-center w-5 h-5 flex-shrink-0 mt-0.5 -ml-2.5 relative z-10">
                    <div class="w-3 h-3 rounded-full bg-base-300 border-2 border-base-100 group-hover:bg-primary transition-colors"></div>
                  </div>

                  <!-- Content -->
                  <div class="flex-1 bg-base-200 rounded-xl p-4 hover:shadow-sm transition-shadow">
                    <div class="flex flex-wrap items-start justify-between gap-2 mb-1">
                      <h3 class="text-sm font-bold text-base-content"><%= ev.title %></h3>
                      <span class={"badge badge-sm #{Map.get(@tipo_colors, ev.tipo, "badge-ghost")} text-xs"}>
                        <%= ev.tipo %>
                      </span>
                    </div>
                    <p class="text-xs text-base-content/55 leading-relaxed"><%= ev.nota %></p>
                  </div>

                </div>
              </div>
            </div>

          </div>
        </section>

        <!-- CTA: propón tu colaboración -->
        <section class="py-16 sm:py-20 bg-base-200">
          <div class="max-w-3xl mx-auto px-4 sm:px-6 lg:px-8">
            <div class="bg-primary rounded-3xl px-6 py-12 sm:px-12 sm:py-16 text-center text-primary-content">
              <h2 class="text-2xl sm:text-3xl font-bold mb-4">
                ¿Tienes una propuesta?
              </h2>
              <p class="text-primary-content/80 text-base sm:text-lg max-w-xl mx-auto mb-8">
                CRC está siempre abierto a nuevas colaboraciones. Si eres músico, artista,
                escritor, barista o simplemente tienes una idea que quieras compartir con
                la comunidad, queremos escucharte.
              </p>
              <a
                href="https://wa.me/525551234567?text=Hola%2C%20me%20gustaría%20proponer%20una%20colaboración%20con%20Café%20Raíces%20y%20Cultura"
                target="_blank"
                rel="noopener noreferrer"
                class="btn btn-lg bg-white text-primary border-0 hover:bg-white/90 gap-2 shadow-md"
              >
                <svg class="h-5 w-5" viewBox="0 0 24 24" fill="currentColor">
                  <path d="M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347m-5.421 7.403h-.004a9.87 9.87 0 01-5.031-1.378l-.361-.214-3.741.982.998-3.648-.235-.374a9.86 9.86 0 01-1.51-5.26c.001-5.45 4.436-9.884 9.888-9.884 2.64 0 5.122 1.03 6.988 2.898a9.825 9.825 0 012.893 6.994c-.003 5.45-4.437 9.884-9.885 9.884m8.413-18.297A11.815 11.815 0 0012.05 0C5.495 0 .16 5.335.157 11.892c0 2.096.547 4.142 1.588 5.945L.057 24l6.305-1.654a11.882 11.882 0 005.683 1.448h.005c6.554 0 11.89-5.335 11.893-11.893a11.821 11.821 0 00-3.48-8.413z"/>
                </svg>
                Escríbenos por WhatsApp
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
