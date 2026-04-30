defmodule CRCWeb.Admin.AsistenciaLive do
  @moduledoc "Admin LiveView for attendance monitoring and metrics."

  use CRCWeb, :live_view

  alias CRC.HR
  alias CRC.Accounts

  # ---------------------------------------------------------------------------
  # Mount
  # ---------------------------------------------------------------------------

  @impl true
  def mount(_params, _session, socket) do
    today = Date.utc_today()

    socket =
      socket
      |> assign(:page_title, "Asistencia — Admin")
      |> assign(:selected_year, today.year)
      |> assign(:selected_month, today.month)
      |> assign(:tab, :today)
      |> assign(:staff_today, HR.list_staff_today())
      |> assign(:summary, [])
      |> assign(:manual_modal, nil)
      |> assign(:time_option, "current")
      |> assign(:custom_time, "")
      |> assign(:modal_error, nil)

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    tab_atom = String.to_existing_atom(tab)

    socket =
      socket
      |> assign(:tab, tab_atom)
      |> maybe_load_summary(tab_atom)

    {:noreply, socket}
  end

  def handle_event("change_month", %{"year" => year, "month" => month}, socket) do
    y = String.to_integer(year)
    m = String.to_integer(month)

    socket =
      socket
      |> assign(:selected_year, y)
      |> assign(:selected_month, m)
      |> assign(:summary, HR.attendance_summary(y, m))

    {:noreply, socket}
  end

  def handle_event("refresh_today", _params, socket) do
    {:noreply, assign(socket, :staff_today, HR.list_staff_today())}
  end

  # --- Manual clock-in modal ---

  def handle_event("open_clock_in_modal", %{"user_id" => user_id}, socket) do
    user = Accounts.get_user!(String.to_integer(user_id))

    socket =
      socket
      |> assign(:manual_modal, {:clock_in, user})
      |> assign(:time_option, "current")
      |> assign(:custom_time, format_now())
      |> assign(:modal_error, nil)

    {:noreply, socket}
  end

  def handle_event("open_clock_out_modal", %{"user_id" => user_id}, socket) do
    user = Accounts.get_user!(String.to_integer(user_id))

    socket =
      socket
      |> assign(:manual_modal, {:clock_out, user})
      |> assign(:time_option, "current")
      |> assign(:custom_time, format_now())
      |> assign(:modal_error, nil)

    {:noreply, socket}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, :manual_modal, nil)}
  end

  def handle_event("set_time_option", %{"option" => option}, socket) do
    {:noreply, assign(socket, :time_option, option)}
  end

  def handle_event("update_custom_time", %{"value" => value}, socket) do
    {:noreply, assign(socket, :custom_time, value)}
  end

  def handle_event("confirm_manual_entry", _params, socket) do
    admin = socket.assigns.current_user
    {action, employee} = socket.assigns.manual_modal

    clock_time = resolve_time(socket.assigns.time_option, socket.assigns.custom_time)

    result =
      case action do
        :clock_in -> HR.clock_in_manual(admin, employee, clock_time)
        :clock_out -> HR.clock_out_manual(admin, employee, clock_time)
      end

    case result do
      {:ok, _record} ->
        socket =
          socket
          |> assign(:manual_modal, nil)
          |> assign(:staff_today, HR.list_staff_today())
          |> assign(:modal_error, nil)

        {:noreply, socket}

      {:error, reason} ->
        msg =
          case reason do
            :not_clocked_in -> "El empleado no ha registrado su entrada aún."
            _ -> "No se pudo registrar. Intenta de nuevo."
          end

        {:noreply, assign(socket, :modal_error, msg)}
    end
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div class="mb-6 flex items-start justify-between">
          <div>
            <h1 class="text-2xl font-bold text-base-content">Asistencia</h1>
            <p class="text-base-content/60 text-sm mt-1">
              Monitoreo en tiempo real y métricas del equipo.
            </p>
          </div>
          <button phx-click="refresh_today" class="btn btn-ghost btn-sm gap-2">
            <.icon name="hero-arrow-path" class="size-4" /> Actualizar
          </button>
        </div>

        <%!-- Tabs --%>
        <div class="tabs tabs-boxed bg-base-300/50 mb-6 w-fit">
          <button
            phx-click="switch_tab"
            phx-value-tab="today"
            class={"tab #{if @tab == :today, do: "tab-active"}"}
          >
            Hoy
          </button>
          <button
            phx-click="switch_tab"
            phx-value-tab="metrics"
            class={"tab #{if @tab == :metrics, do: "tab-active"}"}
          >
            Métricas
          </button>
        </div>

        <%!-- Today tab --%>
        <%= if @tab == :today do %>
          <.today_panel staff_today={@staff_today} />
        <% end %>

        <%!-- Metrics tab --%>
        <%= if @tab == :metrics do %>
          <.metrics_panel
            summary={@summary}
            selected_year={@selected_year}
            selected_month={@selected_month}
          />
        <% end %>
      </div>
    </div>

    <%!-- Manual entry modal --%>
    <%= if @manual_modal do %>
      <.manual_modal
        modal={@manual_modal}
        time_option={@time_option}
        custom_time={@custom_time}
        error={@modal_error}
      />
    <% end %>
    """
  end

  # ---------------------------------------------------------------------------
  # Sub-components
  # ---------------------------------------------------------------------------

  defp today_panel(assigns) do
    ~H"""
    <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
      <%= for {user, record} <- @staff_today do %>
        <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm p-5 flex flex-col gap-3">
          <%!-- User info --%>
          <div class="flex items-center gap-3">
            <div class="w-10 h-10 rounded-full bg-primary/20 flex items-center justify-center shrink-0">
              <span class="text-primary font-bold">{String.first(user.name) |> String.upcase()}</span>
            </div>
            <div class="flex-1 min-w-0">
              <p class="font-semibold text-base-content truncate">{user.name}</p>
              <div class="flex items-center gap-2 mt-0.5">
                <p class="text-xs text-base-content/50 capitalize shrink-0">{user.role}</p>
                <.attendance_status_badge record={record} />
              </div>
            </div>
          </div>

          <%!-- Clock times --%>
          <div class="grid grid-cols-2 gap-2 text-sm">
            <div class="bg-base-200 rounded-lg p-2 text-center">
              <p class="text-xs text-base-content/50">Entrada</p>
              <p class="font-semibold text-base-content">
                {if record && record.clocked_in_at,
                  do: format_time_utc(record.clocked_in_at),
                  else: "–"}
              </p>
            </div>
            <div class="bg-base-200 rounded-lg p-2 text-center">
              <p class="text-xs text-base-content/50">Salida</p>
              <p class="font-semibold text-base-content">
                {if record && record.clocked_out_at,
                  do: format_time_utc(record.clocked_out_at),
                  else: "–"}
              </p>
            </div>
          </div>

          <%!-- Actions --%>
          <div class="flex gap-2">
            <%= if is_nil(record) || is_nil(record.clocked_in_at) do %>
              <button
                phx-click="open_clock_in_modal"
                phx-value-user_id={user.id}
                class="btn btn-sm btn-outline btn-success flex-1 text-xs"
              >
                + Registrar entrada
              </button>
            <% end %>
            <%= if record && record.clocked_in_at && is_nil(record.clocked_out_at) do %>
              <button
                phx-click="open_clock_out_modal"
                phx-value-user_id={user.id}
                class="btn btn-sm btn-outline btn-primary flex-1 text-xs"
              >
                + Registrar salida
              </button>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp metrics_panel(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Month picker --%>
      <div class="flex items-center gap-3">
        <label class="text-sm font-medium text-base-content/70">Mes:</label>
        <select
          class="select select-bordered select-sm"
          phx-change="change_month"
          name="month"
        >
          <%= for {name, n} <- months() do %>
            <option value={n} selected={n == @selected_month}>{name}</option>
          <% end %>
        </select>
        <select
          class="select select-bordered select-sm"
          phx-change="change_month"
          name="year"
        >
          <%= for y <- (Date.utc_today().year - 1)..Date.utc_today().year do %>
            <option value={y} selected={y == @selected_year}>{y}</option>
          <% end %>
        </select>
      </div>

      <%!-- Summary table --%>
      <%= if @summary == [] do %>
        <div class="bg-base-100 rounded-2xl border border-base-300 p-12 text-center text-base-content/40">
          <.icon name="hero-chart-bar" class="size-12 mx-auto mb-3 opacity-30" />
          <p>Sin datos de asistencia para este período.</p>
        </div>
      <% else %>
        <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm overflow-x-auto">
          <table class="table table-zebra w-full text-sm min-w-[640px]">
            <thead>
              <tr>
                <th>Empleado</th>
                <th class="text-center">
                  <span class="badge badge-info badge-sm">Antes</span>
                </th>
                <th class="text-center">
                  <span class="badge badge-success badge-sm">A tiempo</span>
                </th>
                <th class="text-center">
                  <span class="badge badge-warning badge-sm">Tarde</span>
                </th>
                <th class="text-center">
                  <span class="badge badge-error badge-sm">Ausente</span>
                </th>
                <th class="text-center text-base-content/60 text-xs">Prom. anticipación</th>
                <th class="text-center text-base-content/60 text-xs">Prom. retraso</th>
                <th class="text-center text-base-content/60 text-xs">Días extra</th>
              </tr>
            </thead>
            <tbody>
              <%= for row <- @summary do %>
                <tr>
                  <td class="font-medium">{row.name}</td>
                  <td class="text-center font-bold text-info">{row.early}</td>
                  <td class="text-center font-bold text-success">{row.on_time}</td>
                  <td class="text-center font-bold text-warning">{row.late}</td>
                  <td class="text-center font-bold text-error">{row.absent}</td>
                  <td class="text-center text-base-content/70">
                    <%= if row.avg_early_minutes > 0 do %>
                      -{row.avg_early_minutes} min
                    <% else %>
                      –
                    <% end %>
                  </td>
                  <td class="text-center text-base-content/70">
                    <%= if row.avg_late_minutes > 0 do %>
                      +{row.avg_late_minutes} min
                    <% else %>
                      –
                    <% end %>
                  </td>
                  <td class="text-center text-base-content/70">
                    {row.overtime_days}
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      <% end %>
    </div>
    """
  end

  defp manual_modal(assigns) do
    {action, employee} = assigns.modal
    action_label = if action == :clock_in, do: "entrada", else: "salida"
    assigns = assign(assigns, action_label: action_label, employee: employee)

    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/40 backdrop-blur-sm p-4">
      <div class="bg-base-100 rounded-2xl shadow-xl w-full max-w-sm p-6 space-y-5">
        <div>
          <h3 class="text-lg font-bold text-base-content">
            Registrar {@action_label}
          </h3>
          <p class="text-sm text-base-content/60 mt-1">
            Empleado: <strong>{@employee.name}</strong>
          </p>
        </div>

        <%!-- Time option --%>
        <div class="space-y-3">
          <label class="flex items-center gap-3 cursor-pointer">
            <input
              type="radio"
              class="radio radio-primary radio-sm"
              name="time_option"
              value="current"
              checked={@time_option == "current"}
              phx-click="set_time_option"
              phx-value-option="current"
            />
            <span class="text-sm text-base-content">Hora actual ({format_now()})</span>
          </label>

          <label class="flex items-center gap-3 cursor-pointer">
            <input
              type="radio"
              class="radio radio-primary radio-sm"
              name="time_option"
              value="custom"
              checked={@time_option == "custom"}
              phx-click="set_time_option"
              phx-value-option="custom"
            />
            <span class="text-sm text-base-content">Hora diferente</span>
          </label>

          <%= if @time_option == "custom" do %>
            <div class="ml-7">
              <input
                type="time"
                class="input input-bordered input-sm w-36"
                value={@custom_time}
                phx-blur="update_custom_time"
              />
            </div>
          <% end %>
        </div>

        <%!-- Error --%>
        <%= if @error do %>
          <div class="alert alert-error text-sm py-2">{@error}</div>
        <% end %>

        <%!-- Actions --%>
        <div class="flex gap-3">
          <button
            phx-click="confirm_manual_entry"
            class="btn btn-primary btn-sm flex-1"
          >
            Confirmar
          </button>
          <button phx-click="close_modal" class="btn btn-ghost btn-sm">
            Cancelar
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp attendance_status_badge(%{record: nil} = assigns) do
    ~H"""
    <span class="badge badge-ghost badge-sm whitespace-nowrap">Sin datos</span>
    """
  end

  defp attendance_status_badge(%{record: record} = assigns) when not is_nil(record) do
    {label, cls} =
      cond do
        record.clocked_out_at -> {"Completó", "badge-neutral"}
        record.clocked_in_at && record.status == "early" -> {"Llegó antes", "badge-info"}
        record.clocked_in_at && record.status == "on_time" -> {"A tiempo", "badge-success"}
        record.clocked_in_at && record.status == "late" -> {"Tarde", "badge-warning"}
        true -> {"Ausente", "badge-error"}
      end

    assigns = assign(assigns, label: label, cls: cls)

    ~H"""
    <span class={"badge badge-sm whitespace-nowrap #{@cls}"}>{@label}</span>
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp maybe_load_summary(socket, :metrics) do
    assign(
      socket,
      :summary,
      HR.attendance_summary(socket.assigns.selected_year, socket.assigns.selected_month)
    )
  end

  defp maybe_load_summary(socket, _tab), do: socket

  defp resolve_time("current", _custom), do: DateTime.utc_now()

  defp resolve_time("custom", custom_time) do
    today = Date.utc_today()

    case Time.from_iso8601(custom_time <> ":00") do
      {:ok, t} -> DateTime.new!(today, t, "Etc/UTC")
      _ -> DateTime.utc_now()
    end
  end

  defp format_time_utc(%DateTime{} = dt) do
    local = DateTime.add(dt, -6 * 3600, :second)
    Calendar.strftime(local, "%H:%M")
  end

  defp format_now do
    local = DateTime.add(DateTime.utc_now(), -6 * 3600, :second)
    Calendar.strftime(local, "%H:%M")
  end

  defp months do
    [
      {"Enero", 1},
      {"Febrero", 2},
      {"Marzo", 3},
      {"Abril", 4},
      {"Mayo", 5},
      {"Junio", 6},
      {"Julio", 7},
      {"Agosto", 8},
      {"Septiembre", 9},
      {"Octubre", 10},
      {"Noviembre", 11},
      {"Diciembre", 12}
    ]
  end
end
