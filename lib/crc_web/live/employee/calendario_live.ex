defmodule CRCWeb.Employee.CalendarioLive do
  @moduledoc "Read-only weekly activity calendar for all employees."

  use CRCWeb, :live_view

  alias CRCWeb.Components.SiteComponents
  alias CRC.Schedule

  @days 0..6

  @impl true
  def mount(_params, _session, socket) do
    today = Date.utc_today()
    week_start = Schedule.week_start(today)

    socket =
      socket
      |> assign(:page_title, "Calendario de actividades")
      |> assign(:week_start, week_start)
      |> assign(:nav_open, false)
      |> load_data()

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("toggle_nav", _params, socket),
    do: {:noreply, assign(socket, :nav_open, !socket.assigns.nav_open)}

  def handle_event("close_nav", _params, socket),
    do: {:noreply, assign(socket, :nav_open, false)}

  def handle_event("prev_week", _params, socket) do
    {:noreply,
     socket
     |> assign(:week_start, Date.add(socket.assigns.week_start, -7))
     |> load_assignments()}
  end

  def handle_event("next_week", _params, socket) do
    {:noreply,
     socket
     |> assign(:week_start, Date.add(socket.assigns.week_start, 7))
     |> load_assignments()}
  end

  def handle_event("go_today", _params, socket) do
    {:noreply,
     socket
     |> assign(:week_start, Schedule.week_start(Date.utc_today()))
     |> load_assignments()}
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :days, Enum.to_list(@days))

    ~H"""
    <div class="min-h-screen bg-base-200 flex flex-col">
      <SiteComponents.site_navbar
        nav_open={@nav_open}
        current_page={:calendario}
        current_user={@current_user}
      />

      <div class="flex-1 max-w-4xl w-full mx-auto px-4 pt-24 pb-10 space-y-5">
        <%!-- Header --%>
        <div>
          <h1 class="text-2xl font-bold text-base-content">Calendario de actividades</h1>
          <p class="text-sm text-base-content/50 mt-0.5">Actividades asignadas por semana</p>
        </div>

        <%!-- Week navigation --%>
        <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2">
          <div class="flex items-center gap-1">
            <button class="btn btn-ghost btn-sm shrink-0" phx-click="prev_week">
              <.icon name="hero-chevron-left" class="size-4" />
            </button>
            <span class="font-semibold text-base-content text-sm flex-1 text-center sm:min-w-52">
              <%= format_week(@week_start) %>
            </span>
            <button class="btn btn-ghost btn-sm shrink-0" phx-click="next_week">
              <.icon name="hero-chevron-right" class="size-4" />
            </button>
            <button class="btn btn-ghost btn-xs text-base-content/50 shrink-0" phx-click="go_today">
              Hoy
            </button>
          </div>
        </div>

        <%= if @areas == [] do %>
          <%!-- Empty state --%>
          <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm py-20 text-center">
            <.icon name="hero-calendar-days" class="size-12 text-base-content/20 mx-auto mb-3" />
            <p class="text-base-content/50 text-sm">Aún no hay actividades configuradas.</p>
          </div>
        <% else %>
          <%!-- Desktop table --%>
          <div class="hidden md:block overflow-x-auto">
            <table class="table table-fixed w-full text-sm bg-base-100 rounded-2xl shadow-sm border border-base-300">
              <thead>
                <tr class="bg-base-200 text-base-content/70">
                  <th class="w-28 text-xs">Área</th>
                  <th class="text-xs">Tarea</th>
                  <%= for day <- @days do %>
                    <th class={"text-center text-xs w-20 #{if Date.add(@week_start, day) == Date.utc_today(), do: "text-primary font-bold", else: ""}"}>
                      <%= Schedule.day_name(day) %><br />
                      <span class="font-normal text-xs opacity-60">
                        <%= format_day(Date.add(@week_start, day)) %>
                      </span>
                    </th>
                  <% end %>
                </tr>
              </thead>
              <tbody>
                <%= for area <- @areas do %>
                  <%= for {task, idx} <- Enum.with_index(area.tasks) do %>
                    <tr class={if rem(idx, 2) == 0, do: "bg-base-100", else: "bg-base-50"}>
                      <%= if idx == 0 do %>
                        <td
                          rowspan={length(area.tasks)}
                          class="align-middle text-center border-r border-base-200"
                        >
                          <div class={"inline-block px-2 py-1 rounded-lg text-white text-xs font-semibold #{area_bg_class(area.color)}"}>
                            {area.name}
                          </div>
                        </td>
                      <% end %>
                      <td class="text-xs font-medium text-base-content border-r border-base-200 py-2 px-3">
                        {task.name}
                      </td>
                      <%= for day <- @days do %>
                        <% assignment = get_in(@assignments, [task.id, day]) %>
                        <% user = assignment && assignment.user %>
                        <% is_me = user && user.id == @current_user.id %>
                        <td class="text-center p-1.5">
                          <%= if user do %>
                            <span class={"badge badge-sm font-semibold #{if is_me, do: "badge-primary ring-2 ring-primary ring-offset-1", else: employee_badge_class(user)}"}>
                              {Schedule.initials(user)}
                            </span>
                          <% else %>
                            <span class="text-base-content/20 text-xs">—</span>
                          <% end %>
                        </td>
                      <% end %>
                    </tr>
                  <% end %>
                <% end %>
              </tbody>
            </table>
          </div>

          <%!-- Mobile cards --%>
          <div class="md:hidden space-y-4">
            <%= for area <- @areas do %>
              <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm overflow-hidden">
                <div class={"px-4 py-2.5 font-bold text-sm text-white #{area_bg_class(area.color)}"}>
                  {area.name}
                </div>
                <%= for task <- area.tasks do %>
                  <div class="px-3 py-3 border-b border-base-200 last:border-0">
                    <p class="text-sm font-medium text-base-content mb-2 px-1">{task.name}</p>
                    <div class="overflow-x-auto -mx-1">
                      <div class="flex gap-2 px-1 min-w-max">
                        <%= for day <- @days do %>
                          <% assignment = get_in(@assignments, [task.id, day]) %>
                          <% user = assignment && assignment.user %>
                          <% is_today = Date.add(@week_start, day) == Date.utc_today() %>
                          <% is_me = user && user.id == @current_user.id %>
                          <div class={"flex flex-col items-center gap-1 w-10 #{if is_today, do: "rounded-xl bg-primary/5 py-1 -my-1", else: ""}"}>
                            <span class={"text-xs font-bold #{if is_today, do: "text-primary", else: "text-base-content/40"}"}>
                              <%= String.first(Schedule.day_name(day)) %>
                            </span>
                            <%= if user do %>
                              <span class={"badge badge-xs font-semibold #{if is_me, do: "badge-primary", else: employee_badge_class(user)}"}>
                                {Schedule.initials(user)}
                              </span>
                            <% else %>
                              <span class="text-base-content/20 text-xs">—</span>
                            <% end %>
                          </div>
                        <% end %>
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>

          <%!-- Employee legend --%>
          <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm p-4">
            <p class="text-xs font-semibold text-base-content/50 uppercase tracking-wider mb-3">
              Empleados
            </p>
            <div class="flex flex-wrap gap-3">
              <%= for emp <- @employees do %>
                <div class="flex items-center gap-1.5">
                  <span class={"badge badge-sm font-bold #{if emp.id == @current_user.id, do: "badge-primary ring-2 ring-primary ring-offset-1", else: employee_badge_class(emp)}"}>
                    {Schedule.initials(emp)}
                  </span>
                  <span class={"text-sm #{if emp.id == @current_user.id, do: "font-semibold text-base-content", else: "text-base-content/60"}"}>
                    {emp.name}
                    <%= if emp.id == @current_user.id do %>
                      <span class="text-primary text-xs">(tú)</span>
                    <% end %>
                  </span>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp load_data(socket) do
    socket
    |> load_assignments()
    |> assign(:areas, Schedule.list_areas())
    |> assign(:employees, Schedule.list_employees())
  end

  defp load_assignments(socket) do
    assign(socket, :assignments, Schedule.get_week_assignments(socket.assigns.week_start))
  end

  defp format_week(%Date{} = date) do
    week_end = Date.add(date, 6)
    "#{format_day_long(date)} — #{format_day_long(week_end)} #{date.year}"
  end

  defp format_day(%Date{} = date), do: "#{date.day}/#{date.month}"

  defp format_day_long(%Date{} = date) do
    months = ~w(ene feb mar abr may jun jul ago sep oct nov dic)
    "#{date.day} #{Enum.at(months, date.month - 1)}"
  end

  @badge_colors ~w(badge-secondary badge-accent badge-info badge-success badge-warning badge-error badge-neutral)

  defp employee_badge_class(%{id: id}),
    do: Enum.at(@badge_colors, rem(id, length(@badge_colors)))

  defp area_bg_class("blue"), do: "bg-blue-500"
  defp area_bg_class("green"), do: "bg-emerald-500"
  defp area_bg_class("orange"), do: "bg-orange-500"
  defp area_bg_class("pink"), do: "bg-pink-500"
  defp area_bg_class(_), do: "bg-violet-500"
end
