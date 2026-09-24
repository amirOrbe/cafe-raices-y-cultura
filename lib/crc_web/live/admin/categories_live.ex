defmodule CRCWeb.Admin.CategoriesLive do
  use CRCWeb, :live_view

  alias CRC.Catalog
  alias CRC.Catalog.Category

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Categorías de platillos · Admin")
      |> assign(:categories, list_categories_with_count())
      |> assign(:modal, nil)
      |> assign(:form, nil)

    {:ok, socket}
  end

  @impl true
  def handle_event("new_category", _params, socket) do
    changeset = Catalog.change_category(%Category{})

    {:noreply,
     socket
     |> assign(:modal, :new)
     |> assign(:form, to_form(changeset))}
  end

  def handle_event("edit_category", %{"id" => id}, socket) do
    category = Catalog.get_category!(String.to_integer(id))
    changeset = Catalog.change_category(category)

    {:noreply,
     socket
     |> assign(:modal, {:edit, category})
     |> assign(:form, to_form(changeset))}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, modal: nil, form: nil)}
  end

  def handle_event("save_category", %{"category" => params}, socket) do
    result =
      case socket.assigns.modal do
        :new -> Catalog.create_category(params)
        {:edit, cat} -> Catalog.update_category(cat, params)
      end

    case result do
      {:ok, _category} ->
        label = if socket.assigns.modal == :new, do: "creada", else: "actualizada"

        {:noreply,
         socket
         |> put_flash(:info, "Categoría #{label} correctamente.")
         |> assign(:categories, list_categories_with_count())
         |> assign(:modal, nil)
         |> assign(:form, nil)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("toggle_active", %{"id" => id}, socket) do
    category = Catalog.get_category!(String.to_integer(id))

    case Catalog.update_category(category, %{active: !category.active}) do
      {:ok, _} ->
        action = if category.active, do: "desactivada", else: "activada"

        {:noreply,
         socket
         |> put_flash(:info, "Categoría #{action} correctamente.")
         |> assign(:categories, list_categories_with_count())}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "No se pudo cambiar el estado.")}
    end
  end

  def handle_event("delete_category", %{"id" => id}, socket) do
    category = Catalog.get_category!(String.to_integer(id))

    case Catalog.delete_category(category) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Categoría eliminada correctamente.")
         |> assign(:categories, list_categories_with_count())}

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
          <h1 class="text-2xl font-bold text-base-content">Categorías de platillos</h1>
          <p class="text-sm text-base-content/50 mt-0.5">
            {length(@categories)} categorías registradas
          </p>
        </div>
        <button class="btn btn-primary gap-2" phx-click="new_category">
          <.icon name="hero-plus" class="size-4" /> Nueva categoría
        </button>
      </div>

      <%= if @categories == [] do %>
        <.panel class="py-16 text-center">
          <.icon name="hero-squares-2x2" class="size-10 text-base-content/20 mx-auto mb-3" />
          <p class="text-base-content/50 text-sm">No hay categorías registradas.</p>
          <p class="text-base-content/30 text-xs mt-1">
            Crea la primera para poder agregar platillos al menú.
          </p>
        </.panel>
      <% else %>
        <%!-- ── Mobile card list (< md) ──────────────────────────────────────── --%>
        <div class="md:hidden flex flex-col gap-2">
          <%= for cat <- @categories do %>
            <.panel class="p-3 flex items-center gap-3">
              <div class="flex items-center justify-center w-10 h-10 rounded-xl bg-primary/10 shrink-0">
                <.icon name="hero-squares-2x2" class="size-5 text-primary" />
              </div>
              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-2">
                  <p class="font-semibold text-sm text-base-content truncate">{cat.name}</p>
                  <.admin_badge
                    variant={if cat.active, do: :success, else: :error}
                    size="xs"
                    class="shrink-0"
                  >
                    {if cat.active, do: "Activa", else: "Inactiva"}
                  </.admin_badge>
                </div>
                <p class="text-xs text-base-content/50 mt-0.5">
                  {cat.item_count} {if cat.item_count == 1, do: "platillo", else: "platillos"}
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
                  class={[
                    "btn btn-ghost btn-xs btn-circle",
                    if(cat.active, do: "text-warning", else: "text-success")
                  ]}
                  phx-click="toggle_active"
                  phx-value-id={cat.id}
                  title={if cat.active, do: "Desactivar", else: "Activar"}
                >
                  <.icon name={if cat.active, do: "hero-eye-slash", else: "hero-eye"} class="size-4" />
                </button>
                <button
                  class="btn btn-ghost btn-xs btn-circle text-error"
                  phx-click="delete_category"
                  phx-value-id={cat.id}
                  title="Eliminar"
                  data-confirm={
                    if cat.item_count > 0,
                      do:
                        "Esta categoría tiene #{cat.item_count} platillo(s). Al eliminarla se eliminarán también. ¿Continuar?",
                      else: "¿Eliminar la categoría \"#{cat.name}\"?"
                  }
                >
                  <.icon name="hero-trash" class="size-4" />
                </button>
              </div>
            </.panel>
          <% end %>
        </div>

        <%!-- ── Desktop table (md+) ────────────────────────────────────────────── --%>
        <.panel class="hidden md:block overflow-hidden">
          <div class="overflow-x-auto">
            <table class="table table-zebra table-fixed w-full">
              <.admin_table_head>
                <:col class="w-[55%]">Nombre</:col>
                <:col class="w-[15%] text-center">Platillos</:col>
                <:col class="w-[15%]">Estado</:col>
                <:col class="w-[15%] text-right">Acciones</:col>
              </.admin_table_head>
              <tbody>
                <%= for cat <- @categories do %>
                  <tr class="hover:bg-base-200/50 transition-colors">
                    <td class="font-medium text-sm text-base-content">{cat.name}</td>
                    <td class="text-center">
                      <span class="badge badge-sm badge-ghost">{cat.item_count}</span>
                    </td>
                    <td>
                      <.admin_badge variant={if cat.active, do: :success, else: :error}>
                        {if cat.active, do: "Activa", else: "Inactiva"}
                      </.admin_badge>
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
                          class={[
                            "btn btn-ghost btn-xs btn-circle",
                            if(cat.active, do: "text-warning", else: "text-success")
                          ]}
                          phx-click="toggle_active"
                          phx-value-id={cat.id}
                          title={if cat.active, do: "Desactivar", else: "Activar"}
                        >
                          <.icon
                            name={if cat.active, do: "hero-eye-slash", else: "hero-eye"}
                            class="size-4"
                          />
                        </button>
                        <button
                          class="btn btn-ghost btn-xs btn-circle text-error"
                          phx-click="delete_category"
                          phx-value-id={cat.id}
                          title="Eliminar"
                          data-confirm={
                            if cat.item_count > 0,
                              do:
                                "Esta categoría tiene #{cat.item_count} platillo(s). Al eliminarla se eliminarán también. ¿Continuar?",
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
        </.panel>
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
    <.admin_modal id="category-modal" size="sm" on_close="close_modal">
      <:title>{@title}</:title>
      <.form id="category-form" for={@form} phx-submit="save_category" class="space-y-4">
        <.input
          field={@form[:name]}
          type="text"
          label="Nombre de la categoría"
          placeholder="Ej. Café Filtrados, Sanduíses, Bebidas frías..."
        />
        <div class="flex justify-end gap-3 pt-2">
          <button type="button" class="btn btn-ghost" phx-click="close_modal">Cancelar</button>
          <button type="submit" class="btn btn-primary">
            {if @modal == :new, do: "Crear categoría", else: "Guardar cambios"}
          </button>
        </div>
      </.form>
    </.admin_modal>
    """
  end

  defp list_categories_with_count do
    import Ecto.Query
    alias CRC.Repo
    alias CRC.Catalog.{Category, MenuItem}

    Repo.all(
      from c in Category,
        left_join: m in MenuItem,
        on: m.category_id == c.id,
        group_by: c.id,
        select: %{
          id: c.id,
          name: c.name,
          active: c.active,
          slug: c.slug,
          item_count: count(m.id)
        },
        order_by: [asc: c.name]
    )
  end
end
