defmodule CRCWeb.ProduccionLive do
  @moduledoc """
  Staff production logging page — accessible to any authenticated user.

  Shows active production recipes and lets staff register batches.
  Each registration atomically deducts raw ingredients and adds the
  resulting product to stock.
  """

  use CRCWeb, :live_view

  import CRCWeb.Layouts, only: [flash_group: 1]

  alias CRC.Production
  alias CRCWeb.Components.SiteComponents

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Producción")
      |> assign(:recipes, Production.list_active_recipes())
      |> assign(:today_logs, Production.list_today_logs())
      |> assign(:selected_recipe, nil)
      |> assign(:batches_input, "1")
      |> assign(:notes_input, "")
      |> assign(:nav_open, false)

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("toggle_nav", _params, socket),
    do: {:noreply, update(socket, :nav_open, &(!&1))}

  def handle_event("close_nav", _params, socket),
    do: {:noreply, assign(socket, :nav_open, false)}

  def handle_event("select_recipe", %{"id" => id}, socket) do
    recipe = Enum.find(socket.assigns.recipes, &(to_string(&1.id) == id))
    {:noreply, assign(socket, :selected_recipe, recipe)}
  end

  def handle_event("clear_recipe", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_recipe, nil)
     |> assign(:batches_input, "1")
     |> assign(:notes_input, "")}
  end

  def handle_event("update_batches", %{"value" => v}, socket),
    do: {:noreply, assign(socket, :batches_input, v)}

  def handle_event("update_notes", %{"value" => v}, socket),
    do: {:noreply, assign(socket, :notes_input, v)}

  def handle_event("log_production", _params, socket) do
    recipe = socket.assigns.selected_recipe

    case Production.log_production(
           recipe.id,
           socket.assigns.batches_input,
           socket.assigns.current_user.id,
           socket.assigns.notes_input
         ) do
      {:ok, _log} ->
        {:noreply,
         socket
         |> assign(:selected_recipe, nil)
         |> assign(:batches_input, "1")
         |> assign(:notes_input, "")
         |> assign(:today_logs, Production.list_today_logs())
         |> put_flash(:info, "Lote registrado. Stock actualizado.")}

      {:error, :invalid_batches} ->
        {:noreply, put_flash(socket, :error, "La cantidad de lotes debe ser mayor a 0.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "No se pudo registrar. Intenta de nuevo.")}
    end
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <SiteComponents.site_navbar
      nav_open={@nav_open}
      current_page={:produccion}
      current_user={@current_user}
    />

    <div class="min-h-screen bg-base-200 pt-20 pb-12">
      <div class="max-w-2xl mx-auto px-4 space-y-6">

        <%!-- Header --%>
        <div class="flex items-center justify-between flex-wrap gap-2">
          <div>
            <div class="flex items-center gap-2 mb-0.5">
              <.icon name="hero-beaker" class="size-6 text-primary" />
              <h1 class="text-2xl font-bold text-base-content">Producción Interna</h1>
            </div>
            <p class="text-sm text-base-content/50">
              Registra un lote de producción — el sistema ajustará el stock automáticamente.
            </p>
          </div>
        </div>

        <%!-- Step 1: Select recipe (shown when none selected) --%>
        <%= if is_nil(@selected_recipe) do %>
          <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm p-5 space-y-4">
            <p class="text-sm font-semibold text-base-content">¿Qué vas a producir?</p>

            <%= if @recipes == [] do %>
              <div class="py-10 text-center text-base-content/40 text-sm">
                No hay recetas activas. Pide al administrador que cree una.
              </div>
            <% else %>
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <%= for recipe <- @recipes do %>
                  <button
                    class="text-left rounded-xl border border-base-300 bg-base-50 hover:border-primary/40 hover:bg-primary/5 p-4 transition-all group"
                    phx-click="select_recipe"
                    phx-value-id={recipe.id}
                  >
                    <p class="font-semibold text-sm text-base-content group-hover:text-primary transition-colors">
                      {recipe.name}
                    </p>
                    <p class="text-xs text-base-content/50 mt-1">
                      Produce {format_qty(recipe.yield_quantity)} {recipe.yield_unit}
                      de <span class="font-medium">{recipe.output_product && recipe.output_product.name}</span>
                    </p>
                    <div class="flex flex-wrap gap-1 mt-2">
                      <%= for ri <- recipe.recipe_ingredients do %>
                        <span class="badge badge-xs badge-ghost">
                          {ri.product && ri.product.name}
                        </span>
                      <% end %>
                    </div>
                  </button>
                <% end %>
              </div>
            <% end %>
          </div>

        <%!-- Step 2: Confirm batch (shown when recipe selected) --%>
        <% else %>
          <div class="bg-base-100 rounded-2xl border border-primary/30 shadow-sm p-5 space-y-5">
            <%!-- Recipe header --%>
            <div class="flex items-start justify-between gap-3">
              <div>
                <p class="text-xs text-base-content/50 uppercase tracking-wider mb-0.5">Receta seleccionada</p>
                <p class="text-lg font-bold text-base-content">{@selected_recipe.name}</p>
              </div>
              <button
                class="btn btn-ghost btn-sm btn-circle shrink-0"
                phx-click="clear_recipe"
              >
                <.icon name="hero-x-mark" class="size-4" />
              </button>
            </div>

            <%!-- Batch count input --%>
            <div class="form-control">
              <label class="label">
                <span class="label-text font-medium">¿Cuántos lotes hiciste?</span>
                <span class="label-text-alt text-base-content/40">1 = una receta completa</span>
              </label>
              <input
                type="number"
                min="0.1"
                step="0.1"
                class="input input-bordered w-full text-lg font-bold text-center"
                value={@batches_input}
                phx-blur="update_batches"
                phx-value-value={@batches_input}
                phx-debounce="300"
              />
            </div>

            <%!-- Preview: what will happen --%>
            <% batches_d = parse_batches(@batches_input) %>
            <div class="rounded-xl bg-base-200 p-4 space-y-2">
              <p class="text-xs font-semibold text-base-content/60 uppercase tracking-wider">
                Resumen del lote
              </p>
              <%!-- Ingredients consumed --%>
              <%= for ri <- @selected_recipe.recipe_ingredients do %>
                <div class="flex items-center justify-between text-sm">
                  <span class="text-base-content/70">
                    <.icon name="hero-minus-circle" class="size-3.5 text-error inline mr-1" />
                    {ri.product && ri.product.name}
                  </span>
                  <span class="font-medium text-error">
                    -{format_qty(Decimal.mult(ri.quantity, batches_d))} {ri.product && ri.product.unit}
                  </span>
                </div>
              <% end %>
              <%!-- Output produced --%>
              <div class="flex items-center justify-between text-sm border-t border-base-300 pt-2 mt-1">
                <span class="text-base-content/70">
                  <.icon name="hero-plus-circle" class="size-3.5 text-success inline mr-1" />
                  {@selected_recipe.output_product && @selected_recipe.output_product.name}
                </span>
                <span class="font-bold text-success">
                  +{format_qty(Decimal.mult(@selected_recipe.yield_quantity, batches_d))}
                  {@selected_recipe.yield_unit}
                </span>
              </div>
            </div>

            <%!-- Notes --%>
            <div class="form-control">
              <label class="label">
                <span class="label-text font-medium">Notas</span>
                <span class="label-text-alt text-base-content/40">Opcional</span>
              </label>
              <textarea
                class="textarea textarea-bordered w-full text-sm"
                rows="2"
                placeholder="Ej: Se usaron naranjas de la caja nueva"
                phx-keyup="update_notes"
                phx-value-value={@notes_input}
                phx-debounce="300"
              >{@notes_input}</textarea>
            </div>

            <%!-- Submit --%>
            <button
              class="btn btn-primary w-full"
              phx-click="log_production"
            >
              <.icon name="hero-check" class="size-5" />
              Registrar lote
            </button>
          </div>
        <% end %>

        <%!-- Today's log --%>
        <div>
          <h2 class="text-xs font-semibold text-base-content/50 uppercase tracking-wider mb-3 flex items-center gap-2">
            Producción de hoy
            <%= if @today_logs != [] do %>
              <span class="badge badge-ghost badge-sm">{length(@today_logs)}</span>
            <% end %>
          </h2>

          <%= if @today_logs == [] do %>
            <div class="bg-base-100 rounded-2xl border border-base-300 py-10 text-center text-sm text-base-content/40">
              Sin producción registrada hoy.
            </div>
          <% else %>
            <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm divide-y divide-base-200">
              <%= for log <- @today_logs do %>
                <div class="px-4 py-3 flex items-center gap-3">
                  <div class="flex-1 min-w-0">
                    <p class="text-sm font-semibold text-base-content truncate">
                      {log.recipe && log.recipe.name}
                    </p>
                    <p class="text-xs text-base-content/50 mt-0.5">
                      {log.produced_by && log.produced_by.name}
                      · {format_dt(log.produced_at)}
                      {if log.notes && log.notes != "", do: " · #{log.notes}"}
                    </p>
                  </div>
                  <span class="badge badge-success badge-sm shrink-0">
                    {format_qty(log.batches)} {if Decimal.compare(log.batches, Decimal.new(1)) == :eq, do: "lote", else: "lotes"}
                  </span>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>

      </div>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp parse_batches(str) do
    case Decimal.parse(str || "1") do
      {d, _} ->
        if Decimal.compare(d, Decimal.new(0)) == :gt, do: d, else: Decimal.new(1)

      _ ->
        Decimal.new(1)
    end
  end

  defp format_qty(nil), do: "0"
  defp format_qty(%Decimal{} = d) do
    abs = Decimal.abs(d)
    if Decimal.integer?(abs),
      do: abs |> Decimal.to_integer() |> to_string(),
      else: abs |> Decimal.round(3) |> Decimal.to_string() |> String.trim_trailing("0") |> String.trim_trailing(".")
  end
  defp format_qty(v), do: to_string(v)

  defp format_dt(%DateTime{} = dt), do: Calendar.strftime(dt, "%H:%M")
  defp format_dt(_), do: "—"
end
