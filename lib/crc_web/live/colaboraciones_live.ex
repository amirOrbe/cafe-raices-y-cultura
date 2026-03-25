defmodule CRCWeb.ColaboracionesLive do
  @moduledoc "Full-page collaborations LiveView at /colaboraciones."

  use CRCWeb, :live_view

  alias CRC.Events
  alias CRCWeb.Components.SiteComponents

  # ── LiveView callbacks ────────────────────────────────────────────────────────

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(CRC.PubSub, "admin:events")
      :timer.send_interval(60_000, self(), :tick)
    end

    socket =
      socket
      |> assign(:page_title, "Colaboraciones — Café Raíces y Cultura")
      |> assign(:nav_open, false)
      |> load_events()

    {:ok, socket}
  end

  @impl true
  def handle_info(:tick, socket) do
    {:noreply, load_events(socket)}
  end

  def handle_info({:event_changed, _}, socket) do
    {:noreply, load_events(socket)}
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
    ~H"""
    <div class="min-h-screen flex flex-col">
      <SiteComponents.site_navbar nav_open={@nav_open} current_page={:colaboraciones} current_user={@current_user} />
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

        <!-- Sucediendo ahora -->
        <%= if @current_event != nil do %>
          <section class="py-10 sm:py-14 bg-success/10 border-b border-success/20">
            <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
              <div class="flex items-center gap-3 mb-6">
                <span class="inline-flex items-center gap-1.5 bg-success text-success-content font-bold text-xs uppercase tracking-widest px-3 py-1.5 rounded-full animate-pulse">
                  <span class="inline-block w-2 h-2 rounded-full bg-success-content"></span>
                  EN VIVO
                </span>
                <span class="text-sm text-base-content/60">Sucediendo ahora</span>
              </div>

              <div class="bg-base-100 rounded-2xl border border-success/30 shadow-sm p-6 sm:p-8 max-w-3xl">
                <div class="flex flex-wrap items-center gap-2 mb-3">
                  <%= if @current_event.event_type do %>
                    <span class="badge badge-sm badge-ghost">{@current_event.event_type.name}</span>
                  <% end %>
                  <span class="text-sm text-base-content/60 font-medium">
                    {format_time(@current_event.start_time)} – {format_time(@current_event.end_time)}
                  </span>
                </div>

                <h2 class="text-2xl font-bold text-base-content mb-3">{@current_event.title}</h2>

                <%= if @current_event.description do %>
                  <p class="text-base-content/70 leading-relaxed mb-5">
                    {@current_event.description}
                  </p>
                <% end %>

                <%= if @current_event.event_collaborators != [] do %>
                  <div class="flex flex-wrap gap-2">
                    <%= for ec <- @current_event.event_collaborators do %>
                      <.collaborator_badge collaborator={ec.collaborator} role={ec.role_in_event} />
                    <% end %>
                  </div>
                <% end %>
              </div>
            </div>
          </section>
        <% end %>

        <!-- Próximas colaboraciones -->
        <%= if @upcoming_events != [] do %>
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

              <div class="max-w-2xl mx-auto space-y-6">
                <%= for event <- @upcoming_events do %>
                  <div class="bg-base-200 border border-base-300 rounded-2xl p-8 hover:shadow-md transition-shadow">
                    <div class="mb-4 flex flex-wrap items-center gap-2">
                      <span class="text-sm font-semibold text-accent">
                        {format_event_date(event.event_date)}
                      </span>
                      <span class="text-sm text-base-content/50">
                        {format_time(event.start_time)} – {format_time(event.end_time)}
                      </span>
                      <%= if event.event_type do %>
                        <span class="badge badge-sm badge-ghost">{event.event_type.name}</span>
                      <% end %>
                    </div>

                    <h3 class="text-xl font-bold text-base-content mb-3">{event.title}</h3>

                    <%= if event.description do %>
                      <p class="text-sm text-base-content/60 leading-relaxed mb-5">
                        {event.description}
                      </p>
                    <% end %>

                    <%= if event.tags != [] do %>
                      <div class="flex flex-wrap gap-2 mb-5">
                        <span :for={tag <- event.tags} class="badge badge-ghost text-xs">
                          {tag}
                        </span>
                      </div>
                    <% end %>

                    <%= if event.event_collaborators != [] do %>
                      <div class="flex flex-wrap gap-2 pt-3 border-t border-base-300">
                        <%= for ec <- event.event_collaborators do %>
                          <.collaborator_badge collaborator={ec.collaborator} role={ec.role_in_event} />
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>
            </div>
          </section>
        <% end %>

        <!-- Historial de colaboraciones -->
        <%= if @past_events != [] do %>
          <section class="py-16 sm:py-20 bg-base-200">
            <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
              <div class="text-center mb-10">
                <span class="inline-block bg-base-300 text-base-content/60 font-semibold text-xs uppercase tracking-widest px-3 py-1 rounded-full mb-3">
                  Archivo
                </span>
                <h2 class="text-2xl sm:text-3xl font-bold text-base-content">
                  Historial de colaboraciones
                </h2>
              </div>

              <div class="max-w-2xl mx-auto space-y-4">
                <%= for event <- @past_events do %>
                  <div class="bg-base-100 border border-base-300 rounded-xl p-5 opacity-80 hover:opacity-100 transition-opacity">
                    <div class="flex flex-wrap items-center gap-2 mb-2">
                      <span class="text-sm font-medium text-base-content/70">
                        {format_event_date(event.event_date)}
                      </span>
                      <span class="text-xs text-base-content/40">
                        {format_time(event.start_time)} – {format_time(event.end_time)}
                      </span>
                      <%= if event.event_type do %>
                        <span class="badge badge-xs badge-ghost">{event.event_type.name}</span>
                      <% end %>
                    </div>

                    <h3 class="text-base font-bold text-base-content mb-2">{event.title}</h3>

                    <%= if event.event_collaborators != [] do %>
                      <div class="flex flex-wrap gap-1.5 mt-3">
                        <%= for ec <- event.event_collaborators do %>
                          <.collaborator_badge collaborator={ec.collaborator} role={ec.role_in_event} small={true} />
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>
            </div>
          </section>
        <% end %>

        <!-- CTA: propón tu colaboración -->
        <section class="py-16 sm:py-20 bg-base-100">
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
                href="https://wa.me/525530418611?text=Hola%2C%20me%20gustaría%20proponer%20una%20colaboración%20con%20Café%20Raíces%20y%20Cultura"
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

  # ── Collaborator badge component ──────────────────────────────────────────────

  attr :collaborator, :map, required: true
  attr :role, :string, default: nil
  attr :small, :boolean, default: false

  defp collaborator_badge(assigns) do
    ~H"""
    <span class={["inline-flex items-center gap-1 rounded-full px-2.5 py-1 bg-base-300 text-base-content", if(@small, do: "text-xs", else: "text-sm")]}>
      <%= if @collaborator.instagram_handle do %>
        <a
          href={"https://instagram.com/#{@collaborator.instagram_handle}"}
          target="_blank"
          rel="noopener noreferrer"
          class="font-medium hover:text-accent transition-colors"
        >
          {@collaborator.name}
        </a>
        <svg class="w-3 h-3 opacity-60" viewBox="0 0 24 24" fill="currentColor">
          <path d="M12 2.163c3.204 0 3.584.012 4.85.07 3.252.148 4.771 1.691 4.919 4.919.058 1.265.069 1.645.069 4.849 0 3.205-.012 3.584-.069 4.849-.149 3.225-1.664 4.771-4.919 4.919-1.266.058-1.644.07-4.85.07-3.204 0-3.584-.012-4.849-.07-3.26-.149-4.771-1.699-4.919-4.92-.058-1.265-.07-1.644-.07-4.849 0-3.204.013-3.583.07-4.849.149-3.227 1.664-4.771 4.919-4.919 1.266-.057 1.645-.069 4.849-.069zm0-2.163c-3.259 0-3.667.014-4.947.072-4.358.2-6.78 2.618-6.98 6.98-.059 1.281-.073 1.689-.073 4.948 0 3.259.014 3.668.072 4.948.2 4.358 2.618 6.78 6.98 6.98 1.281.058 1.689.072 4.948.072 3.259 0 3.668-.014 4.948-.072 4.354-.2 6.782-2.618 6.979-6.98.059-1.28.073-1.689.073-4.948 0-3.259-.014-3.667-.072-4.947-.196-4.354-2.617-6.78-6.979-6.98-1.281-.059-1.69-.073-4.949-.073zm0 5.838c-3.403 0-6.162 2.759-6.162 6.162s2.759 6.163 6.162 6.163 6.162-2.759 6.162-6.163c0-3.403-2.759-6.162-6.162-6.162zm0 10.162c-2.209 0-4-1.79-4-4 0-2.209 1.791-4 4-4s4 1.791 4 4c0 2.21-1.791 4-4 4zm6.406-11.845c-.796 0-1.441.645-1.441 1.44s.645 1.44 1.441 1.44c.795 0 1.439-.645 1.439-1.44s-.644-1.44-1.439-1.44z"/>
        </svg>
      <% else %>
        <span class="font-medium">{@collaborator.name}</span>
      <% end %>
      <%= if @role && @role != "" do %>
        <span class="opacity-60">· {@role}</span>
      <% end %>
    </span>
    """
  end

  # ── Private helpers ───────────────────────────────────────────────────────────

  defp load_events(socket) do
    socket
    |> assign(:current_event, Events.get_current_event())
    |> assign(:upcoming_events, Events.list_upcoming_events())
    |> assign(:past_events, Events.list_past_events())
  end

  # Formats a Date struct as "Viernes 20 de marzo" in Spanish.
  defp format_event_date(%Date{} = date) do
    weekday =
      case Date.day_of_week(date) do
        1 -> "Lunes"
        2 -> "Martes"
        3 -> "Miércoles"
        4 -> "Jueves"
        5 -> "Viernes"
        6 -> "Sábado"
        7 -> "Domingo"
      end

    month =
      case date.month do
        1 -> "enero"
        2 -> "febrero"
        3 -> "marzo"
        4 -> "abril"
        5 -> "mayo"
        6 -> "junio"
        7 -> "julio"
        8 -> "agosto"
        9 -> "septiembre"
        10 -> "octubre"
        11 -> "noviembre"
        12 -> "diciembre"
      end

    "#{weekday} #{date.day} de #{month}"
  end

  defp format_time(nil), do: "—"
  defp format_time(%Time{} = t), do: Calendar.strftime(t, "%H:%M")
end
