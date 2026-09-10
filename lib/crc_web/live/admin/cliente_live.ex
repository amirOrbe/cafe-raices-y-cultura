defmodule CRCWeb.Admin.ClienteLive do
  @moduledoc "Ficha de un cliente de lealtad: datos, lealtad, gasto e historial."

  use CRCWeb, :live_view

  alias CRC.CRM
  alias CRC.Utils

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case CRM.customer_profile(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Cliente no encontrado.")
         |> push_navigate(to: ~p"/admin/clientes")}

      profile ->
        if connected?(socket), do: CRM.subscribe_customers()

        {:ok,
         socket
         |> assign(:page_title, "#{profile.customer.name} · Clientes")
         |> assign(:profile, profile)
         |> assign(:editing, false)
         |> assign(:form, nil)}
    end
  end

  @impl true
  def handle_info({:customer_changed, %{id: id}}, socket) do
    if id == socket.assigns.profile.customer.id do
      {:noreply, reload(socket)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("edit", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing, true)
     |> assign(:form, to_form(CRM.change_customer(socket.assigns.profile.customer)))}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, editing: false, form: nil)}
  end

  def handle_event("validate", %{"customer" => params}, socket) do
    changeset =
      socket.assigns.profile.customer
      |> CRM.change_customer(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"customer" => params}, socket) do
    case CRM.update_customer(socket.assigns.profile.customer, params) do
      {:ok, _customer} ->
        {:noreply,
         socket
         |> assign(editing: false, form: nil)
         |> reload()
         |> put_flash(:info, "Cliente actualizado correctamente.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("toggle_active", _params, socket) do
    customer = socket.assigns.profile.customer

    result =
      if customer.active,
        do: CRM.deactivate_customer(customer),
        else: CRM.reactivate_customer(customer)

    case result do
      {:ok, _} ->
        action = if customer.active, do: "desactivado", else: "activado"
        {:noreply, socket |> reload() |> put_flash(:info, "Cliente #{action} correctamente.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "No se pudo cambiar el estado del cliente.")}
    end
  end

  def handle_event("deliver_reward", %{"id" => id}, socket) do
    redemption = CRM.get_redemption!(id)

    case CRM.redeem_reward(redemption, nil, socket.assigns.current_user.id) do
      {:ok, _} ->
        {:noreply, socket |> reload() |> put_flash(:info, "Recompensa marcada como entregada.")}

      _ ->
        {:noreply, put_flash(socket, :error, "No se pudo marcar la recompensa.")}
    end
  end

  def handle_event("grant_birthday", _params, socket) do
    case CRM.grant_birthday_reward(socket.assigns.profile.customer) do
      {:ok, %{} = _r} ->
        {:noreply, socket |> reload() |> put_flash(:info, "Beneficio de cumpleaños otorgado.")}

      {:ok, :already_granted} ->
        {:noreply, put_flash(socket, :error, "El beneficio de este año ya se otorgó.")}

      {:error, :no_birthday_config} ->
        {:noreply, put_flash(socket, :error, "No hay un beneficio de cumpleaños activo.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Hoy no es el cumpleaños del cliente.")}
    end
  end

  defp reload(socket) do
    assign(socket, :profile, CRM.customer_profile(socket.assigns.profile.customer.id))
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <% c = @profile.customer %>
    <% s = @profile.spend %>
    <div class="space-y-6 max-w-4xl">
      <.link
        navigate={~p"/admin/clientes"}
        class="inline-flex items-center gap-1.5 text-sm text-base-content/60 hover:text-primary transition-colors"
      >
        <.icon name="hero-arrow-left" class="size-4" /> Todos los clientes
      </.link>

      <div class="flex items-start justify-between flex-wrap gap-3">
        <div class="flex items-center gap-4">
          <div class="size-14 rounded-full bg-primary/10 flex items-center justify-center shrink-0 border border-base-300">
            <span class="text-primary font-bold text-lg">{initial(c.name)}</span>
          </div>
          <div>
            <h1 class="text-2xl font-bold text-base-content flex items-center gap-2">
              {c.name}
              <span :if={not c.active} class="badge badge-sm badge-error">Inactivo</span>
              <span :if={@profile.birthday_today?} class="badge badge-sm badge-accent">
                🎂 Hoy cumple
              </span>
            </h1>
            <p class="text-sm text-base-content/50 mt-0.5">
              Cliente desde {format_date(c.inserted_at)}
            </p>
          </div>
        </div>
        <div class="flex gap-2">
          <button class="btn btn-sm btn-ghost gap-1.5" phx-click="toggle_active">
            <.icon
              name={if c.active, do: "hero-no-symbol", else: "hero-check-circle"}
              class="size-4"
            />
            {if c.active, do: "Desactivar", else: "Activar"}
          </button>
          <button class="btn btn-sm btn-primary gap-1.5" phx-click="edit">
            <.icon name="hero-pencil" class="size-4" /> Editar
          </button>
        </div>
      </div>

      <%!-- Stats --%>
      <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
        <.stat label="Visitas" value={@profile.visit_count} />
        <.stat label="Gasto total" value={"$#{Utils.format_money(s.total_spend)}"} />
        <.stat label="Ticket promedio" value={"$#{Utils.format_money(s.avg_ticket)}"} />
        <.stat label="Comandas" value={s.order_count} />
      </div>

      <%!-- Lealtad --%>
      <section class="bg-base-100 rounded-2xl border border-base-300 shadow-sm p-5 space-y-4">
        <div class="flex items-center justify-between">
          <h2 class="text-sm font-semibold text-base-content/60 uppercase tracking-wider">Lealtad</h2>
          <button
            :if={@profile.birthday_today? and @profile.birthday_reward}
            class="btn btn-accent btn-xs"
            phx-click="grant_birthday"
          >
            🎂 Otorgar beneficio de cumpleaños
          </button>
        </div>

        <%= if @profile.pending_rewards == [] do %>
          <p class="text-sm text-base-content/50">Sin recompensas pendientes.</p>
        <% else %>
          <ul class="space-y-2">
            <%= for r <- @profile.pending_rewards do %>
              <li class="flex items-center justify-between gap-3 rounded-xl bg-success/5 border border-success/20 px-3 py-2">
                <div class="min-w-0">
                  <p class="text-sm font-medium text-base-content">🎁 {r.benefit_snapshot}</p>
                  <p class="text-xs text-base-content/50">
                    {reward_kind_label(r)} · ganada {format_date(r.earned_at)}
                  </p>
                </div>
                <button class="btn btn-success btn-xs" phx-click="deliver_reward" phx-value-id={r.id}>
                  Marcar entregada
                </button>
              </li>
            <% end %>
          </ul>
        <% end %>

        <%= if @profile.redemptions != [] do %>
          <details class="text-sm">
            <summary class="cursor-pointer text-base-content/60 hover:text-base-content">
              Historial de recompensas ({length(@profile.redemptions)})
            </summary>
            <ul class="mt-2 space-y-1">
              <%= for r <- @profile.redemptions do %>
                <li class="flex items-center gap-2 text-xs text-base-content/60">
                  <span class={["badge badge-xs", redemption_badge(r.status)]}>
                    {redemption_status_label(r.status)}
                  </span>
                  <span>🎁 {r.benefit_snapshot}</span>
                  <span class="text-base-content/40">
                    · {format_date(r.redeemed_at || r.earned_at)}
                  </span>
                </li>
              <% end %>
            </ul>
          </details>
        <% end %>
      </section>

      <%!-- Qué consume más --%>
      <section class="bg-base-100 rounded-2xl border border-base-300 shadow-sm p-5">
        <h2 class="text-sm font-semibold text-base-content/60 uppercase tracking-wider mb-3">
          Qué consume más
        </h2>
        <%= if @profile.top_items == [] do %>
          <p class="text-sm text-base-content/50">Aún no hay consumo registrado.</p>
        <% else %>
          <div class="flex flex-wrap gap-2">
            <%= for {name, qty} <- @profile.top_items do %>
              <span class="badge badge-lg badge-ghost gap-1.5">
                {name} <span class="font-bold text-primary">{qty}</span>
              </span>
            <% end %>
          </div>
        <% end %>
      </section>

      <%!-- Historial de comandas --%>
      <section class="bg-base-100 rounded-2xl border border-base-300 shadow-sm p-5">
        <h2 class="text-sm font-semibold text-base-content/60 uppercase tracking-wider mb-3">
          Historial de comandas
        </h2>
        <%= if @profile.orders == [] do %>
          <p class="text-sm text-base-content/50">Este cliente aún no tiene comandas cerradas.</p>
        <% else %>
          <ul class="divide-y divide-base-200">
            <%= for o <- @profile.orders do %>
              <li class="py-2.5 flex items-center justify-between gap-3">
                <div class="min-w-0">
                  <p class="text-sm font-medium text-base-content">
                    {format_date(o.closed_at)} · {o.customer_name}
                  </p>
                  <p class="text-xs text-base-content/50">
                    {length(o.order_items)} artículo(s) · {payment_label(o.payment_method)}
                  </p>
                </div>
                <span class="text-sm font-bold text-primary shrink-0">
                  ${Utils.format_money(o.total)}
                </span>
              </li>
            <% end %>
          </ul>
        <% end %>
      </section>

      <%!-- Datos --%>
      <section class="bg-base-100 rounded-2xl border border-base-300 shadow-sm p-5">
        <h2 class="text-sm font-semibold text-base-content/60 uppercase tracking-wider mb-4">
          Datos
        </h2>
        <dl class="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-4">
          <.data_row label="Teléfono" value={c.phone} />
          <.data_row label="Correo" value={c.email} />
          <.data_row label="Cumpleaños" value={format_birthday(c.birthday)} />
          <div class="sm:col-span-2">
            <dt class="text-xs font-medium text-base-content/50 uppercase tracking-wider">Notas</dt>
            <dd class="text-sm text-base-content mt-1 whitespace-pre-wrap">{c.notes || "—"}</dd>
          </div>
        </dl>
      </section>
    </div>

    <%= if @editing do %>
      <.edit_modal form={@form} />
    <% end %>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true

  defp stat(assigns) do
    ~H"""
    <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm px-4 py-3">
      <p class="text-xs text-base-content/50 uppercase tracking-wider">{@label}</p>
      <p class="text-xl font-bold text-base-content mt-1">{@value}</p>
    </div>
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

  defp initial(name), do: name |> String.first() |> String.upcase()

  defp reward_kind_label(%{kind: "birthday"}), do: "Cumpleaños"
  defp reward_kind_label(%{cycle: cycle}), do: "Tarjeta de lealtad · bloque #{cycle}"

  defp redemption_status_label("earned"), do: "Pendiente"
  defp redemption_status_label("redeemed"), do: "Entregada"
  defp redemption_status_label("void"), do: "Anulada"
  defp redemption_status_label(other), do: other

  defp redemption_badge("redeemed"), do: "badge-success"
  defp redemption_badge("void"), do: "badge-ghost"
  defp redemption_badge(_), do: "badge-warning"

  defp payment_label("efectivo"), do: "Efectivo"
  defp payment_label("tarjeta"), do: "Tarjeta"
  defp payment_label("transferencia"), do: "Transferencia"
  defp payment_label(_), do: "—"

  defp format_birthday(nil), do: nil

  defp format_birthday(%Date{} = date) do
    "#{String.pad_leading("#{date.day}", 2, "0")} de #{month_name(date.month)}"
  end

  defp format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%d/%m/%Y")
  defp format_date(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%d/%m/%Y")
  defp format_date(_), do: "—"

  defp month_name(m) do
    ~w(enero febrero marzo abril mayo junio julio agosto septiembre octubre noviembre diciembre)
    |> Enum.at(m - 1)
  end
end
