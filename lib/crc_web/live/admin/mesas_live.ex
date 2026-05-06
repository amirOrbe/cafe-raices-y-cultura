defmodule CRCWeb.Admin.MesasLive do
  @moduledoc "Admin floor-map editor: create, position, and manage restaurant tables."

  use CRCWeb, :live_view

  alias CRC.Orders
  alias CRC.Orders.Table

  @impl true
  def mount(_params, _session, socket) do
    tables = Orders.list_tables()

    socket =
      socket
      |> assign(:page_title, "Mesas")
      |> assign(:tables, tables)
      |> assign(:show_modal, false)
      |> assign(:editing_table, nil)
      |> assign(:form, to_form(Orders.change_table(%Table{})))
      |> assign(:confirm_delete_id, nil)

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("new_table", _params, socket) do
    # Pre-fill number with next available integer
    next_number = next_available_number(socket.assigns.tables)
    cs = Orders.change_table(%Table{}, %{number: next_number})

    {:noreply,
     socket
     |> assign(:show_modal, true)
     |> assign(:editing_table, nil)
     |> assign(:form, to_form(cs))}
  end

  def handle_event("edit_table", %{"id" => id}, socket) do
    table = Orders.get_table!(id)
    cs = Orders.change_table(table)

    {:noreply,
     socket
     |> assign(:show_modal, true)
     |> assign(:editing_table, table)
     |> assign(:form, to_form(cs))}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_modal, false)
     |> assign(:editing_table, nil)
     |> assign(:confirm_delete_id, nil)}
  end

  def handle_event("validate", %{"table" => params}, socket) do
    table = socket.assigns.editing_table || %Table{}
    cs = Orders.change_table(table, params)
    {:noreply, assign(socket, :form, to_form(cs, action: :validate))}
  end

  def handle_event("save", %{"table" => params}, socket) do
    case socket.assigns.editing_table do
      nil ->
        # Find position for new table: offset from center so they don't all stack
        tables = socket.assigns.tables
        {x, y} = spread_position(length(tables))

        case Orders.create_table(Map.merge(params, %{"x_pct" => x, "y_pct" => y})) do
          {:ok, _table} ->
            {:noreply,
             socket
             |> assign(:tables, Orders.list_tables())
             |> assign(:show_modal, false)
             |> put_flash(:info, "Mesa creada")}

          {:error, cs} ->
            {:noreply, assign(socket, :form, to_form(cs, action: :insert))}
        end

      table ->
        case Orders.update_table(table, params) do
          {:ok, _table} ->
            {:noreply,
             socket
             |> assign(:tables, Orders.list_tables())
             |> assign(:show_modal, false)
             |> assign(:editing_table, nil)
             |> put_flash(:info, "Mesa actualizada")}

          {:error, cs} ->
            {:noreply, assign(socket, :form, to_form(cs, action: :update))}
        end
    end
  end

  def handle_event("confirm_delete", %{"id" => id}, socket) do
    {:noreply, assign(socket, :confirm_delete_id, String.to_integer(id))}
  end

  def handle_event("delete_table", %{"id" => id}, socket) do
    table = Orders.get_table!(id)

    case Orders.delete_table(table) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:tables, Orders.list_tables())
         |> assign(:show_modal, false)
         |> assign(:confirm_delete_id, nil)
         |> put_flash(:info, "Mesa eliminada")}

      {:error, _cs} ->
        {:noreply,
         socket
         |> put_flash(:error, "No se pudo eliminar la mesa (puede tener comandas asociadas)")}
    end
  end

  def handle_event("table_moved", %{"id" => id, "x_pct" => x, "y_pct" => y}, socket) do
    table = Orders.get_table!(id)

    case Orders.move_table(table, x, y) do
      {:ok, updated} ->
        tables =
          Enum.map(socket.assigns.tables, fn t ->
            if t.id == updated.id, do: updated, else: t
          end)

        {:noreply, assign(socket, :tables, tables)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "No se pudo guardar la posición")}
    end
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Header --%>
      <div class="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 class="text-2xl font-bold text-base-content">Distribución de mesas</h1>
          <p class="text-sm text-base-content/50 mt-0.5">
            {length(@tables)} mesa{if length(@tables) != 1, do: "s"} · Arrastra para reposicionar
          </p>
        </div>
        <button class="btn btn-primary btn-sm gap-1" phx-click="new_table">
          <.icon name="hero-plus" class="size-4" /> Nueva mesa
        </button>
      </div>

      <%!-- Floor map canvas --%>
      <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm overflow-hidden">
        <%!-- Map area --%>
        <div
          id="floor-map"
          phx-hook="FloorMapEditor"
          class="relative w-full select-none aspect-square sm:aspect-video"
          style="background-image: radial-gradient(circle, oklch(80% 0.02 78) 1px, transparent 1px); background-size: 32px 32px;"
        >
          <%= if @tables == [] do %>
            <%!-- Empty state overlay --%>
            <div class="absolute inset-0 flex flex-col items-center justify-center gap-3 pointer-events-none">
              <.icon name="hero-table-cells" class="size-12 text-base-content/15" />
              <p class="text-base-content/40 text-sm font-medium">Aún no hay mesas</p>
              <p class="text-base-content/30 text-xs">Usa el botón "Nueva mesa" para agregar</p>
            </div>
          <% end %>

          <%= for table <- @tables do %>
            <div
              data-table-id={table.id}
              class="absolute -translate-x-1/2 -translate-y-1/2 cursor-grab active:cursor-grabbing group"
              style={"left: #{table.x_pct}%; top: #{table.y_pct}%"}
            >
              <%!-- Edit button (visible on hover / tap) --%>
              <button
                data-no-drag
                phx-click="edit_table"
                phx-value-id={table.id}
                class="absolute -top-1 -right-1 z-10 size-5 rounded-full bg-base-100 border border-base-300 shadow-sm
                       flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity"
                title="Editar mesa"
              >
                <.icon name="hero-pencil-square" class="size-3 text-base-content/60" />
              </button>

              <%!-- Table + chairs --%>
              <% active = table.is_active
                 chip_cls  = if active, do: "bg-primary text-primary-content border-primary/40", else: "bg-base-200 text-base-content/40 border-base-300"
                 chair_cls = if active, do: "bg-primary/55", else: "bg-base-300"
              %>
              <% {ch_top, ch_bot, ch_left, ch_right} = chair_distribution(table.capacity) %>
              <div class="relative w-20 h-20">
                <%!-- Top chairs --%>
                <%= if ch_top > 0 do %>
                  <div class="absolute top-0 left-1/2 -translate-x-1/2 flex gap-1">
                    <%= for _ <- 1..ch_top do %>
                      <div class={"w-5 h-3 rounded-t-xl #{chair_cls}"} />
                    <% end %>
                  </div>
                <% end %>
                <%!-- Bottom chairs --%>
                <%= if ch_bot > 0 do %>
                  <div class="absolute bottom-0 left-1/2 -translate-x-1/2 flex gap-1">
                    <%= for _ <- 1..ch_bot do %>
                      <div class={"w-5 h-3 rounded-b-xl #{chair_cls}"} />
                    <% end %>
                  </div>
                <% end %>
                <%!-- Left chair --%>
                <%= if ch_left > 0 do %>
                  <div class={"absolute left-0 top-1/2 -translate-y-1/2 w-3 h-9 rounded-l-xl #{chair_cls}"} />
                <% end %>
                <%!-- Right chair --%>
                <%= if ch_right > 0 do %>
                  <div class={"absolute right-0 top-1/2 -translate-y-1/2 w-3 h-9 rounded-r-xl #{chair_cls}"} />
                <% end %>
                <%!-- Table chip --%>
                <div class={"absolute inset-3 rounded-2xl flex flex-col items-center justify-center shadow-md border-2 #{chip_cls}"}>
                  <span class="text-xl font-bold leading-none">{table.number}</span>
                  <%= if table.label && table.label != "" do %>
                    <span class="text-[9px] leading-tight truncate w-10 text-center px-0.5 mt-0.5 opacity-75">
                      {table.label}
                    </span>
                  <% end %>
                </div>
              </div>
            </div>
          <% end %>
        </div>

        <%!-- Legend --%>
        <div class="px-5 py-3 border-t border-base-200 flex flex-wrap items-center gap-4 text-xs text-base-content/50">
          <span class="flex items-center gap-1.5">
            <span class="size-3 rounded bg-primary inline-block" /> Activa
          </span>
          <span class="flex items-center gap-1.5">
            <span class="size-3 rounded bg-base-300 inline-block" /> Inactiva
          </span>
          <span class="hidden sm:inline">· Toca el ✏️ para editar · Arrastra para mover</span>
        </div>
      </div>

      <%!-- Table list — accessible fallback + mobile --%>
      <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm overflow-hidden">
        <div class="px-5 py-3 border-b border-base-200 flex items-center gap-2">
          <.icon name="hero-list-bullet" class="size-4 text-base-content/40" />
          <h3 class="font-semibold text-sm text-base-content">Lista de mesas</h3>
        </div>

        <%= if @tables == [] do %>
          <div class="py-10 text-center text-sm text-base-content/40">
            Sin mesas registradas
          </div>
        <% else %>
          <%!-- Desktop table --%>
          <div class="hidden sm:block overflow-x-auto">
            <table class="table table-sm w-full">
              <thead>
                <tr class="text-base-content/50 text-xs uppercase">
                  <th class="w-16">#</th>
                  <th>Etiqueta</th>
                  <th class="w-20 text-center">Personas</th>
                  <th class="w-24 text-center">Estado</th>
                  <th class="w-28"></th>
                </tr>
              </thead>
              <tbody>
                <%= for table <- @tables do %>
                  <tr class="hover:bg-base-200/50">
                    <td class="font-bold text-base-content">{table.number}</td>
                    <td class="text-base-content/70">{table.label || "—"}</td>
                    <td class="text-center text-base-content/60">{table.capacity || "—"}</td>
                    <td class="text-center">
                      <span class={if table.is_active, do: "badge badge-sm badge-success", else: "badge badge-sm badge-ghost"}>
                        {if table.is_active, do: "Activa", else: "Inactiva"}
                      </span>
                    </td>
                    <td class="text-right">
                      <button
                        class="btn btn-xs btn-ghost"
                        phx-click="edit_table"
                        phx-value-id={table.id}
                      >
                        Editar
                      </button>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
          <%!-- Mobile cards --%>
          <div class="sm:hidden divide-y divide-base-200">
            <%= for table <- @tables do %>
              <div class="flex items-center gap-3 px-4 py-3">
                <div class={[
                  "size-10 rounded-xl flex items-center justify-center text-sm font-bold shrink-0",
                  if(table.is_active,
                    do: "bg-primary text-primary-content",
                    else: "bg-base-200 text-base-content/40"
                  )
                ]}>
                  {table.number}
                </div>
                <div class="flex-1 min-w-0">
                  <p class="text-sm font-semibold text-base-content">
                    Mesa {table.number}{if table.label && table.label != "", do: " · #{table.label}"}
                  </p>
                  <p class="text-xs text-base-content/50">
                    {if table.capacity, do: "#{table.capacity} personas · ", else: ""}
                    {if table.is_active, do: "Activa", else: "Inactiva"}
                  </p>
                </div>
                <button
                  class="btn btn-xs btn-ghost shrink-0"
                  phx-click="edit_table"
                  phx-value-id={table.id}
                >
                  <.icon name="hero-pencil-square" class="size-4" />
                </button>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>

    <%!-- Create / Edit modal --%>
    <%= if @show_modal do %>
      <div class="fixed inset-0 z-50">
        <div class="absolute inset-0 bg-black/50" phx-click="close_modal" />
        <div class="relative z-10 flex items-center justify-center min-h-full px-4 pointer-events-none">
          <div class="bg-base-100 rounded-2xl shadow-xl w-full max-w-md p-6 space-y-4 pointer-events-auto">
            <%!-- Modal header --%>
            <div class="flex items-center justify-between">
              <h2 class="text-lg font-bold text-base-content">
                {if @editing_table, do: "Editar mesa #{@editing_table.number}", else: "Nueva mesa"}
              </h2>
              <button class="btn btn-sm btn-ghost btn-circle" phx-click="close_modal">
                <.icon name="hero-x-mark" class="size-5" />
              </button>
            </div>

            <.form for={@form} phx-change="validate" phx-submit="save" class="space-y-4">
              <%!-- Number + Label row --%>
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div>
                  <label class="label pb-1">
                    <span class="label-text text-xs font-semibold">Número de mesa *</span>
                  </label>
                  <.input
                    field={@form[:number]}
                    type="number"
                    placeholder="1"
                    min="1"
                    class="input input-bordered w-full"
                  />
                </div>
                <div>
                  <label class="label pb-1">
                    <span class="label-text text-xs font-semibold">Etiqueta (opcional)</span>
                  </label>
                  <.input
                    field={@form[:label]}
                    type="text"
                    placeholder="Terraza, Ventana…"
                    class="input input-bordered w-full"
                  />
                </div>
              </div>

              <%!-- Capacity --%>
              <div>
                <label class="label pb-1">
                  <span class="label-text text-xs font-semibold">Capacidad (personas, opcional)</span>
                </label>
                <.input
                  field={@form[:capacity]}
                  type="number"
                  placeholder="4"
                  min="1"
                  class="input input-bordered w-full"
                />
              </div>

              <%!-- Active toggle --%>
              <div class="flex items-center gap-3">
                <.input
                  field={@form[:is_active]}
                  type="checkbox"
                  class="toggle toggle-primary toggle-sm"
                />
                <label class="text-sm text-base-content cursor-pointer">Mesa activa (visible para meseros)</label>
              </div>

              <%!-- Delete confirmation (only in edit mode) --%>
              <%= if @editing_table do %>
                <div class="pt-1 border-t border-base-200">
                  <%= if @confirm_delete_id == @editing_table.id do %>
                    <p class="text-xs text-error mb-2">¿Confirmar eliminación? Esta acción no se puede deshacer.</p>
                    <div class="flex gap-2">
                      <button
                        type="button"
                        class="btn btn-xs btn-error flex-1"
                        phx-click="delete_table"
                        phx-value-id={@editing_table.id}
                      >
                        Sí, eliminar
                      </button>
                      <button
                        type="button"
                        class="btn btn-xs btn-ghost flex-1"
                        phx-click="close_modal"
                      >
                        Cancelar
                      </button>
                    </div>
                  <% else %>
                    <button
                      type="button"
                      class="btn btn-xs btn-ghost text-error gap-1"
                      phx-click="confirm_delete"
                      phx-value-id={@editing_table.id}
                    >
                      <.icon name="hero-trash" class="size-3" /> Eliminar mesa
                    </button>
                  <% end %>
                </div>
              <% end %>

              <%!-- Actions --%>
              <div class="flex gap-2 pt-1">
                <button type="button" class="btn btn-ghost flex-1" phx-click="close_modal">
                  Cancelar
                </button>
                <button type="submit" class="btn btn-primary flex-1">
                  {if @editing_table, do: "Guardar cambios", else: "Crear mesa"}
                </button>
              </div>
            </.form>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # {top, bottom, left, right} chair counts for a given capacity.
  # nil capacity defaults to 4 chairs (2+2).
  defp chair_distribution(nil), do: {2, 2, 0, 0}
  defp chair_distribution(1),   do: {1, 0, 0, 0}
  defp chair_distribution(2),   do: {1, 1, 0, 0}
  defp chair_distribution(3),   do: {2, 1, 0, 0}
  defp chair_distribution(4),   do: {2, 2, 0, 0}
  defp chair_distribution(5),   do: {2, 2, 1, 0}
  defp chair_distribution(6),   do: {2, 2, 1, 1}
  defp chair_distribution(7),   do: {3, 2, 1, 1}
  defp chair_distribution(8),   do: {3, 3, 1, 1}
  defp chair_distribution(_),   do: {3, 3, 1, 1}

  defp next_available_number(tables) do
    used = MapSet.new(tables, & &1.number)
    Enum.find(1..100, 1, &(not MapSet.member?(used, &1)))
  end

  # Spread new tables in a zigzag grid so they don't all land on top of each other
  defp spread_position(count) do
    cols = 5
    col = rem(count, cols)
    row = div(count, cols)
    x = 15 + col * 16.0
    y = 20 + row * 25.0
    {x, y}
  end
end
