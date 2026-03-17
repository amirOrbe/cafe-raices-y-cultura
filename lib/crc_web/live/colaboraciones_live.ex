defmodule CRCWeb.ColaboracionesLive do
  @moduledoc "Full-page collaborations LiveView at /colaboraciones."

  use CRCWeb, :live_view

  alias CRCWeb.Components.SiteComponents

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Colaboraciones — Café Raíces y Cultura")
      |> assign(:nav_open, false)

    {:ok, socket}
  end

  @impl true
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
      <SiteComponents.site_navbar nav_open={@nav_open} current_page={:colaboraciones} />
      <main class="flex-1 pt-16">

        <!-- Page hero -->
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

        <!-- Colaboraciones pasadas -->
        <section class="py-16 sm:py-20 bg-base-100">
          <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">

            <div class="text-center mb-12">
              <h2 class="text-2xl sm:text-3xl font-bold text-base-content">
                Lo que hemos construido juntos
              </h2>
              <p class="mt-3 text-base-content/60 max-w-xl mx-auto">
                Cada colaboración deja huella. Estas son algunas de las experiencias
                que hemos creado con artistas y creadores de la ciudad.
              </p>
            </div>

            <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">

              <!-- Sesiones de DJ -->
              <div class="bg-base-200 border border-base-300 rounded-2xl p-6 hover:shadow-md transition-shadow group">
                <div class="w-12 h-12 bg-primary/10 rounded-2xl flex items-center justify-center mb-5 group-hover:bg-primary/20 transition-colors">
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6 text-primary" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M9 19V6l12-3v13M9 19c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2zm12-3c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2zM9 10l12-3" />
                  </svg>
                </div>
                <h3 class="text-lg font-bold text-base-content mb-2">Sesiones de DJ</h3>
                <p class="text-sm text-base-content/60 leading-relaxed mb-4">
                  Noches en las que el café se transforma en pista. DJs locales han traído
                  desde house hasta música latinoamericana experimental, creando una atmósfera
                  única entre tazas y personas.
                </p>
                <div class="flex flex-wrap gap-2">
                  <span class="badge badge-ghost text-xs">Música en vivo</span>
                  <span class="badge badge-ghost text-xs">Noche</span>
                </div>
              </div>

              <!-- Lecturas de poesía -->
              <div class="bg-base-200 border border-base-300 rounded-2xl p-6 hover:shadow-md transition-shadow group">
                <div class="w-12 h-12 bg-secondary/10 rounded-2xl flex items-center justify-center mb-5 group-hover:bg-secondary/20 transition-colors">
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6 text-secondary" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.572L16.732 3.732z" />
                  </svg>
                </div>
                <h3 class="text-lg font-bold text-base-content mb-2">Lecturas de Poesía</h3>
                <p class="text-sm text-base-content/60 leading-relaxed mb-4">
                  Poetas de la ciudad y del barrio han tomado el micrófono en CRC para compartir
                  su voz. Tardes de verso y café que conectan al público con la literatura
                  contemporánea mexicana.
                </p>
                <div class="flex flex-wrap gap-2">
                  <span class="badge badge-ghost text-xs">Literatura</span>
                  <span class="badge badge-ghost text-xs">Arte oral</span>
                </div>
              </div>

              <!-- Baristas & Coctelería -->
              <div class="bg-base-200 border border-base-300 rounded-2xl p-6 hover:shadow-md transition-shadow group sm:col-span-2 lg:col-span-1">
                <div class="w-12 h-12 bg-accent/10 rounded-2xl flex items-center justify-center mb-5 group-hover:bg-accent/20 transition-colors">
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6 text-accent" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M9.75 17L9 20l-1 1h8l-1-1-.75-3M3 13h18M5 17h14a2 2 0 002-2V5a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
                  </svg>
                </div>
                <h3 class="text-lg font-bold text-base-content mb-2">Baristas Invitados</h3>
                <p class="text-sm text-base-content/60 leading-relaxed mb-4">
                  Baristas especializados han visitado CRC para compartir su técnica y creatividad
                  a través de la coctelería de especialidad. Propuestas que van más allá del espresso
                  y exploran el café como ingrediente de autor.
                </p>
                <div class="flex flex-wrap gap-2">
                  <span class="badge badge-ghost text-xs">Coctelería</span>
                  <span class="badge badge-ghost text-xs">Café de especialidad</span>
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
