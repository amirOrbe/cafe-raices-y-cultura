defmodule CRCWeb.Admin.ProductCategoriesLive do
  use CRCWeb, :live_view

  alias CRC.Inventory
  alias CRC.Inventory.ProductCategory

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Categorías de insumos · Admin")
      |> assign(:categories, Inventory.list_product_categories_with_count())
      |> assign(:modal, nil)
      |> assign(:form, nil)

    {:ok, socket}
  end

  @impl true
  def handle_event("new_category", _params, socket) do
    changeset = Inventory.change_product_category(%ProductCategory{})

    {:noreply,
     socket
     |> assign(:modal, :new)
     |> assign(:form, to_form(changeset))}
  end

  def handle_event("edit_category", %{"id" => id}, socket) do
    category = Inventory.get_product_category!(String.to_integer(id))
    changeset = Inventory.change_product_category(category)

    {:noreply,
     socket
     |> assign(:modal, {:edit, category})
     |> assign(:form, to_form(changeset))}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, modal: nil, form: nil)}
  end

  def handle_event("save_category", %{"product_category" => params}, socket) do
    result =
      case socket.assigns.modal do
        :new -> Inventory.create_product_category(params)
        {:edit, cat} -> Inventory.update_product_category(cat, params)
      end

    case result do
      {:ok, _category} ->
        label = if socket.assigns.modal == :new, do: "creada", else: "actualizada"

        {:noreply,
         socket
         |> put_flash(:info, "Categoría #{label} correctamente.")
         |> assign(:categories, Inventory.list_product_categories_with_count())
         |> assign(:modal, nil)
         |> assign(:form, nil)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("delete_category", %{"id" => id}, socket) do
    category = Inventory.get_product_category!(String.to_integer(id))

    case Inventory.delete_product_category(category) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Categoría eliminada correctamente.")
         |> assign(:categories, Inventory.list_product_categories_with_count())}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "No se pudo eliminar la categoría.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 class="text-2xl font-bold text-base-content">Categorías de insumos</h1>
          <p class="text-sm text-base-content/50 mt-0.5">{length(@categories)} categorías registradas</p>
        </div>
        <button class="btn btn-primary gap-2" phx-click="new_category">
          <.icon name="hero-plus" class="size-4" />
          Nueva categoría
        </button>
      </div>

      <%= if @categories == [] do %>
        <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm py-16 text-center">
          <.icon name="hero-tag" class="size-10 text-base-content/20 mx-auto mb-3" />
          <p class="text-base-content/50 text-sm">No hay categorías registradas.</p>
          <p class="text-base-content/30 text-xs mt-1">Crea la primera para organizar tus insumos.</p>
        </div>
      <% else %>
        <%!-- ── Mobile card list (< md) ──────────────────────────────────────── --%>
        <div class="md:hidden flex flex-col gap-2">
          <%= for cat <- @categories do %>
            <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm p-3 flex items-center gap-3">
              <div class="flex items-center justify-center w-10 h-10 rounded-xl bg-primary/10 shrink-0">
                <.icon name="hero-tag" class="size-5 text-primary" />
              </div>
              <div class="flex-1 min-w-0">
                <p class="font-semibold text-sm text-base-content truncate">{cat.name}</p>
                <p class="text-xs text-base-content/50 mt-0.5">
                  {cat.product_count} {if cat.product_count == 1, do: "insumo", else: "insumos"}
                </p>
              </div>
              <div class="flex flex-col items-center gap-1 shrink-0">
                <button
                  class="btn btn-ghost btn-xs btn-circle"
                  phx-click="edit_category"
                  phx-value-id={cat.id}
                  title="Editar"
                >
                  <.icon name="hero-pencil" class="size-4" />
                </button>
                <button
                  class="btn btn-ghost btn-xs btn-circle text-error"
                  phx-click="delete_category"
                  phx-value-id={cat.id}
                  title="Eliminar"
                  data-confirm={
                    if cat.product_count > 0,
                      do: "Esta categoría tiene #{cat.product_count} insumo(s). Al eliminarla quedarán sin categoría. ¿Continuar?",
                      else: "¿Eliminar la categoría \"#{cat.name}\"?"
                  }
                >
                  <.icon name="hero-trash" class="size-4" />
                </button>
              </div>
            </div>
          <% end %>
        </div>

        <%!-- ── Desktop table (md+) ────────────────────────────────────────────── --%>
        <div class="hidden md:block bg-base-100 rounded-2xl border border-base-300 shadow-sm overflow-hidden">
          <div class="overflow-x-auto">
            <table class="table table-zebra table-fixed w-full">
              <thead>
                <tr class="bg-base-200 text-xs font-semibold text-base-content/60 uppercase tracking-wider">
                  <th class="w-[65%]">Nombre</th>
                  <th class="w-[15%] text-center">Insumos</th>
                  <th class="w-[20%] text-right">Acciones</th>
                </tr>
              </thead>
              <tbody>
                <%= for cat <- @categories do %>
                  <tr class="hover:bg-base-200/50 transition-colors">
                    <td class="font-medium text-sm text-base-content">{cat.name}</td>
                    <td class="text-center">
                      <span class="badge badge-sm badge-ghost">{cat.product_count}</span>
                    </td>
                    <td>
                      <div class="flex items-center justify-end gap-1">
                        <button
                          class="btn btn-ghost btn-xs btn-circle"
                          phx-click="edit_category"
                          phx-value-id={cat.id}
                          title="Editar"
                        >
                          <.icon name="hero-pencil" class="size-4" />
                        </button>
                        <button
                          class="btn btn-ghost btn-xs btn-circle text-error"
                          phx-click="delete_category"
                          phx-value-id={cat.id}
                          title="Eliminar"
                          data-confirm={
                            if cat.product_count > 0,
                              do: "Esta categoría tiene #{cat.product_count} insumo(s). Al eliminarla quedarán sin categoría. ¿Continuar?",
                              else: "¿Eliminar la categoría \"#{cat.name}\"?"
                          }
                        >
                          <.icon name="hero-trash" class="size-4" />
                        </button>
                      </div>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
      <% end %>
    </div>

    <%= if @modal != nil do %>
      <.category_modal form={@form} modal={@modal} />
    <% end %>
    """
  end

  attr :form, :map, required: true
  attr :modal, :any, required: true

  defp category_modal(assigns) do
    title = if assigns.modal == :new, do: "Nueva categoría", else: "Editar categoría"
    assigns = assign(assigns, :title, title)

    ~H"""
    <div
      id="category-modal"
      class="fixed inset-0 z-50 flex items-center justify-center p-4"
      phx-window-keydown="close_modal"
      phx-key="Escape"
    >
      <div class="absolute inset-0 bg-black/50 backdrop-blur-sm" phx-click="close_modal"></div>

      <div class="relative bg-base-100 rounded-2xl shadow-2xl w-full max-w-sm overflow-y-auto max-h-[90vh]">
        <div class="px-6 py-4 border-b border-base-300 flex items-center justify-between">
          <h2 class="text-lg font-semibold text-base-content">{@title}</h2>
          <button class="btn btn-ghost btn-sm btn-circle" phx-click="close_modal">
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>

        <div class="px-6 py-5">
          <.form id="category-form" for={@form} phx-submit="save_category" class="space-y-4">
            <.input
              field={@form[:name]}
              type="text"
              label="Nombre de la categoría"
              placeholder="Ej. Lácteos, Bebidas, Limpieza..."
            />
            <div class="flex justify-end gap-3 pt-2">
              <button type="button" class="btn btn-ghost" phx-click="close_modal">Cancelar</button>
              <button type="submit" class="btn btn-primary">
                {if @modal == :new, do: "Crear categoría", else: "Guardar cambios"}
              </button>
            </div>
          </.form>
        </div>
      </div>
    </div>
    """
  end
end
