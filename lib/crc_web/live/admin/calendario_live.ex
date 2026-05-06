defmodule CRCWeb.Admin.CalendarioLive do
  @moduledoc "Weekly employee activity schedule — admin view."

  use CRCWeb, :live_view

  alias CRC.Schedule
  alias CRC.Schedule.{Area, Task}

  @days 0..6

  @impl true
  def mount(_params, _session, socket) do
    today = Date.utc_today()
    week_start = Schedule.week_start(today)

    socket =
      socket
      |> assign(:page_title, "Calendario de actividades")
      |> assign(:week_start, week_start)
      |> assign(:tab, :calendar)
      |> load_data()

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # Events — week navigation
  # ---------------------------------------------------------------------------

  @impl true
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
  # Events — tab switching
  # ---------------------------------------------------------------------------

  def handle_event("set_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :tab, String.to_existing_atom(tab))}
  end

  # ---------------------------------------------------------------------------
  # Events — assignment
  # ---------------------------------------------------------------------------

  def handle_event("assign_user", %{"task" => task_id, "day" => day, "user" => user_id}, socket) do
    Schedule.upsert_assignment(
      String.to_integer(task_id),
      String.to_integer(day),
      socket.assigns.week_start,
      user_id
    )

    {:noreply, load_assignments(socket)}
  end

  def handle_event("copy_prev_week", _params, socket) do
    prev = Date.add(socket.assigns.week_start, -7)
    Schedule.copy_week(prev, socket.assigns.week_start)
    {:noreply, socket |> load_assignments() |> put_flash(:info, "Semana anterior copiada.")}
  end

  # ---------------------------------------------------------------------------
  # Events — areas CRUD
  # ---------------------------------------------------------------------------

  def handle_event("new_area", _params, socket) do
    {:noreply, assign(socket, :area_form, to_form(Schedule.change_area(%Area{})))}
  end

  def handle_event("cancel_area_form", _params, socket) do
    {:noreply, assign(socket, :area_form, nil)}
  end

  def handle_event("save_area", %{"area" => params}, socket) do
    case socket.assigns[:editing_area] do
      nil ->
        case Schedule.create_area(params) do
          {:ok, _} ->
            {:noreply, socket |> load_areas() |> assign(:area_form, nil) |> put_flash(:info, "Área creada.")}

          {:error, cs} ->
            {:noreply, assign(socket, :area_form, to_form(cs))}
        end

      area ->
        case Schedule.update_area(area, params) do
          {:ok, _} ->
            {:noreply,
             socket
             |> load_areas()
             |> assign(:area_form, nil)
             |> assign(:editing_area, nil)
             |> put_flash(:info, "Área actualizada.")}

          {:error, cs} ->
            {:noreply, assign(socket, :area_form, to_form(cs))}
        end
    end
  end

  def handle_event("edit_area", %{"id" => id}, socket) do
    area = Schedule.get_area!(id)

    {:noreply,
     socket
     |> assign(:editing_area, area)
     |> assign(:area_form, to_form(Schedule.change_area(area)))}
  end

  def handle_event("delete_area", %{"id" => id}, socket) do
    area = Schedule.get_area!(id)
    Schedule.delete_area(area)
    {:noreply, socket |> load_areas() |> put_flash(:info, "Área eliminada.")}
  end

  def handle_event("validate_area", %{"area" => params}, socket) do
    area = socket.assigns[:editing_area] || %Area{}
    cs = Schedule.change_area(area, params)
    {:noreply, assign(socket, :area_form, to_form(cs, action: :validate))}
  end

  # ---------------------------------------------------------------------------
  # Events — tasks CRUD
  # ---------------------------------------------------------------------------

  def handle_event("new_task", %{"area_id" => area_id}, socket) do
    cs = Schedule.change_task(%Task{area_id: String.to_integer(area_id)})
    {:noreply, assign(socket, :task_form, to_form(cs)) |> assign(:task_area_id, area_id)}
  end

  def handle_event("cancel_task_form", _params, socket) do
    {:noreply, socket |> assign(:task_form, nil) |> assign(:editing_task, nil)}
  end

  def handle_event("save_task", %{"task" => params}, socket) do
    case socket.assigns[:editing_task] do
      nil ->
        case Schedule.create_task(params) do
          {:ok, _} ->
            {:noreply, socket |> load_areas() |> assign(:task_form, nil) |> put_flash(:info, "Tarea creada.")}

          {:error, cs} ->
            {:noreply, assign(socket, :task_form, to_form(cs))}
        end

      task ->
        case Schedule.update_task(task, params) do
          {:ok, _} ->
            {:noreply,
             socket
             |> load_areas()
             |> assign(:task_form, nil)
             |> assign(:editing_task, nil)
             |> put_flash(:info, "Tarea actualizada.")}

          {:error, cs} ->
            {:noreply, assign(socket, :task_form, to_form(cs))}
        end
    end
  end

  def handle_event("edit_task", %{"id" => id}, socket) do
    task = Schedule.get_task!(id)

    {:noreply,
     socket
     |> assign(:editing_task, task)
     |> assign(:task_form, to_form(Schedule.change_task(task)))}
  end

  def handle_event("delete_task", %{"id" => id}, socket) do
    task = Schedule.get_task!(id)
    Schedule.delete_task(task)
    {:noreply, socket |> load_areas() |> put_flash(:info, "Tarea eliminada.")}
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :days, Enum.to_list(@days))

    ~H"""
    <div class="space-y-6">
      <%!-- Header --%>
      <div class="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 class="text-2xl font-bold text-base-content">Calendario de actividades</h1>
          <p class="text-sm text-base-content/50 mt-0.5">Actividades semanales por empleado</p>
        </div>
        <%!-- Tab toggle --%>
        <div class="flex gap-1 bg-base-200 rounded-xl p-1">
          <button
            class={["btn btn-xs gap-1.5", if(@tab == :calendar, do: "btn-primary", else: "btn-ghost")]}
            phx-click="set_tab"
            phx-value-tab="calendar"
          >
            <.icon name="hero-calendar" class="size-3" /> Calendario
          </button>
          <button
            class={["btn btn-xs gap-1.5", if(@tab == :manage, do: "btn-primary", else: "btn-ghost")]}
            phx-click="set_tab"
            phx-value-tab="manage"
          >
            <.icon name="hero-cog-6-tooth" class="size-3" /> Áreas y tareas
          </button>
        </div>
      </div>

      <%!-- How-to tip (dismissable, stored in localStorage) --%>
      <div
        id="tip-admin-calendario"
        phx-hook="DismissableTip"
        data-tip-id="admin-calendario-v1"
        class="bg-info/10 border border-info/20 rounded-2xl p-4 flex gap-3"
      >
        <.icon name="hero-information-circle" class="size-5 text-info shrink-0 mt-0.5" />
        <div class="flex-1 min-w-0 space-y-2 text-sm text-base-content/70">
          <p class="font-semibold text-base-content">¿Cómo funciona?</p>
          <ul class="space-y-1">
            <li>
              <span class="shrink-0 font-bold">1.</span>
              <span>En la pestaña <strong>Áreas y tareas</strong> crea las secciones del café (Barra, Cocina, Limpieza…) y las actividades dentro de cada una.</span>
            </li>
            <li>
              <span class="shrink-0 font-bold">2.</span>
              <span>En la pestaña <strong>Calendario</strong> elige un empleado en cada celda — los cambios se guardan al instante.</span>
            </li>
            <li>
              <span class="shrink-0 font-bold">3.</span>
              <span>Usa <strong>Copiar semana anterior</strong> para reutilizar la misma distribución sin capturar todo de nuevo.</span>
            </li>
            <li>
              <span class="shrink-0 font-bold">4.</span>
              <span>Los empleados pueden consultar sus actividades asignadas desde su pantalla de <strong>Mi horario</strong>.</span>
            </li>
          </ul>
        </div>
        <button data-dismiss-tip class="btn btn-ghost btn-xs text-base-content/30 hover:text-base-content shrink-0 self-start">
          <.icon name="hero-x-mark" class="size-3.5" />
        </button>
      </div>

      <%= if @tab == :calendar do %>
        <.calendar_tab
          week_start={@week_start}
          areas={@areas}
          assignments={@assignments}
          employees={@employees}
          days={@days}
        />
      <% else %>
        <.manage_tab
          areas={@areas}
          area_form={Map.get(assigns, :area_form)}
          task_form={Map.get(assigns, :task_form)}
          task_area_id={Map.get(assigns, :task_area_id)}
          employees={@employees}
        />
      <% end %>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Calendar tab component
  # ---------------------------------------------------------------------------

  attr :week_start, :any, required: true
  attr :areas, :list, required: true
  attr :assignments, :map, required: true
  attr :employees, :list, required: true
  attr :days, :list, required: true

  defp calendar_tab(assigns) do
    ~H"""
    <div class="space-y-4">
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
        <button class="btn btn-outline btn-sm gap-1.5 w-full sm:w-auto" phx-click="copy_prev_week">
          <.icon name="hero-document-duplicate" class="size-4" /> Copiar semana anterior
        </button>
      </div>

      <%!-- Empty state --%>
      <%= if @areas == [] do %>
        <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm py-20 text-center">
          <.icon name="hero-calendar-days" class="size-12 text-base-content/20 mx-auto mb-3" />
          <p class="text-base-content/50 text-sm">No hay áreas ni tareas configuradas.</p>
          <button class="btn btn-primary btn-sm mt-4" phx-click="set_tab" phx-value-tab="manage">
            Agregar áreas y tareas
          </button>
        </div>
      <% end %>

      <%!-- Desktop table (hidden on mobile) --%>
      <%= if @areas != [] do %>
        <div class="hidden md:block overflow-x-auto">
          <table class="table table-fixed w-full text-sm bg-base-100 rounded-2xl shadow-sm border border-base-300">
            <thead>
              <tr class="bg-base-200 text-base-content/70">
                <th class="w-32 text-xs">Área</th>
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
                        class={"align-middle text-center font-bold text-xs uppercase tracking-wider border-r border-base-200 #{area_text_class(area.color)}"}
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
                      <td class="text-center p-1">
                        <select
                          class={[
                            "select select-xs w-full text-center font-semibold",
                            if(user, do: "#{cell_select_class(user)}", else: "select-ghost text-base-content/30")
                          ]}
                          phx-change="assign_user"
                          name={"assign_#{task.id}_#{day}"}
                          data-task={task.id}
                          data-day={day}
                          phx-value-task={task.id}
                          phx-value-day={day}
                          phx-value-user={if user, do: user.id, else: ""}
                        >
                          <option value="">—</option>
                          <%= for emp <- @employees do %>
                            <option value={emp.id} selected={user && user.id == emp.id}>
                              {Schedule.initials(emp)}
                            </option>
                          <% end %>
                        </select>
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
                  <%!-- Scrollable 7-day row so it never gets crushed on tiny screens --%>
                  <div class="overflow-x-auto -mx-1">
                    <div class="flex gap-1.5 px-1 min-w-max">
                      <%= for day <- @days do %>
                        <% assignment = get_in(@assignments, [task.id, day]) %>
                        <% user = assignment && assignment.user %>
                        <% is_today = Date.add(@week_start, day) == Date.utc_today() %>
                        <div class={"flex flex-col items-center gap-1 w-10 #{if is_today, do: "rounded-xl bg-primary/5 py-1 -my-1", else: ""}"}>
                          <span class={"text-xs font-bold #{if is_today, do: "text-primary", else: "text-base-content/40"}"}>
                            <%= String.first(Schedule.day_name(day)) %>
                          </span>
                          <select
                            class={[
                              "select select-xs w-full text-center px-0 font-semibold text-xs",
                              if(user, do: cell_select_class(user), else: "select-ghost text-base-content/30")
                            ]}
                            phx-change="assign_user"
                            phx-value-task={task.id}
                            phx-value-day={day}
                            phx-value-user={if user, do: user.id, else: ""}
                          >
                            <option value="">—</option>
                            <%= for emp <- @employees do %>
                              <option value={emp.id} selected={user && user.id == emp.id}>
                                {Schedule.initials(emp)}
                              </option>
                            <% end %>
                          </select>
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
        <div class="flex flex-wrap gap-3 pt-2">
          <%= for emp <- @employees do %>
            <div class="flex items-center gap-1.5 text-sm text-base-content/70">
              <span class={"badge badge-sm font-bold #{cell_select_class(emp)}"}>
                {Schedule.initials(emp)}
              </span>
              {emp.name}
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Manage tab component
  # ---------------------------------------------------------------------------

  attr :areas, :list, required: true
  attr :area_form, :any, default: nil
  attr :task_form, :any, default: nil
  attr :task_area_id, :any, default: nil
  attr :employees, :list, required: true

  defp manage_tab(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Areas list --%>
      <div class="space-y-3">
        <div class="flex items-center justify-between">
          <h2 class="font-semibold text-base-content">Áreas</h2>
          <button class="btn btn-primary btn-sm gap-1" phx-click="new_area">
            <.icon name="hero-plus" class="size-4" /> Nueva área
          </button>
        </div>

        <%!-- Area form --%>
        <%= if @area_form do %>
          <% preview_name = @area_form[:name].value || "" %>
          <% preview_color = @area_form[:color].value || "purple" %>
          <div class="bg-base-100 border border-primary/30 rounded-2xl p-4 shadow-sm space-y-4">
            <.form for={@area_form} phx-submit="save_area" phx-change="validate_area" class="space-y-4">
              <%!-- Name + live preview --%>
              <div class="flex items-end gap-3">
                <div class="flex-1 min-w-0">
                  <label class="label text-xs font-semibold pb-1">Nombre del área</label>
                  <.input
                    field={@area_form[:name]}
                    placeholder="Ej. Barra, Cocina, Limpieza…"
                    class="input input-bordered w-full input-sm"
                  />
                </div>
                <%!-- Live preview badge --%>
                <div class="shrink-0 pb-1">
                  <span class={"px-3 py-1.5 rounded-xl text-white text-sm font-bold whitespace-nowrap #{area_bg_class(preview_color)}"}>
                    {if preview_name == "", do: "Vista previa", else: preview_name}
                  </span>
                </div>
              </div>

              <%!-- Color swatches --%>
              <div>
                <label class="label text-xs font-semibold pb-2">Color</label>
                <div class="flex gap-3 flex-wrap">
                  <%= for {label_text, value, bg} <- color_options() do %>
                    <label
                      class={"cursor-pointer w-8 h-8 rounded-full #{bg} transition-all duration-150
                        has-[:checked]:scale-125 has-[:checked]:ring-2 has-[:checked]:ring-offset-2 has-[:checked]:ring-base-content
                        opacity-40 has-[:checked]:opacity-100 hover:opacity-80 hover:scale-110"}
                      title={label_text}
                    >
                      <input
                        type="radio"
                        name={@area_form[:color].name}
                        value={value}
                        checked={preview_color == value}
                        class="sr-only"
                      />
                    </label>
                  <% end %>
                </div>
              </div>

              <div class="flex gap-2 justify-end pt-1">
                <button type="button" class="btn btn-ghost btn-sm" phx-click="cancel_area_form">
                  Cancelar
                </button>
                <button type="submit" class="btn btn-primary btn-sm gap-1">
                  <.icon name="hero-check" class="size-3.5" /> Guardar área
                </button>
              </div>
            </.form>
          </div>
        <% end %>

        <%= if @areas == [] do %>
          <div class="bg-base-100 rounded-2xl border border-dashed border-base-300 p-8 text-center space-y-2">
            <.icon name="hero-squares-plus" class="size-10 text-base-content/20 mx-auto" />
            <p class="text-sm font-medium text-base-content/60">Aún no hay áreas</p>
            <p class="text-xs text-base-content/40">Crea una área (Barra, Cocina…) y luego agrega las actividades dentro.</p>
          </div>
        <% end %>

        <%= for area <- @areas do %>
          <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm overflow-hidden">
            <%!-- Area header --%>
            <div class={"flex items-center gap-2 px-4 py-3 #{area_bg_class(area.color)}"}>
              <span class="font-bold text-white text-sm flex-1 min-w-0 truncate">{area.name}</span>
              <div class="flex gap-1 shrink-0">
                <button
                  class="btn btn-xs btn-ghost text-white/70 hover:text-white"
                  phx-click="edit_area"
                  phx-value-id={area.id}
                >
                  <.icon name="hero-pencil" class="size-3.5" />
                </button>
                <button
                  class="btn btn-xs btn-ghost text-white/70 hover:text-white"
                  phx-click="delete_area"
                  phx-value-id={area.id}
                  data-confirm={"¿Eliminar el área \"#{area.name}\" y todas sus tareas?"}
                >
                  <.icon name="hero-trash" class="size-3.5" />
                </button>
                <button
                  class="btn btn-xs btn-ghost text-white gap-1"
                  phx-click="new_task"
                  phx-value-area_id={area.id}
                >
                  <.icon name="hero-plus" class="size-3.5" /> Tarea
                </button>
              </div>
            </div>

            <%!-- Task form (shown per-area) --%>
            <%= if @task_form && to_string(@task_area_id) == to_string(area.id) do %>
              <div class="px-4 py-3 bg-base-200/60 border-b border-base-300">
                <p class="text-xs font-semibold text-base-content/50 mb-2">Nueva actividad en <span class={"font-bold #{area_text_class(area.color)}"}>{area.name}</span></p>
                <.form for={@task_form} phx-submit="save_task" class="flex items-center gap-2">
                  <input type="hidden" name="task[area_id]" value={area.id} />
                  <div class="flex-1">
                    <.input field={@task_form[:name]} placeholder="Ej. Limpieza de mesas, Preparar jarabes…" class="input input-bordered w-full input-sm" />
                  </div>
                  <button type="submit" class="btn btn-primary btn-sm gap-1 shrink-0">
                    <.icon name="hero-plus" class="size-3.5" /> Agregar
                  </button>
                  <button type="button" class="btn btn-ghost btn-sm shrink-0 text-base-content/40" phx-click="cancel_task_form">
                    <.icon name="hero-x-mark" class="size-4" />
                  </button>
                </.form>
              </div>
            <% end %>

            <%!-- Tasks list --%>
            <div class="divide-y divide-base-200">
              <%= for task <- area.tasks do %>
                <div class="flex items-center gap-2 px-4 py-2.5">
                  <span class="text-sm text-base-content flex-1 min-w-0 truncate">{task.name}</span>
                  <div class="flex gap-1 shrink-0">
                    <button
                      class="btn btn-xs btn-ghost text-base-content/40 hover:text-base-content"
                      phx-click="edit_task"
                      phx-value-id={task.id}
                    >
                      <.icon name="hero-pencil" class="size-3.5" />
                    </button>
                    <button
                      class="btn btn-xs btn-ghost text-error/50 hover:text-error"
                      phx-click="delete_task"
                      phx-value-id={task.id}
                      data-confirm={"¿Eliminar la tarea \"#{task.name}\"?"}
                    >
                      <.icon name="hero-trash" class="size-3.5" />
                    </button>
                  </div>
                </div>
                <%!-- Inline edit for task --%>
                <%= if @task_form && Map.get(assigns, :editing_task) && Map.get(assigns, :editing_task).id == task.id do %>
                  <div class="px-4 py-2 bg-base-200/60">
                    <.form for={@task_form} phx-submit="save_task" class="flex items-center gap-2">
                      <input type="hidden" name="task[area_id]" value={task.area_id} />
                      <div class="flex-1">
                        <.input field={@task_form[:name]} class="input input-bordered w-full input-sm" />
                      </div>
                      <button type="submit" class="btn btn-primary btn-sm gap-1 shrink-0">
                        <.icon name="hero-check" class="size-3.5" /> Guardar
                      </button>
                      <button type="button" class="btn btn-ghost btn-sm shrink-0 text-base-content/40" phx-click="cancel_task_form">
                        <.icon name="hero-x-mark" class="size-4" />
                      </button>
                    </.form>
                  </div>
                <% end %>
              <% end %>
              <%= if area.tasks == [] do %>
                <div class="px-4 py-3 text-xs text-base-content/40 italic">Sin tareas — toca "+ Tarea" para agregar.</div>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>

      <%!-- Employees legend --%>
      <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm p-4 space-y-3">
        <h2 class="font-semibold text-base-content text-sm">Empleados activos</h2>
        <div class="flex flex-wrap gap-3">
          <%= for emp <- @employees do %>
            <div class="flex items-center gap-2">
              <span class={"badge badge-md font-bold #{cell_select_class(emp)}"}>{Schedule.initials(emp)}</span>
              <span class="text-sm text-base-content/70">{emp.name}</span>
            </div>
          <% end %>
        </div>
        <p class="text-xs text-base-content/40">
          Los empleados se gestionan en <a href="/admin/usuarios" class="link">Usuarios</a>.
        </p>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp load_data(socket) do
    socket
    |> load_areas()
    |> load_assignments()
    |> assign(:employees, Schedule.list_employees())
    |> assign(:area_form, nil)
    |> assign(:task_form, nil)
    |> assign(:editing_area, nil)
    |> assign(:editing_task, nil)
  end

  defp load_areas(socket) do
    assign(socket, :areas, Schedule.list_areas())
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
    month_name = Enum.at(months, date.month - 1)
    "#{date.day} #{month_name}"
  end

  # Rotates through distinct badge colors per user based on their id
  @badge_colors [
    "badge-primary",
    "badge-secondary",
    "badge-accent",
    "badge-info",
    "badge-success",
    "badge-warning",
    "badge-error"
  ]

  defp cell_select_class(%{id: id}) do
    Enum.at(@badge_colors, rem(id, length(@badge_colors)))
  end

  defp color_options do
    [
      {"Morado", "purple", "bg-violet-500"},
      {"Azul", "blue", "bg-blue-500"},
      {"Verde", "green", "bg-emerald-500"},
      {"Naranja", "orange", "bg-orange-500"},
      {"Rosa", "pink", "bg-pink-500"}
    ]
  end

  defp area_bg_class("blue"), do: "bg-blue-500"
  defp area_bg_class("green"), do: "bg-emerald-500"
  defp area_bg_class("orange"), do: "bg-orange-500"
  defp area_bg_class("pink"), do: "bg-pink-500"
  defp area_bg_class(_), do: "bg-violet-500"

  defp area_text_class("blue"), do: "text-blue-600"
  defp area_text_class("green"), do: "text-emerald-600"
  defp area_text_class("orange"), do: "text-orange-600"
  defp area_text_class("pink"), do: "text-pink-600"
  defp area_text_class(_), do: "text-violet-600"
end
