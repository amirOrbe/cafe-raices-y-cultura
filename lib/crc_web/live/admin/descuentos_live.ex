defmodule CRCWeb.Admin.DescuentosLive do
  use CRCWeb, :live_view

  alias CRC.Settings
  alias CRC.Settings.Discount

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Descuentos · Admin")
      |> assign(:discounts, Settings.list_discounts())
      |> assign(:modal, nil)
      |> assign(:form, nil)

    {:ok, socket}
  end

  @impl true
  def handle_event("new_discount", _params, socket) do
    changeset = Settings.change_discount(%Discount{})

    {:noreply,
     socket
     |> assign(:modal, :new)
     |> assign(:form, to_form(changeset))}
  end

  def handle_event("edit_discount", %{"id" => id}, socket) do
    discount = Settings.get_discount!(String.to_integer(id))
    changeset = Settings.change_discount(discount)

    {:noreply,
     socket
     |> assign(:modal, {:edit, discount})
     |> assign(:form, to_form(changeset))}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, modal: nil, form: nil)}
  end

  def handle_event("save_discount", %{"discount" => params}, socket) do
    result =
      case socket.assigns.modal do
        :new -> Settings.create_discount(params)
        {:edit, discount} -> Settings.update_discount(discount, params)
      end

    case result do
      {:ok, _} ->
        label = if socket.assigns.modal == :new, do: "creado", else: "actualizado"

        {:noreply,
         socket
         |> put_flash(:info, "Descuento #{label} correctamente.")
         |> assign(:discounts, Settings.list_discounts())
         |> assign(:modal, nil)
         |> assign(:form, nil)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("toggle_active", %{"id" => id}, socket) do
    discount = Settings.get_discount!(String.to_integer(id))

    case Settings.update_discount(discount, %{active: !discount.active}) do
      {:ok, _} ->
        action = if discount.active, do: "desactivado", else: "activado"

        {:noreply,
         socket
         |> put_flash(:info, "Descuento #{action} correctamente.")
         |> assign(:discounts, Settings.list_discounts())}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "No se pudo cambiar el estado.")}
    end
  end

  def handle_event("delete_discount", %{"id" => id}, socket) do
    discount = Settings.get_discount!(String.to_integer(id))

    case Settings.delete_discount(discount) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Descuento eliminado correctamente.")
         |> assign(:discounts, Settings.list_discounts())}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "No se pudo eliminar el descuento.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 class="text-2xl font-bold text-base-content">Descuentos</h1>
          <p class="text-sm text-base-content/50 mt-0.5">
            Los meseros pueden aplicar estos descuentos al cerrar una comanda.
          </p>
        </div>
        <button class="btn btn-primary gap-2" phx-click="new_discount">
          <.icon name="hero-plus" class="size-4" /> Nuevo descuento
        </button>
      </div>

      <%= if @discounts == [] do %>
        <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm py-16 text-center">
          <.icon name="hero-tag" class="size-10 text-base-content/20 mx-auto mb-3" />
          <p class="text-base-content/50 text-sm">No hay descuentos registrados.</p>
          <p class="text-base-content/30 text-xs mt-1">
            Crea uno para que los meseros puedan aplicarlo en las comandas.
          </p>
        </div>
      <% else %>
        <%!-- Mobile card list --%>
        <div class="md:hidden flex flex-col gap-2">
          <%= for d <- @discounts do %>
            <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm p-3 flex items-center gap-3">
              <div class="flex items-center justify-center w-10 h-10 rounded-xl bg-primary/10 shrink-0">
                <span class="font-bold text-primary text-sm">{d.percentage}%</span>
              </div>
              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-2">
                  <p class="font-semibold text-sm text-base-content truncate">{d.name}</p>
                  <%= if d.active do %>
                    <span class="badge badge-xs badge-success shrink-0">Activo</span>
                  <% else %>
                    <span class="badge badge-xs badge-error shrink-0">Inactivo</span>
                  <% end %>
                </div>
                <p class="text-xs text-base-content/50 mt-0.5">{d.percentage}% de descuento</p>
              </div>
              <div class="flex flex-col items-center gap-1 shrink-0">
                <button
                  class="btn btn-ghost btn-xs btn-circle"
                  phx-click="edit_discount"
                  phx-value-id={d.id}
                  title="Editar"
                >
                  <.icon name="hero-pencil" class="size-4" />
                </button>
                <button
                  class={[
                    "btn btn-ghost btn-xs btn-circle",
                    if(d.active, do: "text-warning", else: "text-success")
                  ]}
                  phx-click="toggle_active"
                  phx-value-id={d.id}
                  title={if d.active, do: "Desactivar", else: "Activar"}
                >
                  <.icon name={if d.active, do: "hero-eye-slash", else: "hero-eye"} class="size-4" />
                </button>
                <button
                  class="btn btn-ghost btn-xs btn-circle text-error"
                  phx-click="delete_discount"
                  phx-value-id={d.id}
                  title="Eliminar"
                  data-confirm={"¿Eliminar el descuento \"#{d.name}\"? Las comandas que ya lo tienen aplicado no se verán afectadas."}
                >
                  <.icon name="hero-trash" class="size-4" />
                </button>
              </div>
            </div>
          <% end %>
        </div>

        <%!-- Desktop table --%>
        <div class="hidden md:block bg-base-100 rounded-2xl border border-base-300 shadow-sm overflow-hidden">
          <div class="overflow-x-auto">
            <table class="table table-zebra table-fixed w-full">
              <thead>
                <tr class="bg-base-200 text-xs font-semibold text-base-content/60 uppercase tracking-wider">
                  <th class="w-[40%]">Nombre</th>
                  <th class="w-[20%] text-center">Porcentaje</th>
                  <th class="w-[20%]">Estado</th>
                  <th class="w-[20%] text-right">Acciones</th>
                </tr>
              </thead>
              <tbody>
                <%= for d <- @discounts do %>
                  <tr class="hover:bg-base-200/50 transition-colors">
                    <td class="font-medium text-sm text-base-content">{d.name}</td>
                    <td class="text-center">
                      <span class="badge badge-sm badge-primary">{d.percentage}%</span>
                    </td>
                    <td>
                      <%= if d.active do %>
                        <span class="badge badge-sm badge-success">Activo</span>
                      <% else %>
                        <span class="badge badge-sm badge-error">Inactivo</span>
                      <% end %>
                    </td>
                    <td>
                      <div class="flex items-center justify-end gap-1">
                        <button
                          class="btn btn-ghost btn-xs btn-circle"
                          phx-click="edit_discount"
                          phx-value-id={d.id}
                          title="Editar"
                        >
                          <.icon name="hero-pencil" class="size-4" />
                        </button>
                        <button
                          class={[
                            "btn btn-ghost btn-xs btn-circle",
                            if(d.active, do: "text-warning", else: "text-success")
                          ]}
                          phx-click="toggle_active"
                          phx-value-id={d.id}
                          title={if d.active, do: "Desactivar", else: "Activar"}
                        >
                          <.icon
                            name={if d.active, do: "hero-eye-slash", else: "hero-eye"}
                            class="size-4"
                          />
                        </button>
                        <button
                          class="btn btn-ghost btn-xs btn-circle text-error"
                          phx-click="delete_discount"
                          phx-value-id={d.id}
                          title="Eliminar"
                          data-confirm={"¿Eliminar el descuento \"#{d.name}\"? Las comandas que ya lo tienen aplicado no se verán afectadas."}
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
      <.discount_modal form={@form} modal={@modal} />
    <% end %>
    """
  end

  attr :form, :map, required: true
  attr :modal, :any, required: true

  defp discount_modal(assigns) do
    title = if assigns.modal == :new, do: "Nuevo descuento", else: "Editar descuento"
    assigns = assign(assigns, :title, title)

    ~H"""
    <div
      id="discount-modal"
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
          <.form id="discount-form" for={@form} phx-submit="save_discount" class="space-y-4">
            <.input
              field={@form[:name]}
              type="text"
              label="Nombre del descuento"
              placeholder="Ej. Descuento empleado, Promoción especial..."
            />
            <.input
              field={@form[:percentage]}
              type="number"
              label="Porcentaje (%)"
              placeholder="Ej. 10"
              min="1"
              max="100"
            />
            <div class="flex justify-end gap-3 pt-2">
              <button type="button" class="btn btn-ghost" phx-click="close_modal">Cancelar</button>
              <button type="submit" class="btn btn-primary">
                {if @modal == :new, do: "Crear descuento", else: "Guardar cambios"}
              </button>
            </div>
          </.form>
        </div>
      </div>
    </div>
    """
  end
end
