defmodule CRCWeb.Admin.SuppliersLive do
  @moduledoc "Supplier management from the administration panel."

  use CRCWeb, :live_view

  alias CRC.Inventory
  alias CRC.Inventory.Supplier

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(CRC.PubSub, "admin:suppliers")

    socket =
      socket
      |> assign(:page_title, "Proveedores · Admin")
      |> assign(:suppliers, Inventory.list_suppliers())
      |> assign(:status_filter, :active)
      |> assign(:modal, nil)
      |> assign(:form, nil)

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # PubSub
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:supplier_changed, _supplier}, socket) do
    {:noreply, assign(socket, :suppliers, Inventory.list_suppliers())}
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("set_status_filter", %{"status" => status}, socket) do
    {:noreply, assign(socket, :status_filter, String.to_existing_atom(status))}
  end

  def handle_event("new_supplier", _params, socket) do
    changeset = Inventory.change_supplier(%Supplier{})

    {:noreply,
     socket
     |> assign(:modal, :new)
     |> assign(:form, to_form(changeset))}
  end

  def handle_event("edit_supplier", %{"id" => id}, socket) do
    supplier = Inventory.get_supplier!(String.to_integer(id))
    changeset = Inventory.change_supplier(supplier)

    {:noreply,
     socket
     |> assign(:modal, {:edit, supplier})
     |> assign(:form, to_form(changeset))}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, modal: nil, form: nil)}
  end

  def handle_event("save_supplier", %{"supplier" => params}, socket) do
    result =
      case socket.assigns.modal do
        :new -> Inventory.create_supplier(params)
        {:edit, supplier} -> Inventory.update_supplier(supplier, params)
      end

    case result do
      {:ok, _supplier} ->
        label = if socket.assigns.modal == :new, do: "creado", else: "actualizado"

        {:noreply,
         socket
         |> put_flash(:info, "Proveedor #{label} correctamente.")
         |> assign(:suppliers, Inventory.list_suppliers())
         |> assign(:modal, nil)
         |> assign(:form, nil)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("toggle_active", %{"id" => id}, socket) do
    supplier = Inventory.get_supplier!(String.to_integer(id))

    case Inventory.toggle_supplier_active(supplier) do
      {:ok, _} ->
        action = if supplier.active, do: "desactivado", else: "activado"

        {:noreply,
         socket
         |> put_flash(:info, "Proveedor #{action} correctamente.")
         |> assign(:suppliers, Inventory.list_suppliers())}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "No se pudo cambiar el estado del proveedor.")}
    end
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <% visible = filter_by_status(@suppliers, @status_filter) %>
    <% active_count = Enum.count(@suppliers, & &1.active) %>
    <% inactive_count = Enum.count(@suppliers, &(!&1.active)) %>
    <div class="space-y-6">
      <%!-- Header --%>
      <div class="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 class="text-2xl font-bold text-base-content">Proveedores</h1>
          <p class="text-sm text-base-content/50 mt-0.5">
            {length(visible)}
            {if length(visible) == 1, do: "proveedor", else: "proveedores"}
            {if @status_filter == :active, do: "activos", else: "inactivos"}
          </p>
        </div>
        <button class="btn btn-primary gap-2" phx-click="new_supplier">
          <.icon name="hero-plus" class="size-4" /> Nuevo proveedor
        </button>
      </div>

      <%!-- Status tabs --%>
      <div class="flex gap-2">
        <button
          class={[
            "btn btn-sm gap-1.5",
            if(@status_filter == :active, do: "btn-primary", else: "btn-ghost")
          ]}
          phx-click="set_status_filter"
          phx-value-status="active"
        >
          <.icon name="hero-check-circle" class="size-3.5" /> Activos
          <span class={[
            "badge badge-xs",
            if(@status_filter == :active, do: "badge-primary-content/30", else: "badge-ghost")
          ]}>
            {active_count}
          </span>
        </button>
        <button
          class={[
            "btn btn-sm gap-1.5",
            if(@status_filter == :inactive, do: "btn-error", else: "btn-ghost")
          ]}
          phx-click="set_status_filter"
          phx-value-status="inactive"
        >
          <.icon name="hero-x-circle" class="size-3.5" /> Inactivos
          <span class={[
            "badge badge-xs",
            if(@status_filter == :inactive, do: "badge-error-content/30", else: "badge-ghost")
          ]}>
            {inactive_count}
          </span>
        </button>
      </div>

      <%!-- ── Mobile card list (< md) ──────────────────────────────────────── --%>
      <div class="md:hidden flex flex-col gap-2">
        <%= if visible == [] do %>
          <div class="text-center py-12 text-base-content/40 text-sm bg-base-100 rounded-2xl border border-base-300">
            {if @status_filter == :active,
              do: "No hay proveedores activos.",
              else: "No hay proveedores inactivos."}
          </div>
        <% end %>
        <%= for supplier <- visible do %>
          <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm p-3 flex items-center gap-3">
            <div class="flex items-center justify-center w-10 h-10 rounded-xl bg-primary/10 shrink-0">
              <.icon name="hero-truck" class="size-5 text-primary" />
            </div>
            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-2">
                <p class="font-semibold text-sm text-base-content truncate">{supplier.name}</p>
                <%= if supplier.active do %>
                  <span class="badge badge-xs badge-success shrink-0">Activo</span>
                <% else %>
                  <span class="badge badge-xs badge-error shrink-0">Inactivo</span>
                <% end %>
              </div>
              <div class="flex items-center gap-2 mt-0.5 flex-wrap">
                <%= if supplier.contact_name do %>
                  <span class="text-xs text-base-content/60 truncate">{supplier.contact_name}</span>
                <% end %>
                <%= if supplier.phone do %>
                  <span class="text-xs text-base-content/40">{supplier.phone}</span>
                <% end %>
              </div>
              <%= if supplier.email do %>
                <p class="text-xs text-base-content/40 truncate mt-0.5">{supplier.email}</p>
              <% end %>
            </div>
            <div class="flex flex-col items-center gap-1 shrink-0">
              <button
                class="btn btn-ghost btn-xs btn-circle"
                phx-click="edit_supplier"
                phx-value-id={supplier.id}
                title="Editar"
              >
                <.icon name="hero-pencil" class="size-4" />
              </button>
              <button
                class={[
                  "btn btn-ghost btn-xs btn-circle",
                  if(supplier.active, do: "text-error", else: "text-success")
                ]}
                phx-click="toggle_active"
                phx-value-id={supplier.id}
                title={if supplier.active, do: "Desactivar", else: "Activar"}
              >
                <.icon
                  name={if supplier.active, do: "hero-no-symbol", else: "hero-check-circle"}
                  class="size-4"
                />
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
                <th class="w-[25%]">Nombre</th>
                <th class="w-[18%]">Contacto</th>
                <th class="w-[15%]">Teléfono</th>
                <th class="w-[25%]">Correo</th>
                <th class="w-[10%]">Estado</th>
                <th class="w-[7%] text-right">Acciones</th>
              </tr>
            </thead>
            <tbody>
              <%= for supplier <- visible do %>
                <tr class="hover:bg-base-200/50 transition-colors">
                  <td class="max-w-0 font-medium text-sm text-base-content truncate">
                    {supplier.name}
                  </td>
                  <td class="max-w-0 text-sm text-base-content/70 truncate">
                    {supplier.contact_name || "—"}
                  </td>
                  <td class="text-sm text-base-content/70">{supplier.phone || "—"}</td>
                  <td class="max-w-0 text-sm text-base-content/70 truncate">
                    {supplier.email || "—"}
                  </td>
                  <td>
                    <%= if supplier.active do %>
                      <span class="badge badge-sm badge-success">Activo</span>
                    <% else %>
                      <span class="badge badge-sm badge-error">Inactivo</span>
                    <% end %>
                  </td>
                  <td>
                    <div class="flex items-center justify-end gap-1">
                      <button
                        class="btn btn-ghost btn-xs btn-circle"
                        phx-click="edit_supplier"
                        phx-value-id={supplier.id}
                        title="Editar"
                      >
                        <.icon name="hero-pencil" class="size-4" />
                      </button>
                      <button
                        class={[
                          "btn btn-ghost btn-xs btn-circle",
                          if(supplier.active, do: "text-error", else: "text-success")
                        ]}
                        phx-click="toggle_active"
                        phx-value-id={supplier.id}
                        title={if supplier.active, do: "Desactivar", else: "Activar"}
                      >
                        <.icon
                          name={if supplier.active, do: "hero-no-symbol", else: "hero-check-circle"}
                          class="size-4"
                        />
                      </button>
                    </div>
                  </td>
                </tr>
              <% end %>
              <%= if visible == [] do %>
                <tr>
                  <td colspan="6" class="text-center py-12 text-base-content/40 text-sm">
                    {if @status_filter == :active,
                      do: "No hay proveedores activos.",
                      else: "No hay proveedores inactivos."}
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </div>

    <%!-- Modal: new / edit supplier --%>
    <%= if @modal != nil do %>
      <.supplier_modal form={@form} modal={@modal} />
    <% end %>
    """
  end

  # ---------------------------------------------------------------------------
  # Supplier modal
  # ---------------------------------------------------------------------------

  attr :form, :map, required: true
  attr :modal, :any, required: true

  defp supplier_modal(assigns) do
    title = if assigns.modal == :new, do: "Nuevo proveedor", else: "Editar proveedor"
    assigns = assign(assigns, :title, title)

    ~H"""
    <div
      id="supplier-modal"
      class="fixed inset-0 z-50 flex items-center justify-center p-4"
      phx-window-keydown="close_modal"
      phx-key="Escape"
    >
      <div class="absolute inset-0 bg-black/50 backdrop-blur-sm" phx-click="close_modal"></div>

      <div class="relative bg-base-100 rounded-2xl shadow-2xl w-full max-w-lg overflow-hidden">
        <div class="px-6 py-4 border-b border-base-300 flex items-center justify-between">
          <h2 class="text-lg font-semibold text-base-content">{@title}</h2>
          <button class="btn btn-ghost btn-sm btn-circle" phx-click="close_modal">
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>

        <div class="px-6 py-5">
          <.form id="supplier-form" for={@form} phx-submit="save_supplier" class="space-y-1">
            <.input
              field={@form[:name]}
              type="text"
              label="Nombre del proveedor"
              placeholder="Ej. Lala, La Costena, Distribuidora López"
            />
            <.input
              field={@form[:contact_name]}
              type="text"
              label="Persona de contacto (opcional)"
              placeholder="Ej. Carlos Mendoza"
            />
            <.input
              field={@form[:phone]}
              type="text"
              label="Teléfono (opcional)"
              placeholder="55 1234 5678"
            />
            <.input
              field={@form[:email]}
              type="email"
              label="Correo electrónico (opcional)"
              placeholder="contacto@proveedor.com"
            />
            <.input
              field={@form[:address]}
              type="text"
              label="Dirección (opcional)"
              placeholder="Calle, colonia, ciudad"
            />
            <.input
              field={@form[:notes]}
              type="textarea"
              label="Notas (opcional)"
              placeholder="Días de entrega, condiciones, observaciones..."
            />

            <div class="flex justify-end gap-3 pt-4">
              <button type="button" class="btn btn-ghost" phx-click="close_modal">Cancelar</button>
              <button type="submit" class="btn btn-primary">
                {if @modal == :new, do: "Crear proveedor", else: "Guardar cambios"}
              </button>
            </div>
          </.form>
        </div>
      </div>
    </div>
    """
  end

  defp filter_by_status(suppliers, :active), do: Enum.filter(suppliers, & &1.active)
  defp filter_by_status(suppliers, :inactive), do: Enum.filter(suppliers, &(!&1.active))
end
