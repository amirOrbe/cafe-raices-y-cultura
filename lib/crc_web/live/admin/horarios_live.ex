defmodule CRCWeb.Admin.HorariosLive do
  @moduledoc "Admin LiveView for managing employee work schedules."

  use CRCWeb, :live_view

  alias CRC.Accounts
  alias CRC.HR
  alias CRC.HR.WorkSchedule

  @days 1..7

  # ---------------------------------------------------------------------------
  # Mount
  # ---------------------------------------------------------------------------

  @impl true
  def mount(_params, _session, socket) do
    users = Accounts.list_users() |> Enum.reject(&(&1.role == "cliente"))

    socket =
      socket
      |> assign(:page_title, "Horarios — Admin")
      |> assign(:days, Enum.to_list(@days))
      |> assign(:users, users)
      |> assign(:selected_user, nil)
      |> assign(:schedules, [])
      |> assign(:editing, false)
      |> assign(:form_data, default_form_data())
      |> assign(:flash_msg, nil)

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("select_user", %{"id" => id}, socket) do
    user = Enum.find(socket.assigns.users, &(to_string(&1.id) == id))
    schedules = HR.list_work_schedules(user.id)
    form_data = build_form_data(schedules)

    socket =
      socket
      |> assign(:selected_user, user)
      |> assign(:schedules, schedules)
      |> assign(:editing, false)
      |> assign(:form_data, form_data)
      |> assign(:flash_msg, nil)

    {:noreply, socket}
  end

  def handle_event("start_edit", _params, socket) do
    {:noreply, assign(socket, :editing, true)}
  end

  def handle_event("cancel_edit", _params, socket) do
    form_data = build_form_data(socket.assigns.schedules)

    socket =
      socket
      |> assign(:editing, false)
      |> assign(:form_data, form_data)

    {:noreply, socket}
  end

  def handle_event("toggle_day", %{"day" => day_str}, socket) do
    day = String.to_integer(day_str)
    form_data = update_in(socket.assigns.form_data, [day, :active], &(!&1))
    {:noreply, assign(socket, :form_data, form_data)}
  end

  def handle_event("update_time", %{"day" => day_str, "field" => field, "value" => value}, socket) do
    day = String.to_integer(day_str)
    key = String.to_existing_atom(field)
    form_data = put_in(socket.assigns.form_data, [day, key], value)
    {:noreply, assign(socket, :form_data, form_data)}
  end

  def handle_event("save_schedule", _params, socket) do
    user = socket.assigns.selected_user

    entries =
      socket.assigns.form_data
      |> Enum.filter(fn {_day, data} -> data[:active] end)
      |> Enum.map(fn {day, data} ->
        %{
          day_of_week: day,
          start_time: parse_time(data[:start]),
          end_time: parse_time(data[:end])
        }
      end)

    case HR.set_work_schedules(user.id, entries) do
      {:ok, schedules} ->
        socket =
          socket
          |> assign(:schedules, schedules)
          |> assign(:editing, false)
          |> assign(:flash_msg, {:ok, "Horario guardado correctamente."})

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, assign(socket, :flash_msg, {:error, "No se pudo guardar el horario."})}
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

        <div class="mb-8">
          <h1 class="text-2xl font-bold text-base-content">Horarios de trabajo</h1>
          <p class="text-base-content/60 text-sm mt-1">
            Asigna y edita los horarios semanales del personal.
          </p>
        </div>

        <%!-- Flash --%>
        <%= if @flash_msg do %>
          <% {kind, msg} = @flash_msg %>
          <div class={"alert mb-6 #{if kind == :ok, do: "alert-success", else: "alert-error"}"}>
            <span>{msg}</span>
          </div>
        <% end %>

        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">

          <%!-- Sidebar: employee list --%>
          <div class="bg-base-100 rounded-2xl shadow-sm border border-base-300 overflow-hidden">
            <div class="px-4 py-3 border-b border-base-200">
              <h2 class="font-semibold text-base-content text-sm uppercase tracking-wide">
                Personal
              </h2>
            </div>
            <ul class="divide-y divide-base-200">
              <%= for user <- @users do %>
                <li>
                  <button
                    phx-click="select_user"
                    phx-value-id={user.id}
                    class={"w-full text-left px-4 py-3 hover:bg-base-200 transition-colors flex items-center gap-3
                      #{if @selected_user && @selected_user.id == user.id, do: "bg-primary/10 border-l-4 border-primary", else: ""}"}
                  >
                    <div class="w-8 h-8 rounded-full bg-primary/20 flex items-center justify-center shrink-0">
                      <span class="text-primary font-bold text-sm">
                        {String.first(user.name) |> String.upcase()}
                      </span>
                    </div>
                    <div class="min-w-0">
                      <p class="font-medium text-base-content text-sm truncate">{user.name}</p>
                      <p class="text-xs text-base-content/50 capitalize">{user.role}</p>
                    </div>
                  </button>
                </li>
              <% end %>
            </ul>
          </div>

          <%!-- Main panel --%>
          <div class="lg:col-span-2">
            <%= if @selected_user do %>
              <div class="bg-base-100 rounded-2xl shadow-sm border border-base-300 overflow-hidden">
                <%!-- Header --%>
                <div class="px-6 py-4 border-b border-base-200 flex items-center justify-between">
                  <div>
                    <h2 class="font-bold text-base-content">{@selected_user.name}</h2>
                    <p class="text-sm text-base-content/50 capitalize">{@selected_user.role}</p>
                  </div>
                  <%= if !@editing do %>
                    <button
                      phx-click="start_edit"
                      class="btn btn-primary btn-sm gap-2"
                    >
                      <.icon name="hero-pencil-square" class="size-4" />
                      Editar horario
                    </button>
                  <% end %>
                </div>

                <%!-- Schedule view --%>
                <%= if !@editing do %>
                  <div class="p-6">
                    <%= if @schedules == [] do %>
                      <div class="text-center py-12 text-base-content/40">
                        <.icon name="hero-calendar" class="size-12 mx-auto mb-3 opacity-30" />
                        <p>Sin horario asignado.</p>
                        <p class="text-sm mt-1">Presiona "Editar horario" para asignar días y horas.</p>
                      </div>
                    <% else %>
                      <div class="space-y-3">
                        <%= for day <- @days do %>
                          <% sched = Enum.find(@schedules, &(&1.day_of_week == day)) %>
                          <div class={"flex items-center gap-4 p-3 rounded-xl border
                            #{if sched, do: "border-primary/20 bg-primary/5", else: "border-base-200 bg-base-200/50 opacity-50"}"}>
                            <span class={"w-10 text-center font-semibold text-sm
                              #{if sched, do: "text-primary", else: "text-base-content/40"}"}>
                              {WorkSchedule.day_short(day)}
                            </span>
                            <%= if sched do %>
                              <div class="flex items-center gap-2 text-sm text-base-content">
                                <.icon name="hero-clock" class="size-4 text-primary/60" />
                                {format_time(sched.start_time)} — {format_time(sched.end_time)}
                              </div>
                            <% else %>
                              <span class="text-sm text-base-content/40">Descanso</span>
                            <% end %>
                          </div>
                        <% end %>
                      </div>
                    <% end %>
                  </div>

                <%!-- Schedule edit form --%>
                <% else %>
                  <div class="p-6 space-y-4">
                    <p class="text-sm text-base-content/60">
                      Activa los días laborales y establece los horarios de entrada y salida.
                    </p>

                    <%= for day <- @days do %>
                      <% data = @form_data[day] %>
                      <div class={"flex flex-col sm:flex-row sm:items-center gap-3 p-4 rounded-xl border transition-colors
                        #{if data[:active], do: "border-primary/30 bg-primary/5", else: "border-base-200"}"}>

                        <%!-- Day toggle --%>
                        <label class="flex items-center gap-2 cursor-pointer shrink-0">
                          <input
                            type="checkbox"
                            class="checkbox checkbox-primary checkbox-sm"
                            checked={data[:active]}
                            phx-click="toggle_day"
                            phx-value-day={day}
                          />
                          <span class={"font-semibold text-sm w-10 #{if data[:active], do: "text-primary", else: "text-base-content/50"}"}>
                            {WorkSchedule.day_short(day)}
                          </span>
                        </label>

                        <%!-- Time inputs: 2-column grid (full width on mobile, flex on sm+) --%>
                        <div class={"grid grid-cols-2 gap-3 flex-1 sm:flex sm:items-center sm:gap-3
                          #{if !data[:active], do: "opacity-40 pointer-events-none"}"}>
                          <div class="flex flex-col gap-1 sm:flex-row sm:items-center sm:gap-2">
                            <label class="text-xs text-base-content/60 shrink-0">Entrada</label>
                            <input
                              type="time"
                              class="input input-bordered input-sm w-full sm:w-32"
                              value={data[:start]}
                              phx-blur="update_time"
                              phx-value-day={day}
                              phx-value-field="start"
                            />
                          </div>
                          <div class="flex flex-col gap-1 sm:flex-row sm:items-center sm:gap-2">
                            <label class="text-xs text-base-content/60 shrink-0">Salida</label>
                            <input
                              type="time"
                              class="input input-bordered input-sm w-full sm:w-32"
                              value={data[:end]}
                              phx-blur="update_time"
                              phx-value-day={day}
                              phx-value-field="end"
                            />
                          </div>
                        </div>

                      </div>
                    <% end %>

                    <%!-- Actions --%>
                    <div class="flex gap-3 pt-2">
                      <button phx-click="save_schedule" class="btn btn-primary btn-sm gap-2">
                        <.icon name="hero-check" class="size-4" />
                        Guardar horario
                      </button>
                      <button phx-click="cancel_edit" class="btn btn-ghost btn-sm">
                        Cancelar
                      </button>
                    </div>
                  </div>
                <% end %>

              </div>
            <% else %>
              <div class="bg-base-100 rounded-2xl shadow-sm border border-base-300 p-12 text-center text-base-content/40">
                <.icon name="hero-user-group" class="size-14 mx-auto mb-4 opacity-30" />
                <p>Selecciona un empleado para ver o editar su horario.</p>
              </div>
            <% end %>
          </div>

        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp default_form_data do
    Enum.reduce(@days, %{}, fn day, acc ->
      Map.put(acc, day, %{active: false, start: "08:00", end: "16:00"})
    end)
  end

  defp build_form_data(schedules) do
    Enum.reduce(@days, default_form_data(), fn day, acc ->
      case Enum.find(schedules, &(&1.day_of_week == day)) do
        nil ->
          acc

        schedule ->
          Map.put(acc, day, %{
            active: true,
            start: format_time(schedule.start_time),
            end: format_time(schedule.end_time)
          })
      end
    end)
  end

  defp format_time(%Time{} = t), do: Calendar.strftime(t, "%H:%M")
  defp format_time(nil), do: "08:00"

  defp parse_time(str) when is_binary(str) do
    case Time.from_iso8601(str <> ":00") do
      {:ok, t} -> t
      _ -> ~T[08:00:00]
    end
  end
end
