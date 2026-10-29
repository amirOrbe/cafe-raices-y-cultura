defmodule CRCWeb.Barra.DisplayLive do
  @moduledoc "Barra display screen. Shows sent orders filtered to drink items only, split by temperature."

  use CRCWeb, :live_view

  import CRCWeb.Layouts, only: [flash_group: 1]

  alias CRC.Orders
  alias CRCWeb.Components.{SiteComponents, StationComponents}

  @tick_interval 60_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(CRC.PubSub, "orders")
      schedule_tick()
    end

    orders = Orders.list_open_orders()

    socket =
      socket
      |> assign(:page_title, "Barra")
      |> assign(:orders, orders)
      |> assign(:nav_open, false)
      |> assign(:now, DateTime.utc_now())
      |> assign(:seen_sent_ids, sent_drink_ids(orders))
      |> assign(:cancel_alerts, [])
      |> assign(:view_mode, :by_order)
      # Card id whose "Todo listo" is armed for a second tap (it touches
      # drinks another barista claimed)
      |> assign(:confirming, nil)

    {:ok, socket}
  end

  # The temperature tab lives in the URL (/barra?tipo=fria) so a tablet
  # dedicated to cold drinks stays on its tab across reloads. Without one,
  # open the first tab that has something pending.
  @impl true
  def handle_params(params, _uri, socket) do
    pinned? = params["tipo"] in ~w(caliente fria otras)

    socket =
      socket
      |> assign(:tab_pinned, pinned?)
      |> assign(:temp_tab, if(pinned?, do: params["tipo"], else: "caliente"))
      |> follow_pending_tab()

    {:noreply, socket}
  end

  # A barista who didn't pick a tab must never sit on an empty one while
  # drinks wait in another: jump to the first tab with something pending.
  defp follow_pending_tab(%{assigns: %{tab_pinned: true}} = socket), do: socket

  defp follow_pending_tab(%{assigns: %{orders: orders, temp_tab: tab}} = socket) do
    if orders_by_type(orders, tab_barra_type(tab)) != [] do
      socket
    else
      next =
        Enum.find(~w(caliente fria otras), tab, fn t ->
          orders_by_type(orders, tab_barra_type(t)) != []
        end)

      assign(socket, :temp_tab, next)
    end
  end

  # ---------------------------------------------------------------------------
  # PubSub + tick
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:order_updated, _order_id}, socket) do
    # Coalesce a burst of broadcasts into a single reload
    Orders.drain_order_updates()
    new_orders = Orders.list_open_orders()
    new_ids = sent_drink_ids(new_orders)
    disappeared_ids = MapSet.difference(socket.assigns.seen_sent_ids, new_ids)
    new_items? = not MapSet.subset?(new_ids, socket.assigns.seen_sent_ids)

    new_alerts =
      if MapSet.size(disappeared_ids) > 0 do
        new_orders
        |> Enum.flat_map(& &1.order_items)
        |> Enum.filter(fn oi ->
          MapSet.member?(disappeared_ids, oi.id) and
            oi.status in ["cancelled", "cancelled_waste"]
        end)
        |> Enum.map(fn oi ->
          order = Enum.find(new_orders, &(&1.id == oi.order_id))

          %{
            id: oi.id,
            customer: order && order.customer_name,
            item_name: item_label(oi),
            quantity: oi.quantity
          }
        end)
      else
        []
      end

    socket =
      socket
      |> assign(:orders, new_orders)
      |> follow_pending_tab()
      |> assign(:seen_sent_ids, new_ids)
      |> update(:cancel_alerts, &(new_alerts ++ &1))

    socket =
      if new_items?, do: push_event(socket, "play_sound", %{type: "new_order"}), else: socket

    {:noreply, socket}
  end

  def handle_info(:tick, socket) do
    schedule_tick()
    {:noreply, socket |> assign(:now, DateTime.utc_now()) |> assign(:confirming, nil)}
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

  def handle_event("dismiss_cancel_alert", %{"id" => id}, socket) do
    id = String.to_integer(id)
    {:noreply, update(socket, :cancel_alerts, &Enum.reject(&1, fn a -> a.id == id end))}
  end

  # Refused when another barista claimed the drink — their screen may simply
  # not have caught up yet, so the server is the one that decides.
  def handle_event("mark_item_ready", %{"id" => id}, socket) do
    socket =
      case Orders.mark_item_ready_unless_claimed(
             String.to_integer(id),
             socket.assigns.current_user.id
           ) do
        {:ok, _} -> socket
        {:error, {:claimed_by, name}} -> put_flash(socket, :error, "#{name} la está preparando.")
      end

    {:noreply, assign(socket, :orders, Orders.list_open_orders())}
  end

  # First tap on a "Todo listo" that includes someone else's drinks: arm it
  def handle_event("confirm_ready", %{"card" => card_id}, socket) do
    {:noreply, assign(socket, :confirming, card_id)}
  end

  def handle_event("cancel_confirm", _params, socket) do
    {:noreply, assign(socket, :confirming, nil)}
  end

  # "Preparar" — claim the drinks so other baristas don't make them too
  def handle_event("start_items", %{"ids" => ids_str}, socket) do
    {:ok, count} = Orders.start_items(parse_ids(ids_str), socket.assigns.current_user.id)

    socket =
      if count == 0,
        do: put_flash(socket, :error, "Otro barista ya las está preparando."),
        else: socket

    {:noreply, assign(socket, :orders, Orders.list_open_orders())}
  end

  def handle_event("release_items", %{"ids" => ids_str}, socket) do
    Orders.release_items(parse_ids(ids_str), socket.assigns.current_user.id)
    {:noreply, assign(socket, :orders, Orders.list_open_orders())}
  end

  def handle_event("set_view_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, :view_mode, String.to_existing_atom(mode))}
  end

  def handle_event("mark_group_ready", %{"ids" => ids_str}, socket) do
    ids_str
    |> parse_ids()
    |> Enum.each(fn id -> Orders.mark_item_ready(id, socket.assigns.current_user.id) end)

    {:noreply, socket |> assign(:confirming, nil) |> assign(:orders, Orders.list_open_orders())}
  end

  # Marks all sent drink items of a specific barra_type (or all if type == "all") as ready.
  def handle_event("mark_drinks_ready", %{"id" => id, "type" => type}, socket) do
    order = Enum.find(socket.assigns.orders, &(to_string(&1.id) == id))

    if order do
      order.order_items
      |> Enum.filter(fn oi ->
        oi.status == "sent" and drink_item?(oi) and
          (type == "all" or barra_type(oi) == type)
      end)
      |> Enum.each(fn oi -> Orders.mark_item_ready(oi.id, socket.assigns.current_user.id) end)

      label =
        case type do
          "caliente" -> "#{order.customer_name} — calientes listos."
          "fria" -> "#{order.customer_name} — frías listas."
          _ -> "#{order.customer_name} lista en barra."
        end

      {:noreply,
       socket
       |> put_flash(:info, label)
       |> assign(:confirming, nil)
       |> assign(:orders, Orders.list_open_orders())}
    else
      {:noreply, socket}
    end
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <SiteComponents.site_navbar
      nav_open={@nav_open}
      current_page={:barra}
      current_user={@current_user}
    />
    <div id="sound-notifier" phx-hook="SoundNotifier" class="hidden"></div>
    <div class="min-h-screen bg-base-200 pt-20 pb-10 px-4">
      <div class="max-w-6xl mx-auto space-y-4">
        <%!-- Header --%>
        <% pending = pending_orders(@orders) %>
        <div class="flex items-center justify-between flex-wrap gap-3">
          <div>
            <h1 class="text-2xl font-bold text-base-content">Barra</h1>
            <p class="text-sm text-base-content/70">
              {length(pending)} {if length(pending) == 1, do: "pedido", else: "pedidos"} en espera
            </p>
          </div>
          <StationComponents.sound_hint />
        </div>

        <%!-- How it works — names the exact buttons below; always visible for temporary staff --%>
        <div class="bg-base-100 border border-base-300 rounded-2xl px-4 py-3">
          <StationComponents.how_to steps={[
            {"Toca", "Preparar", "en la primera tarjeta libre (o Tomar en una sola bebida)"},
            {"Marca", "Listo", "cada bebida al terminarla"},
            {"Toca", "Todo listo", "cuando salga la comanda completa"}
          ]} />
        </div>

        <%!-- Cancellation alerts --%>
        <%= for alert <- @cancel_alerts do %>
          <div class="alert alert-error py-2 flex items-center gap-3 shadow-sm" role="alert">
            <.icon name="hero-x-circle" class="size-5 shrink-0" />
            <span class="text-sm font-semibold flex-1">
              Cancelado: <span class="font-bold">{alert.customer}</span>
              — {alert.quantity}× {alert.item_name}
            </span>
            <button
              phx-click="dismiss_cancel_alert"
              phx-value-id={alert.id}
              class="btn btn-sm btn-ghost min-h-11 text-error-content"
            >
              Entendido
            </button>
          </div>
        <% end %>

        <%!-- No pending orders --%>
        <%= if pending == [] do %>
          <div class="bg-base-100 rounded-2xl border border-base-300 py-16 px-6 text-center space-y-2">
            <.icon name="hero-check-circle" class="size-12 text-success mx-auto" />
            <p class="text-base font-semibold text-base-content">No hay bebidas pendientes.</p>
            <p class="text-sm text-base-content/70">
              Cuando un mesero envíe una comanda aparecerá aquí y sonará un aviso.
            </p>
          </div>
        <% end %>

        <%!-- Temperature tabs + view toggle --%>
        <%= if pending != [] do %>
          <div class="flex flex-col md:flex-row md:items-center gap-3">
            <nav class="grid grid-flow-col auto-cols-fr gap-2 md:flex" aria-label="Tipo de bebida">
              <%= for {tab, label, icon} <- [
                    {"caliente", "Calientes", "hero-fire"},
                    {"fria", "Frías", "hero-cube"},
                    {"otras", "Otras", "hero-beaker"}
                  ],
                  count = length(orders_by_type(@orders, tab_barra_type(tab))),
                  tab != "otras" or count > 0 or @temp_tab == "otras" do %>
                <.link
                  patch={~p"/barra?tipo=#{tab}"}
                  aria-current={if @temp_tab == tab, do: "page"}
                  class={[
                    "btn min-h-12 gap-2 text-base",
                    if(@temp_tab == tab,
                      do: "btn-primary",
                      else: "btn-ghost bg-base-100 border-base-300"
                    )
                  ]}
                >
                  <.icon name={icon} class="size-5" /> {label}
                  <span class={[
                    "badge badge-sm tabular-nums",
                    if(@temp_tab == tab, do: "badge-ghost", else: "badge-neutral")
                  ]}>
                    {count}
                  </span>
                </.link>
              <% end %>
            </nav>
            <div class="md:ml-auto">
              <StationComponents.view_toggle view_mode={@view_mode} grouped_label="Por bebida" />
            </div>
          </div>
        <% end %>

        <%!-- Only the selected temperature tab is rendered: one list to scan, not three --%>
        <%= if @view_mode == :grouped do %>
          <%!-- Per-drink view — one card per drink across all comandas, to batch them --%>
          <% groups = group_drink_items(pending, tab_barra_type(@temp_tab)) %>
          <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3 items-start">
            <%= for {group, position} <- Enum.with_index(groups, 1) do %>
              <.grouped_drink_card
                id={"drink-group-#{group.menu_item.id}"}
                position={position}
                group={group}
                mins={group_elapsed_minutes(group.oldest_sent_at, @now)}
                current_user_id={@current_user.id}
                confirming={@confirming}
              />
            <% end %>
          </div>
        <% else %>
          <% tab_orders = orders_by_type(@orders, tab_barra_type(@temp_tab)) %>
          <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3 items-start">
            <%= for {order, position} <- Enum.with_index(tab_orders, 1) do %>
              <.drink_order_card
                id={"drink-order-#{order.id}-#{@temp_tab}"}
                position={position}
                order={order}
                items={typed_drink_items(order, tab_barra_type(@temp_tab))}
                type={if @temp_tab == "otras", do: "all", else: @temp_tab}
                mins={elapsed_minutes(order, @now, &drink_item?/1)}
                current_user_id={@current_user.id}
                confirming={@confirming}
              />
            <% end %>
          </div>
        <% end %>

        <%= if pending != [] and orders_by_type(@orders, tab_barra_type(@temp_tab)) == [] do %>
          <div class="bg-base-100 rounded-2xl border border-base-300 py-10 px-6 text-center space-y-1">
            <.icon name="hero-check-circle" class="size-10 text-success mx-auto" />
            <p class="text-base-content/70 text-sm">Nada pendiente en esta pestaña.</p>
            <p class="text-base-content/70 text-sm">Revisa la otra pestaña de arriba.</p>
          </div>
        <% end %>

        <%!-- Ready orders, waiting for the waiter --%>
        <% ready = ready_drink_orders(@orders) %>
        <%= if ready != [] do %>
          <section class="space-y-2 pt-4">
            <h2 class="text-base font-semibold text-base-content">Listos para servir</h2>
            <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2">
              <%= for order <- ready do %>
                <div class="bg-base-100 rounded-xl border border-success/40 px-4 py-3 flex items-center gap-3">
                  <.icon name="hero-check-circle" class="size-5 text-success shrink-0" />
                  <p class="font-semibold text-base-content truncate flex-1">{order.customer_name}</p>
                  <p class="text-sm text-base-content/70 shrink-0">
                    {Enum.count(order.order_items, &drink_item?/1)} bebidas
                  </p>
                </div>
              <% end %>
            </div>
          </section>
        <% end %>
      </div>
    </div>
    <.flash_group flash={@flash} />
    """
  end

  # ---------------------------------------------------------------------------
  # Private components
  # ---------------------------------------------------------------------------

  # Card shell shared by both views. Color only means urgency (late = red
  # border); being claimed shows as "Tú estás preparando" (highlighted) or
  # someone else's name (dimmed, so the eye lands on the free cards).
  attr :id, :string, required: true
  attr :claim, :map, required: true
  attr :mins, :any, default: nil
  slot :inner_block, required: true

  defp station_card(assigns) do
    ~H"""
    <article
      id={@id}
      class={[
        "bg-base-100 rounded-2xl border shadow-sm flex flex-col overflow-hidden transition-opacity",
        cond do
          @claim.state == :mine -> "border-primary ring-2 ring-primary/40"
          @mins && @mins >= 12 -> "border-error"
          true -> "border-base-300"
        end,
        @claim.state == :other && "opacity-60"
      ]}
    >
      {render_slot(@inner_block)}
    </article>
    """
  end

  attr :claim, :map, required: true

  defp claim_strip(assigns) do
    ~H"""
    <p
      :if={@claim.label}
      class={[
        "px-4 py-1.5 text-sm font-semibold flex items-center gap-1.5",
        if(@claim.state == :mine,
          do: "bg-primary/10 text-primary",
          else: "bg-base-200 text-base-content/80"
        )
      ]}
    >
      <.icon name="hero-hand-raised" class="size-4 shrink-0" /> {@claim.label}
    </p>
    """
  end

  # Footer actions, chosen by claim state so there is one obvious next step:
  # free → Preparar; mine → Todo listo (+ Soltar); someone else's → Todo listo only.
  # When the card holds drinks another barista claimed, "Todo listo" needs a
  # second tap — it stays possible (they may be on a break) but never by accident.
  attr :card_id, :string, required: true
  attr :claim, :map, required: true
  attr :confirming, :string, default: nil
  attr :ready_event, :string, required: true
  attr :ready_values, :map, required: true

  defp card_actions(assigns) do
    ~H"""
    <%= if @claim.others != [] and @confirming == @card_id do %>
      <div class="px-3 py-3 border-t border-warning/40 bg-warning/10 space-y-2 mt-auto">
        <p class="text-sm font-semibold text-base-content">
          {Enum.join(@claim.others, ", ")} está preparando parte de esto. ¿Marcar todo como listo?
        </p>
        <div class="flex gap-2">
          <button class="btn btn-ghost min-h-12 flex-1" phx-click="cancel_confirm">No</button>
          <button
            class="btn btn-warning min-h-12 flex-1 gap-1.5"
            phx-click={@ready_event}
            {@ready_values}
          >
            <.icon name="hero-check" class="size-5" /> Sí, todo listo
          </button>
        </div>
      </div>
    <% else %>
      <div class="px-3 py-3 border-t border-base-200 flex gap-2 mt-auto">
        <button
          :if={@claim.state == :free}
          class="btn btn-primary min-h-12 flex-1 gap-1.5"
          phx-click="start_items"
          phx-value-ids={Enum.join(@claim.unclaimed_ids, ",")}
        >
          <.icon name="hero-hand-raised" class="size-5" />
          {if @claim.others == [], do: "Preparar", else: "Preparar libres"}
        </button>
        <button
          :if={@claim.state == :mine}
          class="btn btn-ghost min-h-12"
          phx-click="release_items"
          phx-value-ids={Enum.join(@claim.mine_ids, ",")}
        >
          Soltar
        </button>
        <%!-- Armed first when someone else's drinks would be marked too --%>
        <button
          class={[
            "btn btn-success min-h-12 flex-1 gap-1.5",
            @claim.state != :mine && "btn-outline"
          ]}
          {if @claim.others != [],
            do: %{"phx-click" => "confirm_ready", "phx-value-card" => @card_id},
            else: Map.put(@ready_values, "phx-click", @ready_event)}
        >
          <.icon name="hero-check" class="size-5" /> Todo listo
        </button>
      </div>
    <% end %>
    """
  end

  # Per-drink action. Free → Tomar (claim just this one) + Listo; mine →
  # Listo; someone else's → their name instead of Listo.
  attr :item, :map, required: true
  attr :current_user_id, :integer, required: true

  defp item_action(assigns) do
    ~H"""
    <%= cond do %>
      <% is_nil(@item.started_by_id) -> %>
        <div class="flex gap-2 shrink-0">
          <button
            class="btn btn-sm btn-outline btn-primary min-h-11 px-3"
            phx-click="start_items"
            phx-value-ids={@item.id}
          >
            Tomar
          </button>
          <StationComponents.ready_button id={@item.id} />
        </div>
      <% @item.started_by_id == @current_user_id -> %>
        <button
          class="btn btn-sm btn-success min-h-11 px-4 shrink-0 gap-1"
          phx-click="mark_item_ready"
          phx-value-id={@item.id}
        >
          <.icon name="hero-check" class="size-4" /> Listo
        </button>
      <% true -> %>
        <span
          class="inline-flex items-center gap-1 shrink-0 max-w-32 text-sm font-semibold text-base-content/70"
          title={"#{staff_name(@item.started_by)} la está preparando"}
        >
          <.icon name="hero-hand-raised" class="size-4 shrink-0" />
          <span class="truncate">{staff_name(@item.started_by)}</span>
        </span>
    <% end %>
    """
  end

  attr :group, :map, required: true
  attr :mins, :any, default: nil
  attr :current_user_id, :integer, required: true
  attr :confirming, :string, default: nil
  attr :id, :string, required: true
  attr :position, :integer, required: true

  defp grouped_drink_card(assigns) do
    items = Enum.map(assigns.group.entries, & &1.item)
    assigns = assign(assigns, :claim, claim_info(items, assigns.current_user_id))

    ~H"""
    <.station_card id={@id} claim={@claim} mins={@mins}>
      <header class="px-4 py-3 flex items-center gap-3">
        <SiteComponents.queue_number n={@position} />
        <div class="flex-1 min-w-0">
          <h2 class="text-lg font-bold text-base-content leading-tight">
            <span class="text-primary tabular-nums">{@group.total_qty}×</span>
            {@group.menu_item.name}
          </h2>
          <p class="text-sm text-base-content/70">
            {@group.entry_count} {if @group.entry_count == 1, do: "comanda", else: "comandas"}
          </p>
        </div>
        <StationComponents.wait_time mins={@mins} />
      </header>
      <.claim_strip claim={@claim} />
      <ul class="divide-y divide-base-200 border-t border-base-200">
        <li :for={entry <- @group.entries} class="flex items-center gap-3 px-4 py-2.5">
          <div class="flex-1 min-w-0">
            <%!-- Always the comanda: with many orders open, a bare "Ana" is ambiguous --%>
            <p class="text-base font-semibold text-base-content">
              {entry.order.customer_name}
              <span :if={entry.item.quantity > 1} class="text-primary tabular-nums">
                ×{entry.item.quantity}
              </span>
              <span
                :if={entry.item.started_by_id == @current_user_id && @claim.state == :free}
                class="badge badge-sm badge-primary badge-soft ml-1"
              >
                Tú
              </span>
            </p>
            <StationComponents.item_details item={entry.item} order={entry.order} />
          </div>
          <.item_action item={entry.item} current_user_id={@current_user_id} />
        </li>
      </ul>
      <.card_actions
        card_id={@id}
        confirming={@confirming}
        claim={@claim}
        ready_event="mark_group_ready"
        ready_values={%{"phx-value-ids" => Enum.join(@group.item_ids, ",")}}
      />
    </.station_card>
    """
  end

  attr :order, :map, required: true
  attr :items, :list, required: true
  attr :type, :string, required: true
  attr :mins, :any, default: nil
  attr :current_user_id, :integer, required: true
  attr :confirming, :string, default: nil
  attr :id, :string, required: true
  attr :position, :integer, required: true

  defp drink_order_card(assigns) do
    assigns = assign(assigns, :claim, claim_info(assigns.items, assigns.current_user_id))

    ~H"""
    <.station_card id={@id} claim={@claim} mins={@mins}>
      <header class="px-4 py-3 flex items-center gap-3">
        <SiteComponents.queue_number n={@position} />
        <div class="flex-1 min-w-0">
          <h2 class="text-lg font-bold text-base-content leading-tight truncate">
            {@order.customer_name}
          </h2>
          <p class="text-sm text-base-content/70 flex items-center gap-x-2 flex-wrap">
            <span>{length(@items)} {if length(@items) == 1, do: "bebida", else: "bebidas"}</span>
            <span :if={@order.order_type == "takeout"} class="inline-flex items-center gap-1">
              <.icon name="hero-shopping-bag" class="size-3.5" /> Para llevar
            </span>
            <span :if={@order.is_group} class="inline-flex items-center gap-1">
              <.icon name="hero-user-group" class="size-3.5" /> Grupo
            </span>
          </p>
        </div>
        <StationComponents.wait_time mins={@mins} />
      </header>
      <.claim_strip claim={@claim} />
      <ul class="divide-y divide-base-200 border-t border-base-200">
        <li :for={item <- @items} class="flex items-center gap-3 px-4 py-2.5">
          <div class="flex-1 min-w-0">
            <p class="text-base font-semibold text-base-content">
              <span class="text-primary tabular-nums">{item.quantity}×</span>
              {item.menu_item && item.menu_item.name}
              <span :if={item.package_id} class="badge badge-sm badge-ghost ml-1">Paquete</span>
              <span
                :if={item.started_by_id == @current_user_id && @claim.state == :free}
                class="badge badge-sm badge-primary badge-soft ml-1"
              >
                Tú
              </span>
            </p>
            <StationComponents.item_details item={item} order={@order} />
          </div>
          <.item_action item={item} current_user_id={@current_user_id} />
        </li>
      </ul>
      <.card_actions
        card_id={@id}
        confirming={@confirming}
        claim={@claim}
        ready_event="mark_drinks_ready"
        ready_values={%{"phx-value-id" => @order.id, "phx-value-type" => @type}}
      />
    </.station_card>
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp drink_item?(oi) do
    not is_nil(oi.menu_item) and oi.menu_item.destination == "barra"
  end

  # URL tab → barra_type ("otras" = drinks with no barra_type set)
  defp tab_barra_type("otras"), do: nil
  defp tab_barra_type(tab), do: tab

  # Who is preparing which of these items, for the "Preparar" / "Soltar" UI.
  #   state: :free  — something is still unclaimed (Preparar is the next step)
  #          :mine  — all claimed, part of it by the current barista
  #          :other — all claimed by someone else (card dims)
  #   label: "Tú estás preparando" / "Ana preparando" / nil
  #   others: names of the other baristas holding any of these items
  defp claim_info(items, user_id) do
    unclaimed_ids = for i <- items, is_nil(i.started_by_id), do: i.id
    mine_ids = for i <- items, i.started_by_id == user_id, do: i.id

    others =
      items
      |> Enum.map(& &1.started_by)
      |> Enum.reject(&(is_nil(&1) or &1.id == user_id))
      |> Enum.uniq_by(& &1.id)
      |> Enum.map(&staff_name/1)

    names = if(mine_ids != [], do: ["Tú"], else: []) ++ others

    label =
      case names do
        [] -> nil
        ["Tú"] -> "Tú estás preparando"
        _ -> "#{Enum.join(names, ", ")} preparando"
      end

    state =
      cond do
        unclaimed_ids != [] -> :free
        mine_ids != [] -> :mine
        true -> :other
      end

    %{
      state: state,
      label: label,
      others: others,
      unclaimed_ids: unclaimed_ids,
      mine_ids: mine_ids
    }
  end

  # Full name: Friday profiles may be "Barista Ana", "Barista Luis"… so the
  # first word alone would make every barista look the same.
  defp staff_name(%{name: name}), do: name

  defp parse_ids(ids_str), do: ids_str |> String.split(",") |> Enum.map(&String.to_integer/1)

  # Returns the barra_type of an item ("fria" | "caliente" | nil).
  defp barra_type(oi), do: oi.menu_item && oi.menu_item.barra_type

  # Sent drink items of a specific type for an order.
  # type == nil means items with no barra_type set.
  defp typed_drink_items(order, type) do
    Enum.filter(order.order_items, fn oi ->
      oi.status == "sent" and drink_item?(oi) and barra_type(oi) == type
    end)
  end

  # Orders that have at least one sent drink item of the given type.
  # Sorted by oldest sent_at first (FIFO) so the barista works in arrival order.
  defp orders_by_type(orders, type) do
    orders
    |> Enum.filter(fn o ->
      Enum.any?(o.order_items, fn oi ->
        oi.status == "sent" and drink_item?(oi) and barra_type(oi) == type
      end)
    end)
    |> Enum.sort_by(
      fn o ->
        o.order_items
        |> Enum.filter(&(&1.status == "sent" and drink_item?(&1) and not is_nil(&1.sent_at)))
        |> Enum.map(& &1.sent_at)
        |> Enum.min(DateTime, fn -> DateTime.utc_now() end)
      end,
      DateTime
    )
  end

  # An order is pending in barra if ANY drink item still has status "sent".
  defp pending_orders(orders) do
    Enum.filter(orders, fn o ->
      Enum.any?(o.order_items, fn oi -> oi.status == "sent" and drink_item?(oi) end)
    end)
  end

  # Orders where all drink items are ready — waiting to be served.
  defp ready_drink_orders(orders) do
    Enum.filter(orders, fn o ->
      drinks = Enum.filter(o.order_items, &drink_item?/1)
      drinks != [] and Enum.all?(drinks, fn oi -> oi.status == "ready" end)
    end)
  end

  # Minutes elapsed since the oldest sent drink item in this order.
  # Returns nil if no sent items with a sent_at timestamp exist.
  defp elapsed_minutes(order, now, item_filter) do
    sent_ats =
      order.order_items
      |> Enum.filter(&(&1.status == "sent" and not is_nil(&1.sent_at) and item_filter.(&1)))
      |> Enum.map(& &1.sent_at)

    case sent_ats do
      [] -> nil
      ats -> DateTime.diff(now, Enum.min(ats, DateTime), :minute)
    end
  end

  # Returns the set of IDs of drink items currently in "sent" state.
  defp sent_drink_ids(orders) do
    orders
    |> Enum.flat_map(& &1.order_items)
    |> Enum.filter(&(&1.status == "sent" and drink_item?(&1)))
    |> MapSet.new(& &1.id)
  end

  defp item_label(%{menu_item: %{name: name}}) when not is_nil(name), do: name
  defp item_label(%{product: %{name: name}}) when not is_nil(name), do: "Extra: #{name}"
  defp item_label(_), do: "Artículo"

  # Groups pending drink items by menu_item_id for the given barra_type.
  # Returns a list of group maps, the longest-waiting drink first.
  defp group_drink_items(orders, type) do
    orders
    |> Enum.flat_map(fn order ->
      order.order_items
      |> Enum.filter(fn oi ->
        oi.status == "sent" and drink_item?(oi) and
          barra_type(oi) == type and not is_nil(oi.menu_item_id)
      end)
      |> Enum.map(fn oi -> {order, oi} end)
    end)
    |> Enum.group_by(fn {_order, oi} -> oi.menu_item_id end)
    |> Enum.map(fn {_id, entries} ->
      {_order, first} = hd(entries)
      total_qty = Enum.sum(Enum.map(entries, fn {_, oi} -> oi.quantity end))
      item_ids = Enum.map(entries, fn {_, oi} -> oi.id end)

      oldest_sent_at =
        entries
        |> Enum.map(fn {_, oi} -> oi.sent_at end)
        |> Enum.reject(&is_nil/1)
        |> case do
          [] -> nil
          ats -> Enum.min(ats, DateTime)
        end

      %{
        menu_item: first.menu_item,
        total_qty: total_qty,
        entry_count: length(entries),
        item_ids: item_ids,
        oldest_sent_at: oldest_sent_at,
        entries: Enum.map(entries, fn {order, oi} -> %{order: order, item: oi} end)
      }
    end)
    # Oldest waiting drink first (FIFO), same as the per-order view
    |> Enum.sort_by(&queue_key(&1.oldest_sent_at))
  end

  # Sort key for FIFO: earliest sent_at first, groups without one last
  defp queue_key(nil), do: {1, 0}
  defp queue_key(sent_at), do: {0, DateTime.to_unix(sent_at)}

  defp group_elapsed_minutes(nil, _now), do: nil
  defp group_elapsed_minutes(sent_at, now), do: DateTime.diff(now, sent_at, :minute)

  defp schedule_tick, do: Process.send_after(self(), :tick, @tick_interval)
end
