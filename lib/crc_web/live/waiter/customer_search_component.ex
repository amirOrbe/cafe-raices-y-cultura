defmodule CRCWeb.Waiter.CustomerSearchComponent do
  @moduledoc """
  Buscador de clientes reutilizable para el mostrador.

  Busca por nombre o teléfono, o registra un cliente nuevo (nombre + teléfono +
  cumpleaños). Al elegir/crear uno, avisa al LiveView padre con
  `send(self(), {:customer_selected, customer})`.
  """
  use CRCWeb, :live_component

  alias CRC.CRM
  alias CRC.CRM.Customer

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:mode, fn -> :search end)
     |> assign_new(:query, fn -> "" end)
     |> assign_new(:results, fn -> [] end)
     |> assign_new(:form, fn -> to_form(CRM.change_customer(%Customer{}), as: :customer) end)}
  end

  @impl true
  def handle_event("search", %{"value" => query}, socket) do
    {:noreply, assign(socket, query: query, results: CRM.search_customers(query))}
  end

  def handle_event("pick", %{"id" => id}, socket) do
    customer = CRM.get_customer!(id)
    send(self(), {:customer_selected, customer})
    {:noreply, reset(socket)}
  end

  def handle_event("show_new", _params, socket) do
    prefill =
      if socket.assigns.query =~ ~r/\d/,
        do: %{"phone" => socket.assigns.query},
        else: %{"name" => socket.assigns.query}

    {:noreply,
     socket
     |> assign(:mode, :new)
     |> assign(:form, to_form(CRM.change_customer(%Customer{}, prefill), as: :customer))}
  end

  def handle_event("show_search", _params, socket) do
    {:noreply, assign(socket, :mode, :search)}
  end

  def handle_event("validate_new", %{"customer" => params}, socket) do
    changeset =
      %Customer{} |> CRM.change_customer(params) |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: :customer))}
  end

  def handle_event("create", %{"customer" => params}, socket) do
    case CRM.create_customer(params, socket.assigns[:current_user]) do
      {:ok, customer} ->
        send(self(), {:customer_selected, customer})
        {:noreply, reset(socket)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :customer))}
    end
  end

  defp reset(socket) do
    socket
    |> assign(mode: :search, query: "", results: [])
    |> assign(:form, to_form(CRM.change_customer(%Customer{}), as: :customer))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="bg-base-100 rounded-2xl border border-base-300 shadow-sm p-4">
      <div class="flex items-center justify-between mb-3">
        <h3 class="font-semibold text-sm text-base-content flex items-center gap-1.5">
          <.icon name="hero-identification" class="size-4 text-primary" /> Asociar cliente
        </h3>
        <button
          :if={@mode == :new}
          type="button"
          class="btn btn-ghost btn-xs"
          phx-click="show_search"
          phx-target={@myself}
        >
          ← Buscar
        </button>
      </div>

      <%= if @mode == :search do %>
        <input
          type="text"
          value={@query}
          placeholder="Nombre o teléfono…"
          autocomplete="off"
          phx-keyup="search"
          phx-debounce="300"
          phx-target={@myself}
          class="input input-bordered input-sm w-full"
        />

        <div class="mt-2 space-y-1">
          <%= for c <- @results do %>
            <button
              type="button"
              class="w-full flex items-center gap-2 p-2 rounded-lg hover:bg-base-200 text-left transition-colors"
              phx-click="pick"
              phx-value-id={c.id}
              phx-target={@myself}
            >
              <div class="size-7 rounded-full bg-primary/10 flex items-center justify-center shrink-0">
                <span class="text-primary text-xs font-bold">
                  {c.name |> String.first() |> String.upcase()}
                </span>
              </div>
              <div class="min-w-0">
                <p class="text-sm font-medium text-base-content truncate">{c.name}</p>
                <p class="text-xs text-base-content/50">{c.phone}</p>
              </div>
            </button>
          <% end %>

          <%= if @query != "" and @results == [] do %>
            <p class="text-xs text-base-content/50 px-2 py-1">Sin coincidencias.</p>
          <% end %>
        </div>

        <button
          type="button"
          class="btn btn-ghost btn-sm w-full mt-2 gap-1.5"
          phx-click="show_new"
          phx-target={@myself}
        >
          <.icon name="hero-plus" class="size-4" /> Registrar cliente nuevo
        </button>
      <% else %>
        <.form
          for={@form}
          phx-change="validate_new"
          phx-submit="create"
          phx-target={@myself}
          class="space-y-3"
        >
          <.input field={@form[:name]} type="text" label="Nombre" placeholder="Ana López" />
          <.input field={@form[:phone]} type="text" label="Teléfono" placeholder="55 1234 5678" />
          <.input field={@form[:birthday]} type="date" label="Cumpleaños (opcional)" />
          <button type="submit" class="btn btn-primary btn-sm w-full">Registrar y asociar</button>
        </.form>
      <% end %>
    </div>
    """
  end
end
