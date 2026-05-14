defmodule CRCWeb.Employee.MyScheduleLive do
  @moduledoc """
  Employee self-service LiveView.

  Shows the current week's schedule and allows the employee to clock
  in/out with geolocation verification (100 m radius from the café).
  """

  use CRCWeb, :live_view

  alias CRCWeb.Components.SiteComponents
  alias CRC.HR
  alias CRC.HR.WorkSchedule
  alias CRC.Schedule

  # ---------------------------------------------------------------------------
  # Mount
  # ---------------------------------------------------------------------------

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    # Clients have no schedule — redirect away
    if user.role == "cliente" do
      {:ok, push_navigate(socket, to: "/")}
    else
      if connected?(socket), do: Phoenix.PubSub.subscribe(CRC.PubSub, "schedule:assignments")

      schedules = HR.list_work_schedules(user.id)
      today_record = HR.get_or_create_today_record(user)
      week = build_week(schedules)

      recent =
        HR.list_attendance_for_user(user.id, today_record.date.year, today_record.date.month)

      activity_week_start = Schedule.week_start(Date.utc_today())

      socket =
        socket
        |> assign(:page_title, "Mi horario")
        |> assign(:nav_open, false)
        |> assign(:schedules, schedules)
        |> assign(:today_record, today_record)
        |> assign(:week, week)
        |> assign(:recent_records, Enum.take(recent, -14) |> Enum.reverse())
        |> assign(:clock_status, :idle)
        |> assign(:location_error, nil)
        |> assign(:activity_week_start, activity_week_start)
        |> assign(:activity_assignments, Schedule.get_user_week_assignments(activity_week_start, user.id))

      {:ok, socket}
    end
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info(:assignments_updated, socket) do
    user = socket.assigns.current_user
    week_start = socket.assigns.activity_week_start

    {:noreply,
     assign(socket, :activity_assignments, Schedule.get_user_week_assignments(week_start, user.id))}
  end

  def handle_event("toggle_nav", _params, socket),
    do: {:noreply, assign(socket, :nav_open, !socket.assigns.nav_open)}

  def handle_event("close_nav", _params, socket),
    do: {:noreply, assign(socket, :nav_open, false)}

  @impl true
  # GPS query started in the browser — show loading state immediately
  def handle_event("location_requesting", _params, socket) do
    {:noreply, assign(socket, clock_status: :requesting, location_error: nil)}
  end

  # Geolocation hook resolved a position — attempt clock-in
  def handle_event("clock_in_with_location", %{"latitude" => lat, "longitude" => lng}, socket) do
    user = socket.assigns.current_user

    case HR.clock_in(user, lat, lng) do
      {:ok, record} ->
        {:noreply,
         socket
         |> assign(:today_record, record)
         |> assign(:clock_status, :clocked_in)
         |> assign(:location_error, nil)}

      {:error, :too_far} ->
        {:noreply,
         socket
         |> assign(:clock_status, :idle)
         |> assign(:location_error, :too_far)}

      {:error, :already_clocked_in} ->
        {:noreply, assign(socket, :clock_status, :clocked_in)}
    end
  end

  # Browser denied location permission or GPS timed out / unavailable
  def handle_event("location_denied", %{"reason" => reason}, socket) do
    error =
      case reason do
        "permission_denied" -> :permission_denied
        "unavailable" -> :gps_unavailable
        "timeout" -> :gps_unavailable
        _ -> :gps_unavailable
      end

    {:noreply,
     socket
     |> assign(:clock_status, :idle)
     |> assign(:location_error, error)}
  end

  # Fallback: old-format event without reason param
  def handle_event("location_denied", _params, socket) do
    {:noreply,
     socket
     |> assign(:clock_status, :idle)
     |> assign(:location_error, :gps_unavailable)}
  end

  # Employee clocks out (no location check needed)
  def handle_event("clock_out", _params, socket) do
    user = socket.assigns.current_user

    case HR.clock_out(user) do
      {:ok, record} ->
        socket =
          socket
          |> assign(:today_record, record)
          |> assign(:clock_status, :clocked_out)
          |> assign(:location_error, nil)

        {:noreply, socket}

      {:error, :not_clocked_in} ->
        {:noreply, assign(socket, :location_error, :not_clocked_in)}
    end
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200 flex flex-col">
      <SiteComponents.site_navbar
        nav_open={@nav_open}
        current_page={:mi_horario}
        current_user={@current_user}
      />

      <div class="flex-1 max-w-2xl w-full mx-auto px-4 pt-24 pb-10 space-y-6">
        <%!-- Greeting --%>
        <div>
          <h1 class="text-2xl font-bold text-base-content">Hola, {@current_user.name} 👋</h1>
          <p class="text-base-content/60 text-sm mt-1">
            {format_date(Date.utc_today())}
          </p>
        </div>

        <%!-- Today's card --%>
        <.today_card
          today_record={@today_record}
          clock_status={@clock_status}
          location_error={@location_error}
        />

        <%!-- Weekly schedule --%>
        <div class="bg-base-100 rounded-2xl shadow-sm border border-base-300 overflow-hidden">
          <div class="px-5 py-4 border-b border-base-200">
            <h2 class="font-semibold text-base-content">Esta semana</h2>
          </div>
          <div class="p-4 grid grid-cols-7 gap-1">
            <%= for {date, schedule} <- @week do %>
              <% is_today = date == Date.utc_today() %>
              <div class={"flex flex-col items-center py-3 px-1 rounded-xl text-center
                #{if is_today, do: "bg-primary/10 border border-primary/30", else: ""}
                #{if !schedule, do: "opacity-40", else: ""}"}>
                <span class={"text-xs font-semibold #{if is_today, do: "text-primary", else: "text-base-content/50"}"}>
                  {WorkSchedule.day_short(Date.day_of_week(date))}
                </span>
                <span class={"text-lg font-bold mt-0.5 #{if is_today, do: "text-primary", else: "text-base-content"}"}>
                  {date.day}
                </span>
                <%= if schedule do %>
                  <span class="text-xs text-base-content/60 mt-1 leading-tight">
                    {format_time(schedule.start_time)}<br />{format_time(schedule.end_time)}
                  </span>
                <% else %>
                  <span class="text-xs text-base-content/30 mt-1">–</span>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>

        <%!-- Weekly activity assignments --%>
        <div class="bg-base-100 rounded-2xl shadow-sm border border-base-300 overflow-hidden">
          <div class="px-5 py-4 border-b border-base-200">
            <h2 class="font-semibold text-base-content">Mis actividades esta semana</h2>
            <p class="text-xs text-base-content/50 mt-0.5">Asignadas por el administrador</p>
          </div>
          <%= if @activity_assignments == %{} do %>
            <div class="px-5 py-8 text-center text-sm text-base-content/40">
              Sin actividades asignadas esta semana.
            </div>
          <% else %>
            <div class="divide-y divide-base-200">
              <%= for day <- 0..6 do %>
                <% tasks_for_day = Map.get(@activity_assignments, day, []) %>
                <%= if tasks_for_day != [] do %>
                  <% day_date = Date.add(@activity_week_start, day) %>
                  <div class="flex items-start gap-3 px-5 py-3">
                    <div class={"text-xs font-bold w-10 shrink-0 pt-0.5 text-center #{if day_date == Date.utc_today(), do: "text-primary", else: "text-base-content/40"}"}>
                      <p>{Schedule.day_name(day)}</p>
                      <p class="font-normal opacity-70">{day_date.day}/{day_date.month}</p>
                    </div>
                    <div class="flex flex-wrap gap-1.5 flex-1 pt-0.5">
                      <%= for a <- tasks_for_day do %>
                        <span class={"badge badge-sm font-medium #{activity_badge_class(a.task.area.color)}"}>
                          {a.task.name}
                        </span>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              <% end %>
            </div>
          <% end %>
        </div>

        <%!-- Recent attendance history --%>
        <%= if @recent_records != [] do %>
          <div class="bg-base-100 rounded-2xl shadow-sm border border-base-300 overflow-hidden">
            <div class="px-5 py-4 border-b border-base-200">
              <h2 class="font-semibold text-base-content">Historial reciente</h2>
            </div>
            <ul class="divide-y divide-base-200">
              <%= for record <- @recent_records do %>
                <li class="flex items-center gap-4 px-5 py-3">
                  <.status_badge status={record.status} />
                  <div class="flex-1 min-w-0">
                    <p class="text-sm font-medium text-base-content">
                      {format_date(record.date)}
                    </p>
                    <p class="text-xs text-base-content/50">
                      <%= if record.clocked_in_at do %>
                        Entrada: {format_datetime(record.clocked_in_at)}
                        <%= if record.clocked_out_at do %>
                          · Salida: {format_datetime(record.clocked_out_at)}
                        <% end %>
                      <% else %>
                        Sin registro de entrada
                      <% end %>
                    </p>
                  </div>
                  <%= if record.manual_entry do %>
                    <span class="badge badge-ghost badge-xs">Admin</span>
                  <% end %>
                </li>
              <% end %>
            </ul>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Components
  # ---------------------------------------------------------------------------

  defp today_card(%{today_record: record} = assigns) do
    already_in = not is_nil(record.clocked_in_at)
    already_out = not is_nil(record.clocked_out_at)
    requesting = assigns.clock_status == :requesting

    assigns =
      assign(assigns, already_in: already_in, already_out: already_out, requesting: requesting)

    ~H"""
    <div class="bg-base-100 rounded-2xl shadow-sm border border-base-300 p-6">
      <div class="flex items-start justify-between mb-4">
        <div>
          <h2 class="font-semibold text-base-content">Hoy</h2>
          <%= if @today_record.scheduled_start do %>
            <p class="text-sm text-base-content/60 mt-0.5">
              Horario: {format_time(@today_record.scheduled_start)} — {format_time(
                @today_record.scheduled_end
              )}
            </p>
          <% else %>
            <p class="text-sm text-base-content/40 mt-0.5">Día sin horario asignado</p>
          <% end %>
        </div>
        <.status_badge status={
          cond do
            @already_out -> "out"
            @already_in -> @today_record.status
            true -> "absent"
          end
        } />
      </div>

      <%!-- Times --%>
      <div class="grid grid-cols-2 gap-4 mb-6">
        <div class={"p-3 rounded-xl border #{if @already_in, do: "border-success/30 bg-success/5", else: "border-base-200 bg-base-200/50"}"}>
          <p class="text-xs text-base-content/50 mb-1">Entrada</p>
          <p class={"text-lg font-bold #{if @already_in, do: "text-success", else: "text-base-content/30"}"}>
            {if @already_in, do: format_datetime(@today_record.clocked_in_at), else: "–"}
          </p>
        </div>
        <div class={"p-3 rounded-xl border #{if @already_out, do: "border-primary/30 bg-primary/5", else: "border-base-200 bg-base-200/50"}"}>
          <p class="text-xs text-base-content/50 mb-1">Salida</p>
          <p class={"text-lg font-bold #{if @already_out, do: "text-primary", else: "text-base-content/30"}"}>
            {if @already_out, do: format_datetime(@today_record.clocked_out_at), else: "–"}
          </p>
        </div>
      </div>

      <%!-- GPS requesting — inline loading indicator --%>
      <%= if @requesting do %>
        <div class="flex items-center gap-2 text-sm text-base-content/60 mb-4 p-3 rounded-xl bg-base-200">
          <span class="loading loading-spinner loading-sm text-primary"></span>
          Obteniendo tu ubicación…
        </div>
      <% end %>

      <%!-- Location / action errors --%>
      <%= if @location_error && !@requesting do %>
        <%= case @location_error do %>
          <% :too_far -> %>
            <%!-- GPS funcionó pero indicó que está lejos: puede ser imprecisión → ofrecer reintento --%>
            <div class="alert alert-warning mb-4 text-sm flex-col items-start gap-2">
              <div class="flex items-center gap-2">
                <.icon name="hero-map-pin" class="size-4 shrink-0" />
                <span>
                  El GPS indicó que estás lejos del café.
                  Si ya estás aquí, puede ser imprecisión de la señal — intenta de nuevo.
                </span>
              </div>
              <button
                id="clock-in-retry-btn"
                phx-hook="GeolocationClockIn"
                class="btn btn-warning btn-sm gap-1 self-stretch sm:self-auto"
              >
                <.icon name="hero-arrow-path" class="size-4" /> Reintentar ubicación
              </button>
            </div>
          <% :permission_denied -> %>
            <%!-- El navegador bloqueó los permisos — JS ya no puede volver a pedir --%>
            <div class="alert alert-error mb-4 text-sm flex-col items-start gap-1">
              <div class="flex items-center gap-2">
                <.icon name="hero-no-symbol" class="size-4 shrink-0" />
                <span class="font-semibold">Permiso de ubicación bloqueado</span>
              </div>
              <p>Tu navegador tiene el permiso desactivado para este sitio. Para habilitarlo:</p>
              <ul class="list-disc list-inside space-y-0.5 text-xs">
                <li>
                  <span class="font-medium">iPhone/iPad:</span>
                  Ajustes → Safari → Ubicación → Permitir
                </li>
                <li>
                  <span class="font-medium">Android Chrome:</span>
                  toca el candado 🔒 en la barra de dirección → Permisos → Ubicación
                </li>
                <li>
                  <span class="font-medium">Android otro:</span>
                  Ajustes del navegador → Permisos de sitio → Ubicación
                </li>
              </ul>
              <p class="text-xs mt-1">
                También puedes pedir a tu administrador que registre tu llegada manualmente.
              </p>
            </div>
          <% :gps_unavailable -> %>
            <%!-- GPS falló o expiró el tiempo — se puede reintentar --%>
            <div class="alert alert-warning mb-4 text-sm flex-col items-start gap-2">
              <div class="flex items-center gap-2">
                <.icon name="hero-signal-slash" class="size-4 shrink-0" />
                <span>
                  No se pudo obtener tu ubicación (señal débil o GPS apagado). Intenta de nuevo.
                </span>
              </div>
              <button
                id="clock-in-retry-btn"
                phx-hook="GeolocationClockIn"
                class="btn btn-warning btn-sm gap-1 self-stretch sm:self-auto"
              >
                <.icon name="hero-arrow-path" class="size-4" /> Reintentar
              </button>
            </div>
          <% :not_clocked_in -> %>
            <div class="alert alert-warning mb-4 text-sm">
              <.icon name="hero-exclamation-triangle" class="size-4 shrink-0" />
              Aún no has registrado tu entrada.
            </div>
        <% end %>
      <% end %>

      <%!-- Actions --%>
      <div class="flex gap-3">
        <%= if !@already_in do %>
          <%!-- Main clock-in button; hidden while a retry button is showing to avoid duplicate hooks --%>
          <%= if @location_error not in [:too_far, :gps_unavailable] do %>
            <button
              id="clock-in-btn"
              phx-hook="GeolocationClockIn"
              disabled={@requesting}
              class={"btn btn-success flex-1 gap-2 #{if @requesting, do: "btn-disabled opacity-70"}"}
            >
              <%= if @requesting do %>
                <span class="loading loading-spinner loading-sm"></span>
              <% else %>
                <.icon name="hero-finger-print" class="size-5" />
              <% end %>
              Ya estoy aquí
            </button>
          <% end %>
        <% end %>

        <%= if @already_in and !@already_out do %>
          <button
            phx-click="clock_out"
            class="btn btn-primary flex-1 gap-2"
          >
            <.icon name="hero-arrow-right-on-rectangle" class="size-5" /> Registrar salida
          </button>
        <% end %>

        <%= if @already_in and @already_out do %>
          <div class="flex-1 p-3 rounded-xl bg-base-200 text-center text-sm text-base-content/60">
            Jornada completada ✓
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp status_badge(assigns) do
    {label, classes} =
      case assigns.status do
        "early" -> {"Llegó antes", "badge-info"}
        "on_time" -> {"A tiempo", "badge-success"}
        "late" -> {"Tarde", "badge-warning"}
        "absent" -> {"Ausente", "badge-error"}
        "out" -> {"Salida marcada", "badge-neutral"}
        _ -> {"–", "badge-ghost"}
      end

    assigns = assign(assigns, label: label, classes: classes)

    ~H"""
    <span class={"badge badge-sm #{@classes}"}>{@label}</span>
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp build_week(schedules) do
    today = Date.utc_today()
    day_of_week = Date.day_of_week(today)
    monday = Date.add(today, -(day_of_week - 1))

    Enum.map(0..6, fn offset ->
      date = Date.add(monday, offset)
      schedule = Enum.find(schedules, &(&1.day_of_week == Date.day_of_week(date)))
      {date, schedule}
    end)
  end

  defp format_time(%Time{} = t), do: Calendar.strftime(t, "%H:%M")
  defp format_time(nil), do: "–"

  defp format_datetime(%DateTime{} = dt) do
    # Display in Mexico City time (UTC-6); approximated as UTC-6 without DST here
    local = DateTime.add(dt, -6 * 3600, :second)
    Calendar.strftime(local, "%H:%M")
  end

  defp format_datetime(nil), do: "–"

  # Maps area color key to a DaisyUI badge class
  defp activity_badge_class("blue"), do: "badge-info"
  defp activity_badge_class("green"), do: "badge-success"
  defp activity_badge_class("orange"), do: "badge-warning"
  defp activity_badge_class("pink"), do: "badge-error"
  defp activity_badge_class(_), do: "badge-secondary"

  defp format_date(%Date{} = date) do
    months =
      ~w(enero febrero marzo abril mayo junio julio agosto septiembre octubre noviembre diciembre)

    days = ~w(lunes martes miércoles jueves viernes sábado domingo)
    day_name = Enum.at(days, Date.day_of_week(date) - 1)
    month_name = Enum.at(months, date.month - 1)
    "#{String.capitalize(day_name)}, #{date.day} de #{month_name} de #{date.year}"
  end
end
