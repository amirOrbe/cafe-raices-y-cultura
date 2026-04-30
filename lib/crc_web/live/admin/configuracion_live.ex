defmodule CRCWeb.Admin.ConfiguracionLive do
  @moduledoc "Admin LiveView for managing café business hours."

  use CRCWeb, :live_view

  alias CRC.Settings
  alias CRC.Settings.CafeHours

  @days 1..7

  # ---------------------------------------------------------------------------
  # Mount
  # ---------------------------------------------------------------------------

  @impl true
  def mount(_params, _session, socket) do
    rows = Settings.list_cafe_hours()
    form_data = Settings.build_form_data(rows)

    socket =
      socket
      |> assign(:page_title, "Configuración — Admin")
      |> assign(:days, Enum.to_list(@days))
      |> assign(:rows, rows)
      |> assign(:editing, false)
      |> assign(:form_data, form_data)
      |> assign(:flash_msg, nil)

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("start_edit", _params, socket) do
    {:noreply, assign(socket, :editing, true)}
  end

  def handle_event("cancel_edit", _params, socket) do
    form_data = Settings.build_form_data(socket.assigns.rows)

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

  def handle_event("save_hours", _params, socket) do
    entries =
      Enum.map(socket.assigns.form_data, fn {day, data} ->
        %{
          day_of_week: day,
          is_closed: !data[:active],
          opening_time: parse_time(data[:opening]),
          closing_time: parse_time(data[:closing])
        }
      end)

    case Settings.set_cafe_hours(entries) do
      {:ok, rows} ->
        socket =
          socket
          |> assign(:rows, rows)
          |> assign(:editing, false)
          |> assign(:flash_msg, {:ok, "Horario del café guardado correctamente."})

        {:noreply, socket}

      {:error, _} ->
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
      <div class="max-w-3xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <%!-- Page header --%>
        <div class="mb-8 flex flex-wrap items-start justify-between gap-4">
          <div>
            <h1 class="text-2xl font-bold text-base-content">Configuración del café</h1>
            <p class="text-base-content/60 text-sm mt-1">
              Horario de apertura y cierre del establecimiento por día de la semana.
            </p>
          </div>
          <%= if !@editing do %>
            <button phx-click="start_edit" class="btn btn-primary btn-sm gap-2 shrink-0">
              <.icon name="hero-pencil-square" class="size-4" /> Editar horario
            </button>
          <% end %>
        </div>

        <%!-- Flash --%>
        <%= if @flash_msg do %>
          <% {kind, msg} = @flash_msg %>
          <div class={"alert mb-6 #{if kind == :ok, do: "alert-success", else: "alert-error"}"}>
            <span>{msg}</span>
          </div>
        <% end %>

        <div class="bg-base-100 rounded-2xl shadow-sm border border-base-300 overflow-hidden">
          <%!-- View mode --%>
          <%= if !@editing do %>
            <%= if @rows == [] do %>
              <div class="p-12 text-center text-base-content/40">
                <.icon name="hero-clock" class="size-12 mx-auto mb-3 opacity-30" />
                <p>Sin horario configurado.</p>
                <p class="text-sm mt-1">
                  Presiona "Editar horario" para definir los días y horas de apertura.
                </p>
              </div>
            <% else %>
              <div class="divide-y divide-base-200">
                <%= for day <- @days do %>
                  <% row = Enum.find(@rows, &(&1.day_of_week == day)) %>
                  <div class="flex items-center gap-4 px-6 py-4">
                    <span class={"w-24 shrink-0 font-semibold text-sm
                      #{if row && !row.is_closed, do: "text-primary", else: "text-base-content/40"}"}>
                      {CafeHours.day_name(day)}
                    </span>
                    <span class="text-sm text-base-content">
                      <%= cond do %>
                        <% is_nil(row) -> %>
                          <span class="text-base-content/30">Sin configurar</span>
                        <% row.is_closed -> %>
                          <span class="badge badge-ghost badge-sm">Cerrado</span>
                        <% true -> %>
                          <span class="flex items-center gap-2">
                            <.icon name="hero-clock" class="size-4 text-primary/60" />
                            {format_time(row.opening_time)} — {format_time(row.closing_time)}
                          </span>
                      <% end %>
                    </span>
                  </div>
                <% end %>
              </div>
            <% end %>

            <%!-- Edit mode --%>
          <% else %>
            <div class="p-6 space-y-4">
              <p class="text-sm text-base-content/60">
                Activa los días en que el café está abierto y establece los horarios de apertura y cierre.
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
                    <span class={"font-semibold text-sm w-24 #{if data[:active], do: "text-primary", else: "text-base-content/50"}"}>
                      {CafeHours.day_name(day)}
                    </span>
                  </label>

                  <%!-- Time inputs --%>
                  <div class={"grid grid-cols-2 gap-3 flex-1 sm:flex sm:items-center sm:gap-3
                    #{if !data[:active], do: "opacity-40 pointer-events-none"}"}>
                    <div class="flex flex-col gap-1 sm:flex-row sm:items-center sm:gap-2">
                      <label class="text-xs text-base-content/60 shrink-0">Apertura</label>
                      <input
                        type="time"
                        class="input input-bordered input-sm w-full sm:w-32"
                        value={data[:opening]}
                        phx-blur="update_time"
                        phx-value-day={day}
                        phx-value-field="opening"
                      />
                    </div>
                    <div class="flex flex-col gap-1 sm:flex-row sm:items-center sm:gap-2">
                      <label class="text-xs text-base-content/60 shrink-0">Cierre</label>
                      <input
                        type="time"
                        class="input input-bordered input-sm w-full sm:w-32"
                        value={data[:closing]}
                        phx-blur="update_time"
                        phx-value-day={day}
                        phx-value-field="closing"
                      />
                    </div>
                  </div>
                </div>
              <% end %>

              <%!-- Actions --%>
              <div class="flex flex-wrap gap-3 pt-2">
                <button phx-click="save_hours" class="btn btn-primary btn-sm gap-2">
                  <.icon name="hero-check" class="size-4" /> Guardar horario
                </button>
                <button phx-click="cancel_edit" class="btn btn-ghost btn-sm">
                  Cancelar
                </button>
              </div>
            </div>
          <% end %>
        </div>

        <%!-- Info card --%>
        <div class="mt-6 rounded-xl border border-base-300 bg-base-100 p-4 flex gap-3">
          <.icon name="hero-information-circle" class="size-5 text-primary/60 shrink-0 mt-0.5" />
          <div class="text-sm text-base-content/60 space-y-1">
            <p>
              Este horario define cuándo el café está operando. Los eventos programados dentro
              de este rango descuentan tiempo disponible para reservaciones automáticamente.
            </p>
            <p>
              Los días marcados como <strong>cerrado</strong> no aceptan reservaciones
              independientemente de si hay eventos.
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp format_time(%Time{} = t), do: Calendar.strftime(t, "%H:%M")
  defp format_time(nil), do: "—"

  defp parse_time(str) when is_binary(str) do
    case Time.from_iso8601(str <> ":00") do
      {:ok, t} -> t
      _ -> ~T[10:00:00]
    end
  end
end
