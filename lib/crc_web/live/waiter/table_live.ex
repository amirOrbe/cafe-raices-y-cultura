defmodule CRCWeb.Waiter.TableLive do
  @moduledoc "Overview of active customer tabs (cuentas) with option to create new ones."

  use CRCWeb, :live_view

  alias CRC.Orders
  alias CRCWeb.Components.SiteComponents

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(CRC.PubSub, "orders")
    end

    socket =
      socket
      |> assign(:page_title, "Comandas")
      |> assign(:orders, Orders.list_active_orders())
      |> assign(:show_new_modal, false)
      |> assign(:new_name, "")
      |> assign(:name_error, nil)
      |> assign(:nav_open, false)

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # PubSub
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:order_updated, _order_id}, socket) do
    {:noreply, assign(socket, :orders, Orders.list_active_orders())}
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("toggle_nav", _params, socket) do
    {:noreply, assign(socket, :nav_open, !socket.assigns.nav_open)}
  end

  def handle_event("close_nav", _params, socket) do
    {:noreply, assign(socket, :nav_open, false)}
  end

  def handle_event("open_new_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_new_modal, true)
     |> assign(:new_name, "")
     |> assign(:name_error, nil)}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, :show_new_modal, false)}
  end

  def handle_event("update_name", %{"value" => value}, socket) do
    {:noreply, assign(socket, :new_name, value)}
  end

  def handle_event("create_cuenta", %{"customer_name" => name}, socket) do
    name = String.trim(name)

    if name == "" do
      {:noreply, assign(socket, :name_error, "El nombre no puede estar vacío")}
    else
      case Orders.create_order(%{customer_name: name}) do
        {:ok, order} ->
          {:noreply,
           socket
           |> assign(:show_new_modal, false)
           |> push_navigate(to: "/mesa/#{order.id}")}

        {:error, _changeset} ->
          {:noreply, assign(socket, :name_error, "No se pudo crear la cuenta, intenta de nuevo")}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <SiteComponents.site_navbar nav_open={@nav_open} current_page={:waiter} current_user={@current_user} />
    <div class="min-h-screen bg-base-200 pt-20 pb-10 px-4">
      <div class="max-w-5xl mx-auto space-y-6">

        <%!-- Header --%>
        <div class="flex items-center justify-between flex-wrap gap-3">
          <div>
            <h1 class="text-2xl font-bold text-base-content">Comandas</h1>
            <p class="text-sm text-base-content/50 mt-0.5">
              Comandas activas del turno
            </p>
          </div>
          <button class="btn btn-primary btn-sm gap-1" phx-click="open_new_modal">
            <.icon name="hero-plus" class="size-4" />
            Nueva cuenta
          </button>
        </div>

        <%!-- Empty state --%>
        <%= if @orders == [] do %>
          <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm py-20 text-center">
            <.icon name="hero-clipboard-document-list" class="size-12 text-base-content/20 mx-auto mb-3" />
            <p class="text-base-content/50 text-sm">No hay comandas abiertas.</p>
            <button class="btn btn-primary btn-sm mt-4" phx-click="open_new_modal">
              Abrir primera cuenta
            </button>
          </div>
        <% end %>

        <%!-- Comandas grid --%>
        <div class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-4">
          <%= for order <- @orders do %>
            <.cuenta_card order={order} />
          <% end %>
        </div>

      </div>
    </div>

    <%!-- Nueva cuenta modal --%>
    <%= if @show_new_modal do %>
      <div class="fixed inset-0 z-50">
        <%!-- Backdrop: closes modal on click --%>
        <div class="absolute inset-0 bg-black/50" phx-click="close_modal"></div>
        <%!-- Modal content: sibling of backdrop, no click bubbling issue --%>
        <div class="relative z-10 flex items-center justify-center min-h-full px-4 pointer-events-none">
          <div class="bg-base-100 rounded-2xl shadow-xl w-full max-w-sm p-6 space-y-4 pointer-events-auto">
            <h2 class="text-lg font-bold text-base-content">Nueva cuenta</h2>
            <p class="text-sm text-base-content/50 mt-1">
              Ingresa el nombre del cliente o una referencia (ej. "Mesa 3", "Juan G.")
            </p>

            <form phx-submit="create_cuenta" class="mt-4 space-y-3">
              <div>
                <input
                  type="text"
                  name="customer_name"
                  value={@new_name}
                  placeholder="Nombre del cliente"
                  class={["input input-bordered w-full", @name_error && "input-error"]}
                  autofocus
                  autocomplete="off"
                />
                <%= if @name_error do %>
                  <p class="text-error text-xs mt-1">{@name_error}</p>
                <% end %>
              </div>
              <div class="flex gap-2 pt-1">
                <button type="button" class="btn btn-ghost flex-1" phx-click="close_modal">
                  Cancelar
                </button>
                <button type="submit" class="btn btn-primary flex-1">
                  Abrir cuenta
                </button>
              </div>
            </form>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  # ---------------------------------------------------------------------------
  # Cuenta card component
  # ---------------------------------------------------------------------------

  attr :order, :map, required: true

  defp cuenta_card(assigns) do
    ~H"""
    <a href={"/mesa/#{@order.id}"} class="block">
      <div class={[
        "card bg-base-100 shadow-sm border-2 hover:shadow-md transition-all cursor-pointer",
        border_class(@order.status)
      ]}>
        <div class="card-body p-4 gap-2">
          <div class="flex items-center justify-between gap-2">
            <span class="text-base font-bold text-base-content truncate">{@order.customer_name}</span>
            <.status_badge status={@order.status} />
          </div>

          <div class="text-sm text-base-content/60">
            <%= if length(@order.order_items) == 0 do %>
              Sin artículos
            <% else %>
              {length(@order.order_items)} {if length(@order.order_items) == 1, do: "artículo", else: "artículos"}
            <% end %>
          </div>

          <div class="mt-1">
            <span class={["btn btn-xs w-full", btn_class(@order.status)]}>
              <%= if @order.status == "ready" do %>
                <.icon name="hero-check-circle" class="size-3" /> Lista para servir
              <% else %>
                Ver comanda
              <% end %>
            </span>
          </div>
        </div>
      </div>
    </a>
    """
  end

  defp status_badge(%{status: "open"} = assigns) do
    ~H"<span class='badge badge-sm badge-info'>Abierta</span>"
  end

  defp status_badge(%{status: "sent"} = assigns) do
    ~H"<span class='badge badge-sm badge-warning'>En cocina</span>"
  end

  defp status_badge(%{status: "ready"} = assigns) do
    ~H"<span class='badge badge-sm badge-success'>Lista</span>"
  end

  defp status_badge(assigns) do
    ~H"<span class='badge badge-sm badge-ghost'>{@status}</span>"
  end

  defp border_class("sent"), do: "border-warning"
  defp border_class("ready"), do: "border-success"
  defp border_class(_), do: "border-base-300"

  defp btn_class("ready"), do: "btn-success btn-outline"
  defp btn_class(_), do: "btn-outline btn-primary"
end
