defmodule CRCWeb.Admin.ClientesLive do
  @moduledoc "Gestión de clientes de lealtad desde el panel de administración."

  use CRCWeb, :live_view

  alias CRC.CRM
  alias CRC.CRM.Customer

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: CRM.subscribe_customers()

    socket =
      socket
      |> assign(:page_title, "Clientes · Admin")
      |> assign(:status_filter, :active)
      |> assign(:query, "")
      |> assign(:modal, nil)
      |> assign(:form, nil)
      |> assign(:confirm_delete, false)
      |> load_customers()

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # PubSub
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:customer_changed, _customer}, socket) do
    {:noreply, load_customers(socket)}
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("set_status_filter", %{"status" => status}, socket) do
    {:noreply,
     socket
     |> assign(:status_filter, String.to_existing_atom(status))
     |> load_customers()}
  end

  def handle_event("search", %{"query" => query}, socket) do
    {:noreply,
     socket
     |> assign(:query, query)
     |> load_customers()}
  end

  def handle_event("new_customer", _params, socket) do
    {:noreply,
     socket
     |> assign(:modal, :new)
     |> assign(:confirm_delete, false)
     |> assign(:form, to_form(CRM.change_customer(%Customer{})))}
  end

  def handle_event("edit_customer", %{"id" => id}, socket) do
    customer = CRM.get_customer!(String.to_integer(id))

    {:noreply,
     socket
     |> assign(:modal, {:edit, customer})
     |> assign(:confirm_delete, false)
     |> assign(:form, to_form(CRM.change_customer(customer)))}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, modal: nil, form: nil, confirm_delete: false)}
  end

  def handle_event("validate", %{"customer" => params}, socket) do
    changeset =
      %Customer{}
      |> CRM.change_customer(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save_customer", %{"customer" => params}, socket) do
    result =
      case socket.assigns.modal do
        :new -> CRM.create_customer(params, socket.assigns.current_user)
        {:edit, customer} -> CRM.update_customer(customer, params)
      end

    case result do
      {:ok, _customer} ->
        label = if socket.assigns.modal == :new, do: "registrado", else: "actualizado"

        {:noreply,
         socket
         |> put_flash(:info, "Cliente #{label} correctamente.")
         |> assign(modal: nil, form: nil, confirm_delete: false)
         |> load_customers()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("toggle_active", %{"id" => id}, socket) do
    customer = CRM.get_customer!(String.to_integer(id))

    result =
      if customer.active,
        do: CRM.deactivate_customer(customer),
        else: CRM.reactivate_customer(customer)

    case result do
      {:ok, _} ->
        action = if customer.active, do: "desactivado", else: "activado"

        {:noreply,
         socket
         |> put_flash(:info, "Cliente #{action} correctamente.")
         |> load_customers()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "No se pudo cambiar el estado del cliente.")}
    end
  end

  def handle_event("confirm_delete", _params, socket) do
    {:noreply, assign(socket, :confirm_delete, true)}
  end

  def handle_event("delete_customer", _params, socket) do
    customer =
      case socket.assigns.modal do
        {:edit, c} -> c
        _ -> nil
      end

    case customer && CRM.delete_customer(customer) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Cliente eliminado correctamente.")
         |> assign(modal: nil, form: nil, confirm_delete: false)
         |> load_customers()}

      {:error, :has_records} ->
        {:noreply,
         socket
         |> assign(:confirm_delete, false)
         |> put_flash(
           :error,
           "No se puede eliminar: el cliente tiene comandas o visitas asociadas. Desactívalo en su lugar."
         )}

      _ ->
        {:noreply, put_flash(socket, :error, "No se pudo eliminar el cliente.")}
    end
  end

  # ---------------------------------------------------------------------------
  # Data
  # ---------------------------------------------------------------------------

  defp load_customers(socket) do
    %{status_filter: status, query: query} = socket.assigns

    socket
    |> assign(:customers, CRM.list_customers(status: status, query: query))
    |> assign(:active_count, count_customers(:active))
    |> assign(:inactive_count, count_customers(:inactive))
  end

  defp count_customers(status), do: length(CRM.list_customers(status: status))

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 class="text-2xl font-bold text-base-content">Clientes</h1>
          <p class="text-sm text-base-content/50 mt-0.5">
            {length(@customers)} {customer_count_label(length(@customers), @status_filter)}
          </p>
        </div>
        <button id="btn-new-customer" class="btn btn-primary gap-2" phx-click="new_customer">
          <.icon name="hero-plus" class="size-4" /> Nuevo cliente
        </button>
      </div>

      <div class="flex flex-col sm:flex-row sm:items-center gap-3">
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
            <span class="badge badge-xs badge-ghost">{@active_count}</span>
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
            <span class="badge badge-xs badge-ghost">{@inactive_count}</span>
          </button>
        </div>
        <form phx-change="search" phx-submit="search" class="sm:ml-auto w-full sm:w-72">
          <label class="input input-bordered input-sm flex items-center gap-2 w-full">
            <.icon name="hero-magnifying-glass" class="size-4 text-base-content/40" />
            <input
              type="text"
              name="query"
              value={@query}
              placeholder="Buscar por nombre o teléfono…"
              phx-debounce="300"
              class="grow"
              autocomplete="off"
            />
          </label>
        </form>
      </div>

      <%= if @customers == [] do %>
        <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm py-16 text-center">
          <.icon name="hero-identification" class="size-10 text-base-content/20 mx-auto mb-3" />
          <p class="text-base-content/50 text-sm">
            {if @query != "",
              do: "Ningún cliente coincide con la búsqueda.",
              else: "No hay clientes registrados."}
          </p>
        </div>
      <% else %>
        <%!-- Mobile card list --%>
        <div class="md:hidden flex flex-col gap-2">
          <%= for c <- @customers do %>
            <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm p-3 flex items-center gap-3">
              <.link
                navigate={~p"/admin/clientes/#{c.id}"}
                class="flex items-center gap-3 flex-1 min-w-0"
              >
                <div class="size-11 rounded-full bg-primary/10 flex items-center justify-center shrink-0 border border-base-300">
                  <span class="text-primary font-bold text-sm">{initial(c.name)}</span>
                </div>
                <div class="flex-1 min-w-0">
                  <div class="flex items-center gap-2 flex-wrap">
                    <p class="font-semibold text-sm text-base-content truncate">{c.name}</p>
                    <.status_badge active={c.active} />
                  </div>
                  <p class="text-xs text-base-content/50 truncate mt-0.5">
                    {c.phone}{if c.email, do: " · #{c.email}"}
                  </p>
                </div>
              </.link>
              <div class="flex flex-col items-center gap-1 shrink-0">
                <button
                  id={"btn-edit-mobile-#{c.id}"}
                  class="btn btn-ghost btn-xs btn-circle"
                  phx-click="edit_customer"
                  phx-value-id={c.id}
                  title="Editar"
                >
                  <.icon name="hero-pencil" class="size-4" />
                </button>
                <button
                  id={"btn-toggle-mobile-#{c.id}"}
                  class={[
                    "btn btn-ghost btn-xs btn-circle",
                    if(c.active, do: "text-error", else: "text-success")
                  ]}
                  phx-click="toggle_active"
                  phx-value-id={c.id}
                  title={if c.active, do: "Desactivar", else: "Activar"}
                >
                  <.icon
                    name={if c.active, do: "hero-no-symbol", else: "hero-check-circle"}
                    class="size-4"
                  />
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
                  <th class="w-[30%]">Nombre</th>
                  <th class="w-[18%]">Teléfono</th>
                  <th class="w-[26%]">Correo</th>
                  <th class="w-[14%]">Cumpleaños</th>
                  <th class="w-[12%] text-right">Acciones</th>
                </tr>
              </thead>
              <tbody>
                <%= for c <- @customers do %>
                  <tr class="hover:bg-base-200/50 transition-colors">
                    <td class="max-w-0">
                      <.link
                        navigate={~p"/admin/clientes/#{c.id}"}
                        class="flex items-center gap-3 group"
                      >
                        <div class="size-8 rounded-full bg-primary/10 flex items-center justify-center shrink-0 border border-base-300">
                          <span class="text-primary font-semibold text-xs">{initial(c.name)}</span>
                        </div>
                        <span class="font-medium text-sm text-base-content truncate group-hover:text-primary transition-colors">
                          {c.name}
                        </span>
                        <.status_badge :if={not c.active} active={c.active} />
                      </.link>
                    </td>
                    <td class="text-sm text-base-content/70">{c.phone}</td>
                    <td class="max-w-0 text-sm text-base-content/70 truncate">{c.email || "—"}</td>
                    <td class="text-sm text-base-content/70">{format_birthday(c.birthday)}</td>
                    <td>
                      <div class="flex items-center justify-end gap-1">
                        <button
                          id={"btn-edit-#{c.id}"}
                          class="btn btn-ghost btn-xs btn-circle"
                          phx-click="edit_customer"
                          phx-value-id={c.id}
                          title="Editar"
                        >
                          <.icon name="hero-pencil" class="size-4" />
                        </button>
                        <button
                          id={"btn-toggle-#{c.id}"}
                          class={[
                            "btn btn-ghost btn-xs btn-circle",
                            if(c.active, do: "text-error", else: "text-success")
                          ]}
                          phx-click="toggle_active"
                          phx-value-id={c.id}
                          title={if c.active, do: "Desactivar", else: "Activar"}
                        >
                          <.icon
                            name={if c.active, do: "hero-no-symbol", else: "hero-check-circle"}
                            class="size-4"
                          />
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
      <.customer_modal form={@form} modal={@modal} confirm_delete={@confirm_delete} />
    <% end %>
    """
  end

  # ---------------------------------------------------------------------------
  # Modal
  # ---------------------------------------------------------------------------

  attr :form, :map, required: true
  attr :modal, :any, required: true
  attr :confirm_delete, :boolean, default: false

  defp customer_modal(assigns) do
    title = if assigns.modal == :new, do: "Nuevo cliente", else: "Editar cliente"
    assigns = assign(assigns, :title, title)

    ~H"""
    <div
      id="customer-modal"
      class="fixed inset-0 z-50 flex items-center justify-center p-4"
      phx-window-keydown="close_modal"
      phx-key="Escape"
    >
      <div class="absolute inset-0 bg-black/50 backdrop-blur-sm" phx-click="close_modal"></div>

      <div class="relative bg-base-100 rounded-2xl shadow-2xl w-full max-w-md overflow-y-auto max-h-[90vh]">
        <div class="px-6 py-4 border-b border-base-300 flex items-center justify-between">
          <h2 class="text-lg font-semibold text-base-content">{@title}</h2>
          <button class="btn btn-ghost btn-sm btn-circle" phx-click="close_modal">
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>

        <div class="px-6 py-5">
          <.form
            id="customer-form"
            for={@form}
            phx-change="validate"
            phx-submit="save_customer"
            class="space-y-4"
          >
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <.input field={@form[:name]} type="text" label="Nombre" placeholder="Ej. Ana López" />
              <.input
                field={@form[:phone]}
                type="text"
                label="Teléfono"
                placeholder="55 1234 5678"
              />
            </div>
            <.input
              field={@form[:email]}
              type="email"
              label="Correo (opcional)"
              placeholder="correo@ejemplo.com"
            />
            <.input field={@form[:birthday]} type="date" label="Fecha de cumpleaños (opcional)" />
            <.input
              field={@form[:notes]}
              type="textarea"
              label="Notas (opcional)"
              placeholder="Preferencias, alergias, lo que suele pedir…"
            />

            <div class="flex justify-end gap-3 pt-2">
              <button type="button" class="btn btn-ghost" phx-click="close_modal">Cancelar</button>
              <button type="submit" class="btn btn-primary">
                {if @modal == :new, do: "Registrar cliente", else: "Guardar cambios"}
              </button>
            </div>
          </.form>

          <%= if @modal != :new do %>
            <div class="border-t border-base-200 mt-4 pt-4">
              <%= if @confirm_delete do %>
                <p class="text-xs text-error mb-3 font-medium">
                  ¿Eliminar este cliente permanentemente? Solo es posible si no tiene comandas ni visitas.
                </p>
                <div class="flex gap-2">
                  <button
                    type="button"
                    class="btn btn-error btn-sm flex-1"
                    phx-click="delete_customer"
                  >
                    Sí, eliminar
                  </button>
                  <button type="button" class="btn btn-ghost btn-sm flex-1" phx-click="close_modal">
                    Cancelar
                  </button>
                </div>
              <% else %>
                <button
                  type="button"
                  class="btn btn-ghost btn-sm text-error gap-1.5"
                  phx-click="confirm_delete"
                >
                  <.icon name="hero-trash" class="size-4" /> Eliminar cliente
                </button>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp status_badge(assigns) do
    ~H"""
    <%= if @active do %>
      <span class="badge badge-xs badge-success shrink-0">Activo</span>
    <% else %>
      <span class="badge badge-xs badge-error shrink-0">Inactivo</span>
    <% end %>
    """
  end

  defp initial(name), do: name |> String.first() |> String.upcase()

  defp customer_count_label(1, :active), do: "cliente activo"
  defp customer_count_label(_n, :active), do: "clientes activos"
  defp customer_count_label(1, :inactive), do: "cliente inactivo"
  defp customer_count_label(_n, :inactive), do: "clientes inactivos"

  defp format_birthday(nil), do: "—"

  defp format_birthday(%Date{} = date) do
    "#{String.pad_leading("#{date.day}", 2, "0")} #{month_abbr(date.month)}"
  end

  defp month_abbr(m) do
    ~w(ene feb mar abr may jun jul ago sep oct nov dic) |> Enum.at(m - 1)
  end
end
