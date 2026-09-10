defmodule CRCWeb.Admin.ClienteLive do
  @moduledoc "Ficha de un cliente de lealtad (datos, y en PRs siguientes lealtad e historial)."

  use CRCWeb, :live_view

  alias CRC.CRM

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case CRM.get_customer(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Cliente no encontrado.")
         |> push_navigate(to: ~p"/admin/clientes")}

      customer ->
        if connected?(socket), do: CRM.subscribe_customers()

        {:ok,
         socket
         |> assign(:page_title, "#{customer.name} · Clientes")
         |> assign(:customer, customer)
         |> assign(:editing, false)
         |> assign(:form, nil)}
    end
  end

  @impl true
  def handle_info({:customer_changed, %{id: id} = customer}, socket) do
    if id == socket.assigns.customer.id do
      {:noreply, assign(socket, :customer, customer)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("edit", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing, true)
     |> assign(:form, to_form(CRM.change_customer(socket.assigns.customer)))}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, editing: false, form: nil)}
  end

  def handle_event("validate", %{"customer" => params}, socket) do
    changeset =
      socket.assigns.customer
      |> CRM.change_customer(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"customer" => params}, socket) do
    case CRM.update_customer(socket.assigns.customer, params) do
      {:ok, customer} ->
        {:noreply,
         socket
         |> assign(customer: customer, editing: false, form: nil)
         |> put_flash(:info, "Cliente actualizado correctamente.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("toggle_active", _params, socket) do
    customer = socket.assigns.customer

    result =
      if customer.active,
        do: CRM.deactivate_customer(customer),
        else: CRM.reactivate_customer(customer)

    case result do
      {:ok, updated} ->
        action = if customer.active, do: "desactivado", else: "activado"

        {:noreply,
         socket
         |> assign(:customer, updated)
         |> put_flash(:info, "Cliente #{action} correctamente.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "No se pudo cambiar el estado del cliente.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6 max-w-3xl">
      <.link
        navigate={~p"/admin/clientes"}
        class="inline-flex items-center gap-1.5 text-sm text-base-content/60 hover:text-primary transition-colors"
      >
        <.icon name="hero-arrow-left" class="size-4" /> Todos los clientes
      </.link>

      <div class="flex items-start justify-between flex-wrap gap-3">
        <div class="flex items-center gap-4">
          <div class="size-14 rounded-full bg-primary/10 flex items-center justify-center shrink-0 border border-base-300">
            <span class="text-primary font-bold text-lg">
              {@customer.name |> String.first() |> String.upcase()}
            </span>
          </div>
          <div>
            <h1 class="text-2xl font-bold text-base-content flex items-center gap-2">
              {@customer.name}
              <%= if not @customer.active do %>
                <span class="badge badge-sm badge-error">Inactivo</span>
              <% end %>
            </h1>
            <p class="text-sm text-base-content/50 mt-0.5">Cliente de lealtad</p>
          </div>
        </div>
        <div class="flex gap-2">
          <button class="btn btn-sm btn-ghost gap-1.5" phx-click="toggle_active">
            <.icon
              name={if @customer.active, do: "hero-no-symbol", else: "hero-check-circle"}
              class="size-4"
            />
            {if @customer.active, do: "Desactivar", else: "Activar"}
          </button>
          <button class="btn btn-sm btn-primary gap-1.5" phx-click="edit">
            <.icon name="hero-pencil" class="size-4" /> Editar
          </button>
        </div>
      </div>

      <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm p-5">
        <h2 class="text-sm font-semibold text-base-content/60 uppercase tracking-wider mb-4">
          Datos
        </h2>
        <dl class="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-4">
          <.data_row label="Teléfono" value={@customer.phone} />
          <.data_row label="Correo" value={@customer.email} />
          <.data_row label="Cumpleaños" value={format_birthday(@customer.birthday)} />
          <.data_row label="Registrado" value={format_date(@customer.inserted_at)} />
          <div class="sm:col-span-2">
            <dt class="text-xs font-medium text-base-content/50 uppercase tracking-wider">Notas</dt>
            <dd class="text-sm text-base-content mt-1 whitespace-pre-wrap">
              {@customer.notes || "—"}
            </dd>
          </div>
        </dl>
      </div>
    </div>

    <%= if @editing do %>
      <.edit_modal form={@form} />
    <% end %>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true

  defp data_row(assigns) do
    ~H"""
    <div>
      <dt class="text-xs font-medium text-base-content/50 uppercase tracking-wider">{@label}</dt>
      <dd class="text-sm text-base-content mt-1">{@value || "—"}</dd>
    </div>
    """
  end

  attr :form, :map, required: true

  defp edit_modal(assigns) do
    ~H"""
    <div
      id="customer-edit-modal"
      class="fixed inset-0 z-50 flex items-center justify-center p-4"
      phx-window-keydown="close_modal"
      phx-key="Escape"
    >
      <div class="absolute inset-0 bg-black/50 backdrop-blur-sm" phx-click="close_modal"></div>

      <div class="relative bg-base-100 rounded-2xl shadow-2xl w-full max-w-md overflow-y-auto max-h-[90vh]">
        <div class="px-6 py-4 border-b border-base-300 flex items-center justify-between">
          <h2 class="text-lg font-semibold text-base-content">Editar cliente</h2>
          <button class="btn btn-ghost btn-sm btn-circle" phx-click="close_modal">
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>

        <div class="px-6 py-5">
          <.form
            id="customer-edit-form"
            for={@form}
            phx-change="validate"
            phx-submit="save"
            class="space-y-4"
          >
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <.input field={@form[:name]} type="text" label="Nombre" />
              <.input field={@form[:phone]} type="text" label="Teléfono" />
            </div>
            <.input field={@form[:email]} type="email" label="Correo (opcional)" />
            <.input field={@form[:birthday]} type="date" label="Fecha de cumpleaños (opcional)" />
            <.input field={@form[:notes]} type="textarea" label="Notas (opcional)" />
            <div class="flex justify-end gap-3 pt-2">
              <button type="button" class="btn btn-ghost" phx-click="close_modal">Cancelar</button>
              <button type="submit" class="btn btn-primary">Guardar cambios</button>
            </div>
          </.form>
        </div>
      </div>
    </div>
    """
  end

  defp format_birthday(nil), do: nil

  defp format_birthday(%Date{} = date) do
    "#{String.pad_leading("#{date.day}", 2, "0")} de #{month_name(date.month)}"
  end

  defp format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%d/%m/%Y")
  defp format_date(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%d/%m/%Y")
  defp format_date(_), do: nil

  defp month_name(m) do
    ~w(enero febrero marzo abril mayo junio julio agosto septiembre octubre noviembre diciembre)
    |> Enum.at(m - 1)
  end
end
