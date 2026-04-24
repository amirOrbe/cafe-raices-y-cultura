defmodule CRCWeb.ColaboracionesLive do
  @moduledoc """
  Public-facing collaborations page at /colaboraciones.

  Shows a monthly calendar of events. Clicking a day with events reveals
  the full event detail below the grid. Past days are visually muted.
  A "En vivo" banner appears when an event is happening right now.
  """

  use CRCWeb, :live_view

  alias CRC.Events
  alias CRCWeb.Components.SiteComponents

  # ---------------------------------------------------------------------------
  # Mount
  # ---------------------------------------------------------------------------

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(CRC.PubSub, "admin:events")
      :timer.send_interval(60_000, self(), :tick)
    end

    today = cdmx_today()

    socket =
      socket
      |> assign(:page_title, "Colaboraciones — Café Raíces y Cultura")
      |> assign(:nav_open, false)
      |> assign(:today, today)
      |> assign(:cal_year, today.year)
      |> assign(:cal_month, today.month)
      |> assign(:selected_date, nil)
      |> load_month_events()
      |> load_current_event()

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # Messages
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info(:tick, socket) do
    {:noreply,
     socket
     |> assign(:today, cdmx_today())
     |> load_current_event()
     |> load_month_events()}
  end

  def handle_info({:event_changed, _}, socket) do
    {:noreply, socket |> load_month_events() |> load_current_event()}
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("toggle_nav", _params, socket) do
    {:noreply, assign(socket, :nav_open, !socket.assigns.nav_open)}
  end

  def handle_event("close_nav", _params, socket) do
    {:noreply, assign(socket, :nav_open, false)}
  end

  def handle_event("prev_month", _params, socket) do
    {y, m} = prev_month(socket.assigns.cal_year, socket.assigns.cal_month)

    {:noreply,
     socket
     |> assign(cal_year: y, cal_month: m, selected_date: nil)
     |> load_month_events()}
  end

  def handle_event("next_month", _params, socket) do
    {y, m} = next_month(socket.assigns.cal_year, socket.assigns.cal_month)

    {:noreply,
     socket
     |> assign(cal_year: y, cal_month: m, selected_date: nil)
     |> load_month_events()}
  end

  def handle_event("select_day", %{"date" => date_str}, socket) do
    date = Date.from_iso8601!(date_str)
    # Toggle: clicking the same day again closes the detail panel
    selected = if socket.assigns.selected_date == date, do: nil, else: date
    {:noreply, assign(socket, :selected_date, selected)}
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex flex-col">
      <SiteComponents.site_navbar
        nav_open={@nav_open}
        current_page={:colaboraciones}
        current_user={@current_user}
      />
      <main class="flex-1 pt-16">

        <%!-- ── Hero ────────────────────────────────────────────────────── --%>
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

        <%!-- ── En vivo ──────────────────────────────────────────────────── --%>
        <%= if @current_event do %>
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

        <%!-- ── Calendario mensual ────────────────────────────────────────── --%>
        <section class="py-12 sm:py-16 bg-base-100">
          <div class="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8">

            <%!-- Header: title + month navigation --%>
            <div class="flex flex-wrap items-start justify-between gap-4 mb-8">
              <div>
                <span class="inline-block bg-accent/15 text-accent font-semibold text-xs uppercase tracking-widest px-3 py-1 rounded-full mb-2">
                  Agenda
                </span>
                <h2 class="text-2xl sm:text-3xl font-bold text-base-content">
                  Este mes en CRC
                </h2>
              </div>

              <div class="flex items-center gap-1">
                <button
                  phx-click="prev_month"
                  class="btn btn-ghost btn-sm btn-circle"
                  aria-label="Mes anterior"
                >
                  <.icon name="hero-chevron-left" class="size-4" />
                </button>
                <span class="text-sm font-semibold px-2 min-w-[140px] text-center select-none">
                  {month_name(@cal_month)} {@cal_year}
                </span>
                <button
                  phx-click="next_month"
                  class="btn btn-ghost btn-sm btn-circle"
                  aria-label="Mes siguiente"
                >
                  <.icon name="hero-chevron-right" class="size-4" />
                </button>
              </div>
            </div>

            <%!-- Calendar grid — flat grid-cols-7, browser wraps rows automatically --%>
            <div class="grid grid-cols-7 gap-px bg-base-300 rounded-2xl overflow-hidden border border-base-300">

              <%!-- Week day headers --%>
              <%= for abbr <- ~w(Do Lu Ma Mi Ju Vi Sá) do %>
                <div class="bg-base-200 text-center py-2 sm:py-3 text-[10px] sm:text-xs font-bold text-base-content/50 uppercase tracking-wide">
                  {abbr}
                </div>
              <% end %>

              <%!-- Day cells --%>
              <%= for cell <- @cal_cells do %>
                <%= if cell == :empty do %>
                  <div class="bg-base-100/50 min-h-[52px] sm:min-h-[80px]"></div>
                <% else %>
                  <% {date, day_events} = cell %>
                  <% past? = Date.compare(date, @today) == :lt %>
                  <% is_today? = date == @today %>
                  <% has_events? = day_events != [] %>
                  <% selected? = @selected_date == date %>

                  <div
                    class={[
                      "min-h-[52px] sm:min-h-[80px] p-1 sm:p-2 flex flex-col transition-colors",
                      if(has_events?, do: "cursor-pointer", else: ""),
                      cond do
                        selected? and past? -> "bg-base-200"
                        selected? -> "bg-accent/10"
                        past? -> "bg-base-100/70"
                        is_today? -> "bg-primary/5"
                        has_events? -> "bg-base-100 hover:bg-base-200/60"
                        true -> "bg-base-100"
                      end
                    ]}
                    phx-click={if has_events?, do: "select_day"}
                    phx-value-date={if has_events?, do: Date.to_iso8601(date)}
                  >
                    <%!-- Day number --%>
                    <div class="flex justify-end sm:justify-start">
                      <span class={[
                        "text-xs sm:text-sm font-semibold w-5 h-5 sm:w-6 sm:h-6 flex items-center justify-center rounded-full leading-none shrink-0",
                        cond do
                          is_today? -> "bg-primary text-primary-content font-bold"
                          selected? -> "text-accent font-bold"
                          past? -> "text-base-content/25"
                          true -> "text-base-content/70"
                        end
                      ]}>
                        {date.day}
                      </span>
                    </div>

                    <%!-- Events --%>
                    <%= if has_events? do %>
                      <%!-- Mobile: colored dots --%>
                      <div class="flex gap-0.5 justify-center mt-auto pb-0.5 sm:hidden">
                        <%= for _ev <- Enum.take(day_events, 3) do %>
                          <div class={[
                            "w-1.5 h-1.5 rounded-full shrink-0",
                            cond do
                              past? -> "bg-base-content/20"
                              is_today? -> "bg-accent"
                              true -> "bg-primary"
                            end
                          ]}></div>
                        <% end %>
                        <%= if length(day_events) > 3 do %>
                          <span class="text-[8px] leading-tight text-base-content/40 self-center">
                            +{length(day_events) - 3}
                          </span>
                        <% end %>
                      </div>

                      <%!-- Desktop: time + title pills --%>
                      <div class="hidden sm:flex flex-col gap-0.5 mt-1">
                        <%= for ev <- Enum.take(day_events, 2) do %>
                          <div class={[
                            "text-[10px] leading-snug rounded px-1 py-0.5 truncate font-medium",
                            cond do
                              past? -> "bg-base-300 text-base-content/35"
                              is_today? -> "bg-accent/20 text-accent"
                              true -> "bg-primary/15 text-primary"
                            end
                          ]}>
                            {format_time(ev.start_time)} · {ev.title}
                          </div>
                        <% end %>
                        <%= if length(day_events) > 2 do %>
                          <div class="text-[10px] text-base-content/35 pl-1">
                            +{length(day_events) - 2} más
                          </div>
                        <% end %>
                      </div>
                    <% end %>

                  </div>
                <% end %>
              <% end %>
            </div>

            <%!-- Empty month state --%>
            <%= if @cal_events == [] do %>
              <div class="mt-8 text-center py-12 text-base-content/40">
                <.icon name="hero-calendar" class="size-12 mx-auto mb-3 opacity-30" />
                <p class="font-medium">Sin eventos para este mes</p>
                <p class="text-sm mt-1">Navega a otro mes o vuelve pronto.</p>
              </div>
            <% end %>

            <%!-- Selected day detail panel --%>
            <%= if @selected_date do %>
              <% day_events = Map.get(@events_by_date, @selected_date, []) %>
              <%= if day_events != [] do %>
                <div id="day-detail" class="mt-8 scroll-mt-24">
                  <%!-- Panel header --%>
                  <div class="flex flex-wrap items-center gap-3 mb-5">
                    <h3 class="text-lg sm:text-xl font-bold text-base-content">
                      {format_full_date(@selected_date)}
                    </h3>
                    <%= if Date.compare(@selected_date, @today) == :lt do %>
                      <span class="badge badge-ghost badge-sm">Pasado</span>
                    <% end %>
                  </div>

                  <div class="space-y-4">
                    <%= for event <- day_events do %>
                      <% is_past_event? = Date.compare(@selected_date, @today) == :lt %>
                      <div class={[
                        "rounded-2xl border p-5 sm:p-6",
                        if(is_past_event?,
                          do: "border-base-300 bg-base-200/60 opacity-80",
                          else: "border-base-300 bg-base-200"
                        )
                      ]}>
                        <%!-- Type + time --%>
                        <div class="flex flex-wrap items-center gap-2 mb-3">
                          <%= if event.event_type do %>
                            <span class="badge badge-sm badge-ghost">{event.event_type.name}</span>
                          <% end %>
                          <span class="text-sm font-semibold text-accent">
                            {format_time(event.start_time)} – {format_time(event.end_time)}
                          </span>
                        </div>

                        <%!-- Title --%>
                        <h4 class="text-lg sm:text-xl font-bold text-base-content mb-2">
                          {event.title}
                        </h4>

                        <%!-- Description --%>
                        <%= if event.description do %>
                          <p class="text-sm sm:text-base text-base-content/60 leading-relaxed mb-4 break-words">
                            {event.description}
                          </p>
                        <% end %>

                        <%!-- Tags --%>
                        <%= if event.tags != [] do %>
                          <div class="flex flex-wrap gap-1.5 mb-4">
                            <span :for={tag <- event.tags} class="badge badge-ghost text-xs">
                              {tag}
                            </span>
                          </div>
                        <% end %>

                        <%!-- Collaborators --%>
                        <%= if event.event_collaborators != [] do %>
                          <div class={[
                            "flex flex-wrap gap-2 pt-3",
                            if(event.event_photos != [], do: "", else: "border-t border-base-300")
                          ]}>
                            <%= for ec <- event.event_collaborators do %>
                              <.collaborator_badge
                                collaborator={ec.collaborator}
                                role={ec.role_in_event}
                              />
                            <% end %>
                          </div>
                        <% end %>

                        <%!-- Photo carousel --%>
                        <%= if event.event_photos != [] do %>
                          <div class="pt-4 border-t border-base-300 mt-3">
                            <p class="text-xs font-semibold text-base-content/40 uppercase tracking-wider mb-3">
                              Galería
                              <span class="font-normal normal-case">
                                · {length(event.event_photos)} {if length(event.event_photos) == 1, do: "foto", else: "fotos"}
                              </span>
                            </p>
                            <div class="carousel carousel-center gap-2 w-full">
                              <%= for photo <- event.event_photos do %>
                                <div class="carousel-item">
                                  <a
                                    href={photo.image_url}
                                    target="_blank"
                                    rel="noopener noreferrer"
                                    class="block overflow-hidden rounded-xl group"
                                  >
                                    <img
                                      src={photo.image_url}
                                      alt={photo.caption || event.title}
                                      class="h-44 w-44 object-cover rounded-xl group-hover:scale-105 transition-transform duration-300"
                                      loading="lazy"
                                    />
                                  </a>
                                </div>
                              <% end %>
                            </div>
                          </div>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                </div>
              <% end %>
            <% end %>

          </div>
        </section>

        <%!-- ── CTA ─────────────────────────────────────────────────────── --%>
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
                href="https://wa.me/525530418611?text=Hola%2C%20me%20gustaría%20proponer%20una%20colaboración%20con%20Café%20Raíces%20y%20Cultura"
                target="_blank"
                rel="noopener noreferrer"
                class="btn btn-lg bg-white text-primary border-0 hover:bg-white/90 gap-2 shadow-md"
              >
                <svg class="h-5 w-5" viewBox="0 0 24 24" fill="currentColor">
                  <path d="M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347m-5.421 7.403h-.004a9.87 9.87 0 01-5.031-1.378l-.361-.214-3.741.982.998-3.648-.235-.374a9.86 9.86 0 01-1.51-5.26c.001-5.45 4.436-9.884 9.888-9.884 2.64 0 5.122 1.03 6.988 2.898a9.825 9.825 0 012.893 6.994c-.003 5.45-4.437 9.884-9.885 9.884m8.413-18.297A11.815 11.815 0 0012.05 0C5.495 0 .16 5.335.157 11.892c0 2.096.547 4.142 1.588 5.945L.057 24l6.305-1.654a11.882 11.882 0 005.683 1.448h.005c6.554 0 11.89-5.335 11.893-11.893a11.821 11.821 0 00-3.48-8.413z" />
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

  # ---------------------------------------------------------------------------
  # Collaborator badge component (reused from before)
  # ---------------------------------------------------------------------------

  attr :collaborator, :map, required: true
  attr :role, :string, default: nil
  attr :small, :boolean, default: false

  defp collaborator_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center gap-1 rounded-full px-2.5 py-1 bg-base-300 text-base-content",
      if(@small, do: "text-xs", else: "text-sm")
    ]}>
      <%= if @collaborator.instagram_handle do %>
        <a
          href={"https://instagram.com/#{@collaborator.instagram_handle}"}
          target="_blank"
          rel="noopener noreferrer"
          class="font-medium hover:text-accent transition-colors"
        >
          {@collaborator.name}
        </a>
        <svg class="w-3 h-3 opacity-60 shrink-0" viewBox="0 0 24 24" fill="currentColor">
          <path d="M12 2.163c3.204 0 3.584.012 4.85.07 3.252.148 4.771 1.691 4.919 4.919.058 1.265.069 1.645.069 4.849 0 3.205-.012 3.584-.069 4.849-.149 3.225-1.664 4.771-4.919 4.919-1.266.058-1.644.07-4.85.07-3.204 0-3.584-.012-4.849-.07-3.26-.149-4.771-1.699-4.919-4.92-.058-1.265-.07-1.644-.07-4.849 0-3.204.013-3.583.07-4.849.149-3.227 1.664-4.771 4.919-4.919 1.266-.057 1.645-.069 4.849-.069zm0-2.163c-3.259 0-3.667.014-4.947.072-4.358.2-6.78 2.618-6.98 6.98-.059 1.281-.073 1.689-.073 4.948 0 3.259.014 3.668.072 4.948.2 4.358 2.618 6.78 6.98 6.98 1.281.058 1.689.072 4.948.072 3.259 0 3.668-.014 4.948-.072 4.354-.2 6.782-2.618 6.979-6.98.059-1.28.073-1.689.073-4.948 0-3.259-.014-3.667-.072-4.947-.196-4.354-2.617-6.78-6.979-6.98-1.281-.059-1.69-.073-4.949-.073zm0 5.838c-3.403 0-6.162 2.759-6.162 6.162s2.759 6.163 6.162 6.163 6.162-2.759 6.162-6.163c0-3.403-2.759-6.162-6.162-6.162zm0 10.162c-2.209 0-4-1.79-4-4 0-2.209 1.791-4 4-4s4 1.791 4 4c0 2.21-1.791 4-4 4zm6.406-11.845c-.796 0-1.441.645-1.441 1.44s.645 1.44 1.441 1.44c.795 0 1.439-.645 1.439-1.44s-.644-1.44-1.439-1.44z" />
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

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp load_month_events(socket) do
    year = socket.assigns.cal_year
    month = socket.assigns.cal_month
    events = Events.list_events_for_month(year, month)
    by_date = Enum.group_by(events, & &1.event_date)
    cells = build_calendar_cells(year, month, by_date)

    socket
    |> assign(:cal_events, events)
    |> assign(:events_by_date, by_date)
    |> assign(:cal_cells, cells)
  end

  defp load_current_event(socket) do
    assign(socket, :current_event, Events.get_current_event())
  end

  # Builds a flat list of :empty | {date, [events]} covering the full calendar
  # grid (including leading/trailing padding cells to align to a Sun–Sat week).
  defp build_calendar_cells(year, month, by_date) do
    first = Date.new!(year, month, 1)
    total_days = Date.days_in_month(first)
    # ISO day_of_week: 1=Mon … 7=Sun. We want Sun=0, Mon=1 … Sat=6.
    offset = rem(Date.day_of_week(first), 7)

    day_cells =
      Enum.map(1..total_days, fn d ->
        date = Date.new!(year, month, d)
        {date, Map.get(by_date, date, [])}
      end)

    all_cells = List.duplicate(:empty, offset) ++ day_cells

    # Pad the last row to a complete week
    remainder = rem(length(all_cells), 7)
    if remainder > 0,
      do: all_cells ++ List.duplicate(:empty, 7 - remainder),
      else: all_cells
  end

  defp prev_month(year, 1), do: {year - 1, 12}
  defp prev_month(year, month), do: {year, month - 1}

  defp next_month(year, 12), do: {year + 1, 1}
  defp next_month(year, month), do: {year, month + 1}

  defp cdmx_today do
    DateTime.utc_now()
    |> DateTime.add(-6 * 3600, :second)
    |> DateTime.to_date()
  end

  defp format_time(nil), do: "—"
  defp format_time(%Time{} = t), do: Calendar.strftime(t, "%H:%M")

  defp format_full_date(%Date{} = date) do
    "#{day_name(Date.day_of_week(date))} #{date.day} de #{month_name_lower(date.month)} de #{date.year}"
  end

  defp day_name(1), do: "Lunes"
  defp day_name(2), do: "Martes"
  defp day_name(3), do: "Miércoles"
  defp day_name(4), do: "Jueves"
  defp day_name(5), do: "Viernes"
  defp day_name(6), do: "Sábado"
  defp day_name(7), do: "Domingo"

  defp month_name(1), do: "Enero"
  defp month_name(2), do: "Febrero"
  defp month_name(3), do: "Marzo"
  defp month_name(4), do: "Abril"
  defp month_name(5), do: "Mayo"
  defp month_name(6), do: "Junio"
  defp month_name(7), do: "Julio"
  defp month_name(8), do: "Agosto"
  defp month_name(9), do: "Septiembre"
  defp month_name(10), do: "Octubre"
  defp month_name(11), do: "Noviembre"
  defp month_name(12), do: "Diciembre"

  defp month_name_lower(n), do: n |> month_name() |> String.downcase()
end
