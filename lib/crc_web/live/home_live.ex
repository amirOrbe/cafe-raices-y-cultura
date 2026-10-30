defmodule CRCWeb.HomeLive do
  @moduledoc "Single-page home LiveView for Café Raíces y Cultura."

  use CRCWeb, :live_view

  alias CRCWeb.Components.SiteComponents
  alias CRC.Catalog
  alias CRC.Events
  alias CRC.Settings

  # How many upcoming events the home teaser shows before pointing to /colaboraciones
  @max_home_events 3

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(CRC.PubSub, "admin:events")

    # Carousel always uses local photos shuffled randomly — every visit shows a different order
    photos = carousel_photos() |> Enum.shuffle()
    packages = Catalog.list_packages()
    cafe_hours = Settings.grouped_hours()

    socket =
      socket
      |> assign(:page_title, "Café Raíces y Cultura")
      |> assign(:photos, photos)
      |> assign(:active_slide, 0)
      |> assign(:autoplay, true)
      |> assign(:nav_open, false)
      |> assign(:packages, packages)
      |> assign(:cafe_hours, cafe_hours)
      |> load_upcoming_events()

    {:ok, socket}
  end

  @impl true
  def handle_info({:event_changed, _}, socket) do
    {:noreply, load_upcoming_events(socket)}
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

  def handle_event("toggle_autoplay", _params, socket) do
    {:noreply, assign(socket, :autoplay, !socket.assigns.autoplay)}
  end

  # Sent by the hook when the visitor prefers reduced motion
  def handle_event("disable_autoplay", _params, socket) do
    {:noreply, assign(socket, :autoplay, false)}
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
      <SiteComponents.site_navbar
        nav_open={@nav_open}
        current_page={:home}
        current_user={@current_user}
      />
      <main class="flex-1">
        <.hero_section photos={@photos} active_slide={@active_slide} autoplay={@autoplay} />
        <.events_section
          :if={@upcoming_events != []}
          events={@upcoming_events}
          more_count={@more_events_count}
          now={@cdmx_now}
        />
        <.about_section cafe_hours={@cafe_hours} />
        <.packages_section :if={@packages != []} packages={@packages} />
        <.contact_section cafe_hours={@cafe_hours} />
      </main>
      <SiteComponents.site_footer />
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Static photo data
  # ---------------------------------------------------------------------------

  # All 19 real CRC photos — shuffled on every mount so each visit looks different
  defp format_time(%Time{} = t), do: Calendar.strftime(t, "%H:%M")

  defp carousel_photos do
    [
      %{url: "/images/carousel/crc-01", caption: "Café Raíces y Cultura"},
      %{url: "/images/carousel/crc-02", caption: "Un espacio para conectar"},
      %{url: "/images/carousel/crc-03", caption: "Café de origen seleccionado"},
      %{url: "/images/carousel/crc-04", caption: "Arte y sabor en cada taza"},
      %{url: "/images/carousel/crc-05", caption: "Tu refugio en Santa María la Ribera"},
      %{url: "/images/carousel/crc-06", caption: "Café Raíces y Cultura"},
      %{url: "/images/carousel/crc-07", caption: "Hecho con amor y detalle"},
      %{url: "/images/carousel/crc-08", caption: "Raíces que nos sostienen"},
      %{url: "/images/carousel/crc-09", caption: "Cultura que inspira"},
      %{url: "/images/carousel/crc-10", caption: "Un proyecto familiar"},
      %{url: "/images/carousel/crc-11", caption: "Granos de origen seleccionado"},
      %{url: "/images/carousel/crc-12", caption: "Santa María la Ribera · CDMX"},
      %{url: "/images/carousel/crc-13", caption: "Café Raíces y Cultura"},
      %{url: "/images/carousel/crc-14", caption: "Cada taza, una historia"},
      %{url: "/images/carousel/crc-15", caption: "Bienvenidos a CRC"},
      %{url: "/images/carousel/crc-16", caption: "Arte, café y cultura"},
      %{url: "/images/carousel/crc-17", caption: "Compromiso con la comunidad"},
      %{url: "/images/carousel/crc-18", caption: "Lo artesanal en cada detalle"},
      %{url: "/images/carousel/crc-19", caption: "Ven y descúbrenos"}
    ]
  end

  # ---------------------------------------------------------------------------
  # Hero / Carousel section
  # ---------------------------------------------------------------------------

  defp hero_section(%{photos: []} = assigns) do
    ~H"""
    <section
      id="inicio"
      class="relative pt-16 h-64 sm:h-80 md:h-[500px] lg:h-[600px] bg-primary flex items-center justify-center"
    >
      <div class="text-center text-primary-content px-4">
        <h1 class="text-3xl sm:text-5xl font-bold mb-4">Café Raíces y Cultura</h1>
        <p class="text-lg sm:text-xl opacity-90">Santa María la Ribera · CDMX</p>
      </div>
    </section>
    """
  end

  defp hero_section(assigns) do
    total = length(assigns.photos)
    assigns = assign(assigns, :total, total)

    ~H"""
    <section
      id="inicio"
      class="relative pt-16 h-80 md:h-[500px] lg:h-[600px] overflow-hidden"
      phx-hook="CarouselAutoplay"
      data-autoplay={to_string(@autoplay)}
      aria-roledescription="carrusel"
      aria-label="Fotos de Café Raíces y Cultura"
    >
      <!-- Slides: only the active photo and its neighbours carry an image, so the
           browser downloads 3 photos instead of all 19 -->
      <div class="relative w-full h-full" aria-live={if @autoplay, do: "off", else: "polite"}>
        <%= for {photo, index} <- Enum.with_index(@photos) do %>
          <div
            class={"absolute inset-0 transition-opacity duration-700 motion-reduce:transition-none #{if index == @active_slide, do: "opacity-100 z-10", else: "opacity-0 z-0"}"}
            aria-hidden={to_string(index != @active_slide)}
          >
            <img
              :if={near_slide?(index, @active_slide, @total)}
              src={photo.url <> ".webp"}
              srcset={"#{photo.url}-800.webp 800w, #{photo.url}.webp 1400w"}
              sizes="100vw"
              alt={photo.caption || "Café Raíces y Cultura"}
              class="w-full h-full object-cover"
              fetchpriority={if index == @active_slide, do: "high", else: "low"}
            />
            <div class="absolute inset-0 bg-gradient-to-t from-black/60 via-black/10 to-transparent">
            </div>
            <div
              :if={photo.caption}
              class="hidden sm:block absolute bottom-16 left-0 right-0 text-center px-4"
            >
              <p class="text-white text-base sm:text-lg md:text-2xl font-medium drop-shadow-lg">
                {photo.caption}
              </p>
            </div>
          </div>
        <% end %>
      </div>

      <!-- Previous arrow -->
      <button
        phx-click="carousel_prev"
        class="absolute left-3 sm:left-6 top-1/2 -translate-y-1/2 z-20 bg-black/40 hover:bg-black/60 text-white rounded-full size-11 sm:size-12 flex items-center justify-center transition-colors"
        aria-label="Foto anterior"
      >
        <.icon name="hero-chevron-left" class="size-5 sm:size-6" />
      </button>

      <!-- Next arrow -->
      <button
        phx-click="carousel_next"
        class="absolute right-3 sm:right-6 top-1/2 -translate-y-1/2 z-20 bg-black/40 hover:bg-black/60 text-white rounded-full size-11 sm:size-12 flex items-center justify-center transition-colors"
        aria-label="Foto siguiente"
      >
        <.icon name="hero-chevron-right" class="size-5 sm:size-6" />
      </button>

      <!-- Controls: pause + position. 19 dots don't fit a phone, so phones get a counter -->
      <div class="absolute bottom-3 left-0 right-0 z-20 flex items-center justify-center gap-2 px-4">
        <button
          phx-click="toggle_autoplay"
          class="size-8 shrink-0 rounded-full bg-black/40 hover:bg-black/60 text-white flex items-center justify-center transition-colors"
          aria-label={if @autoplay, do: "Pausar fotos", else: "Reanudar fotos"}
          aria-pressed={to_string(!@autoplay)}
        >
          <.icon name={if @autoplay, do: "hero-pause-solid", else: "hero-play-solid"} class="size-4" />
        </button>
        <span class="sm:hidden text-xs font-medium text-white bg-black/40 rounded-full px-3 py-1.5 tabular-nums">
          {@active_slide + 1} / {@total}
        </span>
        <div class="hidden sm:flex items-center">
          <%= for {_photo, index} <- Enum.with_index(@photos) do %>
            <button
              phx-click="carousel_goto"
              phx-value-index={index}
              class="group size-6 flex items-center justify-center"
              aria-label={"Ir a la foto #{index + 1}"}
              aria-current={if index == @active_slide, do: "true"}
            >
              <span class={"block rounded-full transition-all motion-reduce:transition-none #{if index == @active_slide, do: "w-5 h-2.5 bg-white", else: "size-2.5 bg-white/60 group-hover:bg-white/90"}"} />
            </button>
          <% end %>
        </div>
      </div>

      <!-- Headline overlay -->
      <div class="absolute inset-x-0 top-1/2 -translate-y-1/2 z-20 text-center px-16 sm:px-20 pointer-events-none">
        <h1 class="text-3xl sm:text-4xl md:text-5xl lg:text-6xl font-bold text-white drop-shadow-xl leading-tight text-balance">
          Café Raíces y Cultura
        </h1>
        <p class="mt-2 text-sm sm:text-base md:text-lg text-white drop-shadow">
          Santa María la Ribera ·
          <span class="sm:hidden">CDMX</span><span class="hidden sm:inline">Ciudad de México</span>
        </p>
      </div>
    </section>
    """
  end

  defp near_slide?(index, active, total) do
    diff = abs(index - active)
    diff <= 1 or diff == total - 1
  end

  # ---------------------------------------------------------------------------
  # Upcoming events teaser
  # ---------------------------------------------------------------------------

  attr :events, :list, required: true
  attr :more_count, :integer, default: 0
  attr :now, NaiveDateTime, required: true

  defp events_section(assigns) do
    ~H"""
    <section id="eventos" class="py-12 sm:py-16 bg-base-200 border-b border-base-300">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="flex flex-col sm:flex-row sm:items-end sm:justify-between gap-3 mb-8">
          <div>
            <p class="text-sm font-semibold text-secondary uppercase tracking-wider">
              Agenda cultural
            </p>
            <h2 class="text-2xl sm:text-3xl font-bold text-base-content leading-tight mt-1">
              {events_heading(@events, @now)}
            </h2>
          </div>
          <.link
            href={~p"/colaboraciones"}
            class="hidden sm:inline-flex items-center gap-1.5 text-primary font-semibold hover:underline"
          >
            Ver calendario completo <.icon name="hero-arrow-right" class="size-4" />
          </.link>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-3 gap-4 sm:gap-6">
          <.link
            :for={event <- @events}
            href={"/colaboraciones?fecha=#{Date.to_iso8601(event.event_date)}#day-detail"}
            class="group bg-base-100 rounded-2xl border border-base-300 hover:border-primary/40 shadow-sm hover:shadow-md transition-all p-5 flex gap-4"
          >
            <div class="shrink-0 w-14 rounded-xl bg-primary/10 text-primary flex flex-col items-center justify-center py-2 self-start">
              <span class="text-[11px] font-semibold uppercase tracking-wide">
                {month_abbr(event.event_date.month)}
              </span>
              <span class="text-2xl font-bold leading-none tabular-nums">
                {event.event_date.day}
              </span>
            </div>
            <div class="min-w-0 flex-1">
              <div class="flex flex-wrap items-center gap-2 mb-1.5">
                <%= if live_now?(event, @now) do %>
                  <span class="inline-flex items-center gap-1 bg-success text-success-content font-bold text-[11px] uppercase tracking-wider px-2 py-0.5 rounded-full">
                    <span class="size-1.5 rounded-full bg-success-content motion-safe:animate-pulse"></span>
                    En vivo
                  </span>
                <% else %>
                  <span class="text-xs font-semibold text-secondary">
                    {day_label(event.event_date, NaiveDateTime.to_date(@now))}
                  </span>
                <% end %>
                <span :if={event.event_type} class="badge badge-sm badge-ghost">
                  {event.event_type.name}
                </span>
              </div>
              <h3 class="font-bold text-base-content leading-snug group-hover:text-primary transition-colors break-words">
                {event.title}
              </h3>
              <p class="text-sm text-base-content/70 mt-1 tabular-nums">
                {format_time(event.start_time)} – {format_time(event.end_time)}
              </p>
            </div>
          </.link>
        </div>

        <div class="mt-6 flex flex-col sm:flex-row sm:items-center gap-3 text-sm">
          <p :if={@more_count > 0} class="text-base-content/70">
            {if @more_count == 1,
              do: "Y 1 evento más en los próximos días.",
              else: "Y #{@more_count} eventos más en los próximos días."}
          </p>
          <.link
            href={~p"/colaboraciones"}
            class="sm:hidden btn btn-primary btn-sm w-full"
          >
            Ver calendario completo
          </.link>
        </div>
      </div>
    </section>
    """
  end

  defp events_heading(events, now) do
    today = NaiveDateTime.to_date(now)

    if Enum.any?(events, &(&1.event_date == today)),
      do: "Hoy en Café Raíces y Cultura",
      else: "Próximos eventos"
  end

  defp live_now?(event, now) do
    event.event_date == NaiveDateTime.to_date(now) and
      Time.compare(event.start_time, NaiveDateTime.to_time(now)) != :gt and
      Time.compare(event.end_time, NaiveDateTime.to_time(now)) == :gt
  end

  defp day_label(date, today) do
    case Date.diff(date, today) do
      0 -> "Hoy"
      1 -> "Mañana"
      _ -> "#{weekday_name(Date.day_of_week(date))} #{date.day}"
    end
  end

  defp weekday_name(n),
    do: Enum.at(~w(Lunes Martes Miércoles Jueves Viernes Sábado Domingo), n - 1)

  defp month_abbr(n),
    do: Enum.at(~w(Ene Feb Mar Abr May Jun Jul Ago Sep Oct Nov Dic), n - 1)

  defp load_upcoming_events(socket) do
    events = Events.list_upcoming_events()

    socket
    |> assign(:upcoming_events, Enum.take(events, @max_home_events))
    |> assign(:more_events_count, max(length(events) - @max_home_events, 0))
    |> assign(:cdmx_now, cdmx_now())
  end

  defp cdmx_now do
    DateTime.utc_now()
    |> DateTime.add(-6 * 3600, :second)
    |> DateTime.to_naive()
  end

  # ---------------------------------------------------------------------------
  # About section
  # ---------------------------------------------------------------------------

  attr :cafe_hours, :list, default: []

  defp about_section(assigns) do
    ~H"""
    <section id="nosotros" class="py-16 sm:py-20 lg:py-24 bg-base-100">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <!-- Header -->
        <div class="text-center mb-12 sm:mb-16">
          <h2 class="text-3xl sm:text-4xl font-bold text-base-content leading-tight">
            Un espacio para conectar
          </h2>
        </div>

        <!-- Intro + imagen -->
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-10 lg:gap-16 items-center mb-16 sm:mb-20">
          <!-- Imagen -->
          <div class="relative rounded-2xl overflow-hidden shadow-xl aspect-[4/3]">
            <img
              src="/images/carousel/crc-17-800.webp"
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
            <div class={[
              "grid gap-4",
              if(length(@cafe_hours) >= 2, do: "grid-cols-2", else: "grid-cols-1")
            ]}>
              <%= if @cafe_hours == [] do %>
                <div class="bg-base-200 rounded-xl p-4 text-center">
                  <p class="text-xl font-bold text-primary">Lun – Vie</p>
                  <p class="text-sm text-base-content/70 mt-1">8:00 – 21:00</p>
                </div>
              <% else %>
                <%= for group <- @cafe_hours do %>
                  <div class="bg-base-200 rounded-xl p-4 text-center">
                    <p class="text-xl font-bold text-primary">{group.label}</p>
                    <p class="text-sm text-base-content/70 mt-1">
                      {format_time(group.opening)} – {format_time(group.closing)}
                    </p>
                  </div>
                <% end %>
              <% end %>
            </div>
          </div>
        </div>

        <!-- 4 pilares -->
        <div class="grid grid-cols-1 md:grid-cols-2 gap-x-12 gap-y-10 max-w-5xl mx-auto mb-16">
          <div class="border-t-2 border-primary/25 pt-5">
            <h3 class="flex items-center gap-2.5 text-lg font-bold text-base-content mb-2">
              <.icon name="hero-sparkles" class="size-5 text-primary shrink-0" /> Raíces que Sostienen
            </h3>
            <p class="text-base-content/70 leading-relaxed text-pretty">
              Nuestras raíces son profundas, nutridas por la historia y el esfuerzo de quienes
              han guiado este camino. Son el ADN que nos sostiene y nos conecta con el pasado
              para guiarnos hacia el futuro.
            </p>
          </div>
          <div class="border-t-2 border-primary/25 pt-5">
            <h3 class="flex items-center gap-2.5 text-lg font-bold text-base-content mb-2">
              <.icon name="hero-light-bulb" class="size-5 text-primary shrink-0" />
              Cultura que Inspira
            </h3>
            <p class="text-base-content/70 leading-relaxed text-pretty">
              Más que una cafetería, somos un espacio cultural vibrante. Promovemos actividades
              artísticas que unen a las personas y generan un impacto positivo. Somos un faro
              de colaboración y creatividad.
            </p>
          </div>
          <div class="border-t-2 border-primary/25 pt-5">
            <h3 class="flex items-center gap-2.5 text-lg font-bold text-base-content mb-2">
              <.icon name="hero-user-group" class="size-5 text-primary shrink-0" />
              Compromiso con la Comunidad
            </h3>
            <p class="text-base-content/70 leading-relaxed text-pretty">
              Creemos en la trazabilidad del café, mostrando el impacto de quienes lo producen.
              Nuestra visión es fomentar comunidades comprometidas que trabajen juntas para
              mejorar el ámbito cafetalero.
            </p>
          </div>
          <div class="border-t-2 border-primary/25 pt-5">
            <h3 class="flex items-center gap-2.5 text-lg font-bold text-base-content mb-2">
              <.icon name="hero-heart" class="size-5 text-primary shrink-0" /> Valores que Nos Definen
            </h3>
            <p class="text-base-content/70 leading-relaxed text-pretty">
              Empatía, respeto, colaboración e integridad son el pilar de cada acción. Promovemos
              el trabajo en equipo, la responsabilidad social y la conciencia del entorno con
              perseverancia y resiliencia.
            </p>
          </div>
        </div>

        <!-- Cierre -->
        <div class="text-center max-w-2xl mx-auto">
          <p class="text-base-content/70 text-base sm:text-lg leading-relaxed">
            En CRC somos personas cálidas y versátiles, siempre en busca de nuevos horizontes.
            Ven y descubre un espacio donde el <strong class="text-base-content">café</strong>,
            el <strong class="text-base-content">arte</strong>
            y la <strong class="text-base-content">cultura</strong>
            convergen para nutrir y transformar nuestro entorno.
          </p>
          <p class="mt-4 text-primary font-semibold text-balance">
            ¡Te esperamos en Café Raíces y Cultura para compartir una experiencia única y auténtica!
          </p>
        </div>
      </div>
    </section>
    """
  end

  # ---------------------------------------------------------------------------
  # Packages section
  # ---------------------------------------------------------------------------

  defp packages_section(assigns) do
    ~H"""
    <section id="paquetes" class="py-16 sm:py-20 lg:py-24 bg-base-200">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="text-center mb-12">
          <h2 class="text-3xl sm:text-4xl font-bold text-base-content leading-tight">
            Paquetes del día
          </h2>
          <p class="mt-3 text-base-content/70 max-w-xl mx-auto">
            Lleva más por menos. Combinaciones pensadas para que disfrutes al máximo.
          </p>
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">
          <%= for package <- @packages do %>
            <div class="bg-base-100 rounded-2xl border border-primary/20 shadow-sm overflow-hidden flex flex-col hover:shadow-md transition-shadow">
              <%!-- Header --%>
              <div class="bg-primary/10 px-5 py-4 border-b border-primary/15">
                <div class="flex items-start justify-between gap-3">
                  <h3 class="font-bold text-base-content text-lg leading-snug">{package.name}</h3>
                  <span class="badge badge-primary badge-sm whitespace-nowrap shrink-0">Combo</span>
                </div>
                <%= if package.description do %>
                  <p class="text-sm text-base-content/70 mt-1">{package.description}</p>
                <% end %>
              </div>

              <%!-- Items included --%>
              <div class="flex-1 px-5 py-4">
                <p class="text-xs font-semibold text-base-content/65 uppercase tracking-wider mb-3">
                  Incluye:
                </p>
                <ul class="space-y-2">
                  <%= for pi <- package.package_items do %>
                    <li class="flex items-center gap-2 text-sm text-base-content">
                      <span class="w-5 h-5 rounded-full bg-primary/10 flex items-center justify-center shrink-0">
                        <.icon name="hero-check" class="size-3 text-primary" />
                      </span>
                      <%= if pi.quantity > 1 do %>
                        <span class="font-semibold text-primary">{pi.quantity}×</span>
                      <% end %>
                      {pi.menu_item.name}
                    </li>
                  <% end %>
                </ul>
              </div>

              <%!-- Price --%>
              <div class="px-5 py-4 border-t border-base-200 flex items-center justify-between">
                <div>
                  <% individual_total =
                    Enum.reduce(package.package_items, Decimal.new(0), fn pi, acc ->
                      Decimal.add(acc, Decimal.mult(pi.menu_item.price, pi.quantity))
                    end) %>
                  <%= if Decimal.compare(individual_total, package.price) == :gt do %>
                    <p class="text-xs text-base-content/65 line-through">
                      ${individual_total |> Decimal.round(0) |> Decimal.to_string()}
                    </p>
                  <% end %>
                  <p class="text-2xl font-bold text-primary">
                    ${package.price |> Decimal.round(0) |> Decimal.to_string()}
                  </p>
                </div>
                <%= if Decimal.compare(individual_total, package.price) == :gt do %>
                  <% savings = Decimal.sub(individual_total, package.price) |> Decimal.round(0) %>
                  <span class="badge badge-success badge-lg">
                    Ahorras ${Decimal.to_string(savings)}
                  </span>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </section>
    """
  end

  # ---------------------------------------------------------------------------
  # Contact / Social / Map section
  # ---------------------------------------------------------------------------

  attr :cafe_hours, :list, default: []

  defp contact_section(assigns) do
    ~H"""
    <section id="contacto" class="py-16 sm:py-20 lg:py-24 bg-base-200">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="text-center mb-10 sm:mb-14">
          <h2 class="text-3xl sm:text-4xl font-bold text-base-content">Visítanos</h2>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-10 lg:gap-16 items-start">
          <!-- Contact info + Social -->
          <div class="space-y-8">
            <!-- Dirección -->
            <div class="flex gap-4">
              <div class="w-10 h-10 bg-primary/10 rounded-xl flex items-center justify-center flex-shrink-0 mt-0.5">
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  class="h-5 w-5 text-primary"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke="currentColor"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z"
                  />
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M15 11a3 3 0 11-6 0 3 3 0 016 0z"
                  />
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
                  Dr. Mariano Azuela #80 Local A<br /> Col. Santa María la Ribera, CDMX 06400
                </a>
              </div>
            </div>

            <!-- Horario -->
            <div class="flex gap-4">
              <div class="w-10 h-10 bg-primary/10 rounded-xl flex items-center justify-center flex-shrink-0 mt-0.5">
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  class="h-5 w-5 text-primary"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke="currentColor"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
                  />
                </svg>
              </div>
              <div>
                <p class="font-semibold text-base-content">Horario</p>
                <%= if @cafe_hours == [] do %>
                  <p class="text-base-content/70 mt-0.5">Lunes – Viernes: 8:00 – 21:00</p>
                <% else %>
                  <div class="space-y-0.5 mt-0.5">
                    <%= for group <- @cafe_hours do %>
                      <p class="text-base-content/70">
                        {group.label}: {format_time(group.opening)} – {format_time(group.closing)}
                      </p>
                    <% end %>
                  </div>
                <% end %>
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
                    <path d="M12 2.163c3.204 0 3.584.012 4.85.07 3.252.148 4.771 1.691 4.919 4.919.058 1.265.069 1.645.069 4.849 0 3.205-.012 3.584-.069 4.849-.149 3.225-1.664 4.771-4.919 4.919-1.266.058-1.644.07-4.85.07-3.204 0-3.584-.012-4.849-.07-3.26-.149-4.771-1.699-4.919-4.92-.058-1.265-.07-1.644-.07-4.849 0-3.204.013-3.583.07-4.849.149-3.227 1.664-4.771 4.919-4.919 1.266-.057 1.645-.069 4.849-.069zm0-2.163c-3.259 0-3.667.014-4.947.072-4.358.2-6.78 2.618-6.98 6.98-.059 1.281-.073 1.689-.073 4.948 0 3.259.014 3.668.072 4.948.2 4.358 2.618 6.78 6.98 6.98 1.281.058 1.689.072 4.948.072 3.259 0 3.668-.014 4.948-.072 4.354-.2 6.782-2.618 6.979-6.98.059-1.28.073-1.689.073-4.948 0-3.259-.014-3.667-.072-4.947-.196-4.354-2.617-6.78-6.979-6.98-1.281-.059-1.69-.073-4.949-.073zm0 5.838c-3.403 0-6.162 2.759-6.162 6.162s2.759 6.163 6.162 6.163 6.162-2.759 6.162-6.163c0-3.403-2.759-6.162-6.162-6.162zm0 10.162c-2.209 0-4-1.79-4-4 0-2.209 1.791-4 4-4s4 1.791 4 4c0 2.21-1.791 4-4 4zm6.406-11.845c-.796 0-1.441.645-1.441 1.44s.645 1.44 1.441 1.44c.795 0 1.439-.645 1.439-1.44s-.644-1.44-1.439-1.44z" />
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
                    <path d="M24 12.073c0-6.627-5.373-12-12-12s-12 5.373-12 12c0 5.99 4.388 10.954 10.125 11.854v-8.385H7.078v-3.47h3.047V9.43c0-3.007 1.792-4.669 4.533-4.669 1.312 0 2.686.235 2.686.235v2.953H15.83c-1.491 0-1.956.925-1.956 1.874v2.25h3.328l-.532 3.47h-2.796v8.385C19.612 23.027 24 18.062 24 12.073z" />
                  </svg>
                </a>
                <!-- WhatsApp -->
                <a
                  href="https://wa.me/525572155523"
                  target="_blank"
                  rel="noopener noreferrer"
                  class="w-10 h-10 bg-base-300 hover:bg-primary hover:text-primary-content rounded-xl flex items-center justify-center transition-all"
                  aria-label="WhatsApp"
                >
                  <svg class="h-5 w-5" viewBox="0 0 24 24" fill="currentColor">
                    <path d="M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347m-5.421 7.403h-.004a9.87 9.87 0 01-5.031-1.378l-.361-.214-3.741.982.998-3.648-.235-.374a9.86 9.86 0 01-1.51-5.26c.001-5.45 4.436-9.884 9.888-9.884 2.64 0 5.122 1.03 6.988 2.898a9.825 9.825 0 012.893 6.994c-.003 5.45-4.437 9.884-9.885 9.884m8.413-18.297A11.815 11.815 0 0012.05 0C5.495 0 .16 5.335.157 11.892c0 2.096.547 4.142 1.588 5.945L.057 24l6.305-1.654a11.882 11.882 0 005.683 1.448h.005c6.554 0 11.89-5.335 11.893-11.893a11.821 11.821 0 00-3.48-8.413z" />
                  </svg>
                </a>
                <!-- Teléfono (solo llamadas) -->
                <a
                  href="tel:5521217831"
                  class="w-10 h-10 bg-base-300 hover:bg-primary hover:text-primary-content rounded-xl flex items-center justify-center transition-all"
                  aria-label="Teléfono"
                >
                  <svg class="h-5 w-5" viewBox="0 0 24 24" fill="currentColor">
                    <path d="M6.62 10.79c1.44 2.83 3.76 5.14 6.59 6.59l2.2-2.2c.27-.27.67-.36 1.02-.24 1.12.37 2.33.57 3.57.57.55 0 1 .45 1 1V20c0 .55-.45 1-1 1-9.39 0-17-7.61-17-17 0-.55.45-1 1-1h3.5c.55 0 1 .45 1 1 0 1.25.2 2.45.57 3.57.11.35.03.74-.25 1.02l-2.2 2.2z" />
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
