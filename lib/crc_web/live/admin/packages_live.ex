defmodule CRCWeb.Admin.PackagesLive do
  use CRCWeb, :live_view

  alias CRC.Catalog
  alias CRC.Catalog.Package

  @impl true
  def mount(_params, _session, socket) do
    all_items = Catalog.list_all_menu_items()
    suggestions = Catalog.suggest_packages()

    socket =
      socket
      |> assign(:page_title, "Paquetes · Admin")
      |> assign(:packages, Catalog.list_all_packages())
      |> assign(:all_menu_items, all_items)
      |> assign(:suggestions, suggestions)
      |> assign(:modal, nil)
      |> assign(:form, nil)
      |> assign(:selected_items, [])

    {:ok, socket}
  end

  @impl true
  def handle_event("new_package", _params, socket) do
    changeset = Catalog.change_package(%Package{})

    {:noreply,
     socket
     |> assign(:modal, :new)
     |> assign(:form, to_form(changeset))
     |> assign(:selected_items, [])}
  end

  def handle_event("edit_package", %{"id" => id}, socket) do
    package = Catalog.get_package!(String.to_integer(id))
    changeset = Catalog.change_package(package)

    selected = Enum.map(package.package_items, fn pi ->
      %{menu_item_id: pi.menu_item_id, quantity: pi.quantity}
    end)

    {:noreply,
     socket
     |> assign(:modal, {:edit, package})
     |> assign(:form, to_form(changeset))
     |> assign(:selected_items, selected)}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, modal: nil, form: nil, selected_items: [])}
  end

  def handle_event("validate_package", %{"package" => params}, socket) do
    changeset =
      case socket.assigns.modal do
        :new -> Catalog.change_package(%Package{}, params)
        {:edit, pkg} -> Catalog.change_package(pkg, params)
      end
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("toggle_menu_item", %{"id" => id}, socket) do
    item_id = String.to_integer(id)
    selected = socket.assigns.selected_items

    updated =
      if Enum.any?(selected, &(&1.menu_item_id == item_id)) do
        Enum.reject(selected, &(&1.menu_item_id == item_id))
      else
        [%{menu_item_id: item_id, quantity: 1} | selected]
      end

    {:noreply, assign(socket, :selected_items, updated)}
  end

  def handle_event("update_item_qty", %{"id" => id, "qty" => qty_str}, socket) do
    item_id = String.to_integer(id)
    qty = max(1, String.to_integer(qty_str))

    updated =
      Enum.map(socket.assigns.selected_items, fn item ->
        if item.menu_item_id == item_id, do: %{item | quantity: qty}, else: item
      end)

    {:noreply, assign(socket, :selected_items, updated)}
  end

  def handle_event("save_package", %{"package" => params}, socket) do
    selected = socket.assigns.selected_items

    if Enum.empty?(selected) do
      {:noreply, put_flash(socket, :error, "Agrega al menos un platillo al paquete.")}
    else
      result =
        case socket.assigns.modal do
          :new ->
            with {:ok, package} <- Catalog.create_package(params),
                 {:ok, package} <- Catalog.set_package_items(package, selected) do
              {:ok, package}
            end

          {:edit, pkg} ->
            with {:ok, package} <- Catalog.update_package(pkg, params),
                 {:ok, package} <- Catalog.set_package_items(package, selected) do
              {:ok, package}
            end
        end

      case result do
        {:ok, _package} ->
          label = if socket.assigns.modal == :new, do: "creado", else: "actualizado"

          {:noreply,
           socket
           |> put_flash(:info, "Paquete #{label} correctamente.")
           |> assign(:packages, Catalog.list_all_packages())
           |> assign(:modal, nil)
           |> assign(:form, nil)
           |> assign(:selected_items, [])}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign(socket, :form, to_form(changeset))}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Error al guardar el paquete.")}
      end
    end
  end

  def handle_event("toggle_active", %{"id" => id}, socket) do
    package = Catalog.get_package!(String.to_integer(id))
    {:ok, updated} = Catalog.update_package(package, %{active: !package.active})
    label = if updated.active, do: "activado", else: "desactivado"

    {:noreply,
     socket
     |> put_flash(:info, "Paquete #{label} correctamente.")
     |> assign(:packages, Catalog.list_all_packages())}
  end

  def handle_event("toggle_featured", %{"id" => id}, socket) do
    package = Catalog.get_package!(String.to_integer(id))
    {:ok, _} = Catalog.update_package(package, %{featured: !package.featured})

    {:noreply,
     socket
     |> assign(:packages, Catalog.list_all_packages())}
  end

  def handle_event("delete_package", %{"id" => id}, socket) do
    package = Catalog.get_package!(String.to_integer(id))

    case Catalog.delete_package(package) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Paquete eliminado correctamente.")
         |> assign(:packages, Catalog.list_all_packages())}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "No se pudo eliminar el paquete.")}
    end
  end

  def handle_event("use_suggestion", %{"a" => a_id, "b" => b_id, "price" => price}, socket) do
    selected = [
      %{menu_item_id: String.to_integer(a_id), quantity: 1},
      %{menu_item_id: String.to_integer(b_id), quantity: 1}
    ]

    changeset = Catalog.change_package(%Package{}, %{price: price})

    {:noreply,
     socket
     |> assign(:modal, :new)
     |> assign(:form, to_form(changeset))
     |> assign(:selected_items, selected)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Header --%>
      <div class="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 class="text-2xl font-bold text-base-content">Paquetes</h1>
          <p class="text-sm text-base-content/50 mt-0.5">{length(@packages)} paquetes registrados</p>
        </div>
        <button class="btn btn-primary gap-2" phx-click="new_package">
          <.icon name="hero-plus" class="size-4" />
          Nuevo paquete
        </button>
      </div>

      <%!-- Smart Recommendations --%>
      <%= if @suggestions != [] do %>
        <div class="card bg-base-100 border border-accent/30">
          <div class="card-body p-4 sm:p-6">
            <div class="flex items-center gap-2 mb-4">
              <.icon name="hero-light-bulb" class="size-5 text-accent shrink-0" />
              <h2 class="font-semibold text-base-content">Sugerencias de paquetes</h2>
              <span class="badge badge-accent badge-sm">basado en costos reales</span>
            </div>
            <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
              <%= for s <- @suggestions do %>
                <div class="bg-base-200 rounded-xl p-4 space-y-2">
                  <div class="flex items-start justify-between gap-2">
                    <div class="space-y-0.5">
                      <p class="font-medium text-sm text-base-content">{s.item_a.menu_item.name}</p>
                      <p class="text-xs text-base-content/50">margen {s.item_a.margin}%</p>
                    </div>
                    <.icon name="hero-plus-small" class="size-4 text-base-content/30 mt-1 shrink-0" />
                    <div class="space-y-0.5 text-right">
                      <p class="font-medium text-sm text-base-content">{s.item_b.menu_item.name}</p>
                      <p class="text-xs text-base-content/50">margen {s.item_b.margin}%</p>
                    </div>
                  </div>
                  <div class="divider my-1 text-xs text-base-content/30">combo sugerido</div>
                  <div class="flex items-center justify-between">
                    <div>
                      <p class="text-lg font-bold text-primary">${s.suggested_price}</p>
                      <p class="text-xs text-base-content/50">
                        valor normal ${s.normal_price} · ahorro ${s.savings}
                      </p>
                      <p class="text-xs text-success font-medium">{s.package_margin}% de margen</p>
                    </div>
                    <button
                      class="btn btn-sm btn-accent"
                      phx-click="use_suggestion"
                      phx-value-a={s.item_a.menu_item.id}
                      phx-value-b={s.item_b.menu_item.id}
                      phx-value-price={s.suggested_price}
                    >
                      Crear
                    </button>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      <% end %>

      <%!-- Package list --%>
      <%= if @packages == [] do %>
        <div class="card bg-base-100">
          <div class="card-body items-center py-16 text-center">
            <.icon name="hero-gift" class="size-12 text-base-content/20 mb-2" />
            <p class="text-base-content/50">No hay paquetes registrados.</p>
            <p class="text-sm text-base-content/40">Crea el primero con el botón de arriba.</p>
          </div>
        </div>
      <% else %>
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          <%= for pkg <- @packages do %>
            <div class={"card bg-base-100 shadow-sm border #{if pkg.active, do: "border-base-200", else: "border-base-200 opacity-60"}"}>
              <div class="card-body p-4 sm:p-5 space-y-3">
                <%!-- Name + badges --%>
                <div class="flex items-start justify-between gap-2">
                  <div class="min-w-0">
                    <h3 class="font-semibold text-base-content truncate">{pkg.name}</h3>
                    <%= if pkg.description do %>
                      <p class="text-xs text-base-content/50 mt-0.5 line-clamp-2">{pkg.description}</p>
                    <% end %>
                  </div>
                  <div class="flex flex-col items-end gap-1 shrink-0">
                    <%= if pkg.active do %>
                      <span class="badge badge-success badge-sm">Activo</span>
                    <% else %>
                      <span class="badge badge-ghost badge-sm">Inactivo</span>
                    <% end %>
                    <%= if pkg.featured do %>
                      <span class="badge badge-accent badge-sm">Destacado</span>
                    <% end %>
                  </div>
                </div>

                <%!-- Price --%>
                <p class="text-2xl font-bold text-primary">${pkg.price}</p>

                <%!-- Items --%>
                <ul class="space-y-1">
                  <%= for pi <- pkg.package_items do %>
                    <li class="flex items-center gap-2 text-sm text-base-content/70">
                      <span class="badge badge-outline badge-xs">{pi.quantity}x</span>
                      {pi.menu_item.name}
                      <span class={"ml-auto badge badge-xs #{if pi.menu_item.destination == "barra", do: "badge-info", else: "badge-warning"}"}>
                        {if pi.menu_item.destination == "barra", do: "Barra", else: "Cocina"}
                      </span>
                    </li>
                  <% end %>
                </ul>

                <%!-- Actions --%>
                <div class="flex items-center gap-2 pt-1 border-t border-base-200">
                  <button
                    class="btn btn-xs btn-ghost"
                    phx-click="edit_package"
                    phx-value-id={pkg.id}
                  >
                    <.icon name="hero-pencil" class="size-3.5" /> Editar
                  </button>
                  <button
                    class="btn btn-xs btn-ghost"
                    phx-click="toggle_active"
                    phx-value-id={pkg.id}
                  >
                    {if pkg.active, do: "Desactivar", else: "Activar"}
                  </button>
                  <button
                    class="btn btn-xs btn-ghost"
                    phx-click="toggle_featured"
                    phx-value-id={pkg.id}
                    title={if pkg.featured, do: "Quitar de destacados", else: "Poner en destacados"}
                  >
                    <.icon name={if pkg.featured, do: "hero-star-solid", else: "hero-star"} class="size-3.5 text-accent" />
                  </button>
                  <button
                    class="btn btn-xs btn-ghost text-error ml-auto"
                    phx-click="delete_package"
                    phx-value-id={pkg.id}
                    data-confirm={"¿Eliminar el paquete \"#{pkg.name}\"? Esta acción no se puede deshacer."}
                  >
                    <.icon name="hero-trash" class="size-3.5" />
                  </button>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>

    <%!-- Modal --%>
    <%= if @modal != nil do %>
      <div class="fixed inset-0 z-50 flex items-start justify-center p-4 pt-16 bg-black/50 overflow-y-auto">
        <div class="bg-base-100 rounded-2xl shadow-xl w-full max-w-2xl">
          <div class="p-5 border-b border-base-200 flex items-center justify-between">
            <h2 class="font-bold text-lg text-base-content">
              {if @modal == :new, do: "Nuevo paquete", else: "Editar paquete"}
            </h2>
            <button class="btn btn-sm btn-ghost btn-circle" phx-click="close_modal">
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          </div>

          <div class="p-5 space-y-5">
            <.form id="package-form" for={@form} phx-change="validate_package" phx-submit="save_package" class="space-y-4">
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div class="sm:col-span-2">
                  <label class="label pb-1"><span class="label-text font-medium">Nombre del paquete</span></label>
                  <input
                    type="text"
                    name="package[name]"
                    value={@form[:name].value}
                    class="input input-bordered w-full"
                    placeholder="Ej. Combo Familiar"
                    required
                  />
                  <%= if @form[:name].errors != [] do %>
                    <p class="text-error text-xs mt-1">{translate_error(hd(@form[:name].errors))}</p>
                  <% end %>
                </div>

                <div class="sm:col-span-2">
                  <label class="label pb-1"><span class="label-text font-medium">Descripción <span class="text-base-content/40">(opcional)</span></span></label>
                  <textarea
                    name="package[description]"
                    class="textarea textarea-bordered w-full resize-none"
                    rows="2"
                    placeholder="Ej. 2 sandwiches + 2 cafés a precio especial"
                  >{@form[:description].value}</textarea>
                </div>

                <div>
                  <label class="label pb-1"><span class="label-text font-medium">Precio del paquete ($)</span></label>
                  <input
                    type="number"
                    step="0.01"
                    min="0.01"
                    name="package[price]"
                    value={@form[:price].value}
                    class="input input-bordered w-full"
                    placeholder="0.00"
                    required
                  />
                  <%= if @form[:price].errors != [] do %>
                    <p class="text-error text-xs mt-1">{translate_error(hd(@form[:price].errors))}</p>
                  <% end %>
                </div>

                <div class="flex items-center gap-6 pt-6">
                  <label class="flex items-center gap-2 cursor-pointer">
                    <input type="hidden" name="package[active]" value="false" />
                    <input
                      type="checkbox"
                      name="package[active]"
                      value="true"
                      class="checkbox checkbox-primary checkbox-sm"
                      checked={@form[:active].value != false && @form[:active].value != "false"}
                    />
                    <span class="text-sm font-medium">Activo</span>
                  </label>
                  <label class="flex items-center gap-2 cursor-pointer">
                    <input type="hidden" name="package[featured]" value="false" />
                    <input
                      type="checkbox"
                      name="package[featured]"
                      value="true"
                      class="checkbox checkbox-accent checkbox-sm"
                      checked={@form[:featured].value == true || @form[:featured].value == "true"}
                    />
                    <span class="text-sm font-medium">Destacado en menú</span>
                  </label>
                </div>
              </div>

              <%!-- Item selector --%>
              <div>
                <label class="label pb-2">
                  <span class="label-text font-medium">Platillos incluidos</span>
                  <span class="label-text-alt text-base-content/50">{length(@selected_items)} seleccionados</span>
                </label>
                <div class="border border-base-200 rounded-xl overflow-hidden">
                  <div class="max-h-64 overflow-y-auto divide-y divide-base-200">
                    <%= for item <- @all_menu_items do %>
                      <% selected = Enum.find(@selected_items, &(&1.menu_item_id == item.id)) %>
                      <div class={"flex items-center gap-3 px-4 py-2.5 #{if selected, do: "bg-primary/5"}"}>
                        <input
                          type="checkbox"
                          class="checkbox checkbox-primary checkbox-sm"
                          checked={selected != nil}
                          phx-click="toggle_menu_item"
                          phx-value-id={item.id}
                        />
                        <div class="flex-1 min-w-0">
                          <p class="text-sm font-medium text-base-content truncate">{item.name}</p>
                          <p class="text-xs text-base-content/50">${item.price}</p>
                        </div>
                        <span class={"badge badge-xs #{if item.destination == "barra", do: "badge-info", else: "badge-warning"}"}>
                          {if item.destination == "barra", do: "Barra", else: "Cocina"}
                        </span>
                        <%= if selected do %>
                          <div class="flex items-center gap-1">
                            <button
                              type="button"
                              class="btn btn-xs btn-ghost px-1"
                              phx-click="update_item_qty"
                              phx-value-id={item.id}
                              phx-value-qty={max(1, selected.quantity - 1)}
                            >−</button>
                            <span class="text-sm font-mono w-5 text-center">{selected.quantity}</span>
                            <button
                              type="button"
                              class="btn btn-xs btn-ghost px-1"
                              phx-click="update_item_qty"
                              phx-value-id={item.id}
                              phx-value-qty={selected.quantity + 1}
                            >+</button>
                          </div>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                </div>
              </div>

              <div class="flex justify-end gap-3 pt-2">
                <button type="button" class="btn btn-ghost" phx-click="close_modal">Cancelar</button>
                <button type="submit" class="btn btn-primary">
                  {if @modal == :new, do: "Crear paquete", else: "Guardar cambios"}
                </button>
              </div>
            </.form>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

end
