defmodule CRC.CRM do
  @moduledoc """
  Contexto de Clientes + Lealtad (CRM).

  Registra clientes frecuentes del café (sin autenticación — los da de alta el
  personal), acumula visitas al cerrar comandas asociadas, y otorga recompensas
  configurables (tarjeta perforada por visitas + beneficio de cumpleaños).

  Ver el plan en `.claude/plans/` para el diseño completo.
  """

  import Ecto.Query, warn: false

  alias CRC.Accounts
  alias CRC.CRM.{Customer, CustomerVisit, LoyaltyRedemption, LoyaltyReward}
  alias CRC.Orders
  alias CRC.Orders.{Order, OrderItem}
  alias CRC.Repo

  @pubsub CRC.PubSub
  @customers_topic "admin:customers"

  # ---------------------------------------------------------------------------
  # PubSub
  # ---------------------------------------------------------------------------

  @doc "Suscribe al proceso llamante a los cambios de clientes."
  def subscribe_customers do
    Phoenix.PubSub.subscribe(@pubsub, @customers_topic)
  end

  defp broadcast_customer_change({:ok, %Customer{} = customer} = result) do
    Phoenix.PubSub.broadcast(@pubsub, @customers_topic, {:customer_changed, customer})
    result
  end

  defp broadcast_customer_change(other), do: other

  # ---------------------------------------------------------------------------
  # Clientes — consultas
  # ---------------------------------------------------------------------------

  @doc """
  Lista clientes ordenados por nombre.

  Opciones:
    * `:status` — `:active` (default), `:inactive` o `:all`
    * `:query`  — filtra por nombre o teléfono (ILIKE)
  """
  def list_customers(opts \\ []) do
    status = Keyword.get(opts, :status, :active)
    query = opts |> Keyword.get(:query) |> normalize_query()

    Customer
    |> filter_by_status(status)
    |> filter_by_query(query)
    |> order_by([c], asc: c.name)
    |> Repo.all()
  end

  @doc """
  Busca clientes activos por nombre o teléfono (ILIKE), para el autocomplete del
  mostrador. Devuelve como máximo `:limit` resultados (default 10).
  """
  def search_customers(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)

    case normalize_query(query) do
      nil ->
        []

      q ->
        Customer
        |> where([c], c.active == true)
        |> filter_by_query(q)
        |> order_by([c], asc: c.name)
        |> limit(^limit)
        |> Repo.all()
    end
  end

  @doc "Obtiene un cliente por id. `nil` si no existe."
  def get_customer(id), do: Repo.get(Customer, id)

  @doc "Obtiene un cliente por id. Levanta `Ecto.NoResultsError` si no existe."
  def get_customer!(id), do: Repo.get!(Customer, id)

  @doc """
  Otros clientes activos con el mismo teléfono (posibles duplicados).
  El teléfono duplicado está permitido (familias comparten número); esto solo
  alimenta el aviso de la UI.
  """
  def possible_duplicates(phone, exclude_id \\ nil)
  def possible_duplicates(nil, _exclude_id), do: []
  def possible_duplicates("", _exclude_id), do: []

  def possible_duplicates(phone, exclude_id) do
    Customer
    |> where([c], c.phone == ^phone and c.active == true)
    |> maybe_exclude_id(exclude_id)
    |> order_by([c], asc: c.name)
    |> Repo.all()
  end

  # ---------------------------------------------------------------------------
  # Clientes — comandos
  # ---------------------------------------------------------------------------

  @doc """
  Crea un cliente. Cualquier empleado autenticado puede hacerlo (no admin-gated).
  `staff` (opcional) queda registrado como quién lo dio de alta.
  """
  def create_customer(attrs, staff \\ nil) do
    attrs = maybe_put_created_by(attrs, staff)

    %Customer{}
    |> Customer.changeset(attrs)
    |> Repo.insert()
    |> broadcast_customer_change()
  end

  @doc "Actualiza los datos de un cliente."
  def update_customer(%Customer{} = customer, attrs) do
    customer
    |> Customer.changeset(attrs)
    |> Repo.update()
    |> broadcast_customer_change()
  end

  @doc "Desactiva un cliente (no borra — conserva historial)."
  def deactivate_customer(%Customer{} = customer) do
    customer
    |> Customer.changeset(%{active: false})
    |> Repo.update()
    |> broadcast_customer_change()
  end

  @doc "Reactiva un cliente previamente desactivado."
  def reactivate_customer(%Customer{} = customer) do
    customer
    |> Customer.changeset(%{active: true})
    |> Repo.update()
    |> broadcast_customer_change()
  end

  @doc """
  Borra un cliente permanentemente.

  Devuelve `{:error, :has_records}` si tiene visitas, órdenes o redenciones
  asociadas — en ese caso solo se puede desactivar.
  """
  def delete_customer(%Customer{} = customer) do
    if has_records?(customer) do
      {:error, :has_records}
    else
      case Repo.delete(customer) do
        {:ok, deleted} ->
          Phoenix.PubSub.broadcast(@pubsub, @customers_topic, {:customer_changed, deleted})
          {:ok, deleted}

        {:error, changeset} ->
          if foreign_key_error?(changeset),
            do: {:error, :has_records},
            else: {:error, changeset}
      end
    end
  end

  # Las FKs de órdenes son `nilify_all` y las de visitas/redenciones `delete_all`,
  # así que un `Repo.delete` no fallaría: hay que chequear explícitamente.
  defp has_records?(%Customer{id: id}) do
    Repo.exists?(from o in CRC.Orders.Order, where: o.customer_id == ^id) or
      Repo.exists?(from v in CRC.CRM.CustomerVisit, where: v.customer_id == ^id) or
      Repo.exists?(from r in CRC.CRM.LoyaltyRedemption, where: r.customer_id == ^id)
  end

  @doc "Changeset para formularios de cliente."
  def change_customer(%Customer{} = customer, attrs \\ %{}) do
    Customer.changeset(customer, attrs)
  end

  # ---------------------------------------------------------------------------
  # Cumpleaños
  # ---------------------------------------------------------------------------

  @doc """
  Clientes activos con fecha de cumpleaños, ordenados por días hasta el próximo.
  Espeja `Accounts.list_staff_with_birthdays/0`.
  """
  def list_customers_with_birthdays do
    today = Date.utc_today()

    Customer
    |> where([c], c.active == true and not is_nil(c.birthday))
    |> order_by([c], asc: c.name)
    |> Repo.all()
    |> Enum.map(fn customer ->
      Map.put(
        customer,
        :days_until_birthday,
        Accounts.days_until_birthday(customer.birthday, today)
      )
    end)
    |> Enum.sort_by(fn customer -> customer.days_until_birthday || 999 end)
  end

  @doc """
  `true` si hoy es el cumpleaños del cliente (o cae dentro de `window_days`).

  Maneja el 29 de febrero: en años no bisiestos cuenta como el 28 de febrero,
  a diferencia de `Accounts.days_until_birthday/2` que devuelve `nil` ahí.
  """
  def birthday_today?(customer_or_date, today \\ Date.utc_today(), window_days \\ 0)

  def birthday_today?(%Customer{birthday: birthday}, today, window_days),
    do: birthday_today?(birthday, today, window_days)

  def birthday_today?(nil, _today, _window_days), do: false

  def birthday_today?(%Date{} = birthday, %Date{} = today, window_days) do
    case anniversary_in_year(birthday, today.year) do
      %Date{} = anniversary ->
        diff = Date.diff(today, anniversary)
        diff >= 0 and diff <= window_days

      nil ->
        false
    end
  end

  @doc false
  # Fecha del aniversario del cumpleaños en `year`. El 29 de febrero en un año no
  # bisiesto se ancla al 28 de febrero.
  def anniversary_in_year(%Date{month: month, day: day}, year) do
    case Date.new(year, month, day) do
      {:ok, date} ->
        date

      {:error, _} when month == 2 and day == 29 ->
        Date.new!(year, 2, 28)

      {:error, _} ->
        nil
    end
  end

  # ---------------------------------------------------------------------------
  # Visitas
  # ---------------------------------------------------------------------------

  @doc """
  Registra una visita para la comanda dada. Precondición: la comanda debe estar
  cerrada y tener `customer_id`.

  Idempotente — el índice único en `customer_visits.order_id` garantiza una sola
  visita por comanda aunque se cierre/reabra varias veces.

  Devuelve `{:ok, visit}`, `{:ok, :already_recorded}`, `{:error, :not_closed}`,
  `{:error, :no_customer}` o `{:error, changeset}`.
  """
  def record_visit(%Order{status: "closed", customer_id: customer_id} = order)
      when not is_nil(customer_id) do
    recorded_at = order.closed_at || DateTime.utc_now() |> DateTime.truncate(:second)

    %CustomerVisit{}
    |> CustomerVisit.changeset(%{
      customer_id: customer_id,
      order_id: order.id,
      recorded_at: recorded_at,
      recorded_by_id: order.closed_by_id
    })
    |> Repo.insert()
    |> case do
      {:ok, visit} ->
        {:ok, visit}

      {:error, changeset} ->
        if unique_error?(changeset), do: {:ok, :already_recorded}, else: {:error, changeset}
    end
  end

  def record_visit(%Order{status: "closed"}), do: {:error, :no_customer}
  def record_visit(%Order{}), do: {:error, :not_closed}

  @doc "Número de visitas acumuladas por un cliente."
  def visit_count(customer_id) do
    Repo.aggregate(from(v in CustomerVisit, where: v.customer_id == ^customer_id), :count)
  end

  @doc "Lista las visitas de un cliente, más recientes primero (con la comanda precargada)."
  def list_visits_for_customer(customer_id) do
    from(v in CustomerVisit,
      where: v.customer_id == ^customer_id,
      order_by: [desc: v.recorded_at],
      preload: [:order]
    )
    |> Repo.all()
  end

  @doc """
  Herramienta de corrección: elimina la visita asociada a una comanda y rescinde
  (marca como `void`) las recompensas por visitas aún no redimidas que ya no
  correspondan al nuevo conteo.
  """
  def void_visit_for_order(order_id) do
    case Repo.get_by(CustomerVisit, order_id: order_id) do
      nil ->
        {:ok, :no_visit}

      %CustomerVisit{customer_id: customer_id} = visit ->
        Repo.transaction(fn ->
          Repo.delete!(visit)
          rescind_excess_visit_rewards(customer_id)
          :ok
        end)
    end
  end

  defp rescind_excess_visit_rewards(customer_id) do
    count = visit_count(customer_id)

    for tier <- all_visit_tiers() do
      entitled = entitled_cycles(count, tier)

      from(r in LoyaltyRedemption,
        where:
          r.customer_id == ^customer_id and r.loyalty_reward_id == ^tier.id and
            r.kind == "visits" and r.status == "earned" and r.cycle > ^entitled
      )
      |> Repo.update_all(set: [status: "void", updated_at: DateTime.utc_now()])
    end
  end

  # ---------------------------------------------------------------------------
  # Configuración de recompensas
  # ---------------------------------------------------------------------------

  @doc "Lista los niveles/configs de recompensa. Opción `:kind` para filtrar."
  def list_reward_tiers(opts \\ []) do
    LoyaltyReward
    |> maybe_filter_kind(Keyword.get(opts, :kind))
    |> order_by([r], asc: r.kind, asc: r.visits_required, asc: r.name)
    |> Repo.all()
  end

  @doc "Niveles por visitas activos, del menor al mayor número de visitas."
  def list_active_visit_tiers do
    all_visit_tiers()
  end

  defp all_visit_tiers do
    from(r in LoyaltyReward,
      where: r.kind == "visits" and r.active == true,
      order_by: [asc: r.visits_required]
    )
    |> Repo.all()
  end

  @doc "Config de cumpleaños activa, o `nil`."
  def get_birthday_reward do
    Repo.one(from r in LoyaltyReward, where: r.kind == "birthday" and r.active == true, limit: 1)
  end

  def get_reward!(id), do: Repo.get!(LoyaltyReward, id)

  def create_reward(attrs) do
    %LoyaltyReward{}
    |> LoyaltyReward.changeset(attrs)
    |> Repo.insert()
  end

  def update_reward(%LoyaltyReward{} = reward, attrs) do
    reward
    |> LoyaltyReward.changeset(attrs)
    |> Repo.update()
  end

  def delete_reward(%LoyaltyReward{} = reward), do: Repo.delete(reward)

  def change_reward(%LoyaltyReward{} = reward, attrs \\ %{}) do
    LoyaltyReward.changeset(reward, attrs)
  end

  defp maybe_filter_kind(query, nil), do: query
  defp maybe_filter_kind(query, kind), do: where(query, [r], r.kind == ^kind)

  # ---------------------------------------------------------------------------
  # Motor de recompensas
  # ---------------------------------------------------------------------------

  @doc """
  Evalúa todos los niveles de visitas activos para un cliente y otorga las
  redenciones que le correspondan según su conteo actual de visitas.

  Retro-otorga: si se crea un nivel de 6 visitas cuando el cliente ya tiene 20,
  en la siguiente evaluación se le otorgan los 3 ciclos. El índice único
  `(customer_id, loyalty_reward_id, cycle)` hace la operación segura ante
  concurrencia.

  Devuelve `{:ok, [redenciones_nuevas]}`.
  """
  def evaluate_rewards_after_visit(%Customer{id: id}), do: evaluate_rewards_after_visit(id)

  def evaluate_rewards_after_visit(customer_id) when is_integer(customer_id) do
    count = visit_count(customer_id)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    new_redemptions =
      for tier <- all_visit_tiers(),
          entitled = entitled_cycles(count, tier),
          existing = earned_cycle_count(customer_id, tier.id),
          entitled > existing,
          cycle <- (existing + 1)..entitled,
          redemption = insert_visit_redemption(customer_id, tier, cycle, count, now),
          not is_nil(redemption) do
        redemption
      end

    {:ok, new_redemptions}
  end

  # Cuántos ciclos completos ha ganado el cliente para este nivel.
  defp entitled_cycles(_count, %LoyaltyReward{visits_required: req}) when is_nil(req) or req <= 0,
    do: 0

  defp entitled_cycles(count, %LoyaltyReward{visits_required: req, repeatable: true}),
    do: div(count, req)

  defp entitled_cycles(count, %LoyaltyReward{visits_required: req, repeatable: false}),
    do: if(count >= req, do: 1, else: 0)

  defp earned_cycle_count(customer_id, reward_id) do
    Repo.aggregate(
      from(r in LoyaltyRedemption,
        where:
          r.customer_id == ^customer_id and r.loyalty_reward_id == ^reward_id and
            r.kind == "visits" and r.status != "void"
      ),
      :count
    )
  end

  defp insert_visit_redemption(customer_id, %LoyaltyReward{} = tier, cycle, count, now) do
    %LoyaltyRedemption{}
    |> LoyaltyRedemption.changeset(%{
      customer_id: customer_id,
      loyalty_reward_id: tier.id,
      kind: "visits",
      benefit_snapshot: tier.benefit,
      visits_required_snapshot: tier.visits_required,
      cycle: cycle,
      earned_at: now,
      earned_at_visit_count: count,
      status: "earned"
    })
    |> Repo.insert()
    |> case do
      {:ok, redemption} -> redemption
      {:error, _} -> nil
    end
  end

  @doc """
  Otorga el beneficio de cumpleaños al cliente si hoy (± ventana configurada) es
  su cumpleaños y hay una config activa. Una sola vez por año.

  Devuelve `{:ok, redemption}`, `{:ok, :already_granted}`,
  `{:error, :no_birthday_config}` o `{:error, :not_birthday}`.
  """
  def grant_birthday_reward(%Customer{} = customer, today \\ Date.utc_today()) do
    case get_birthday_reward() do
      nil ->
        {:error, :no_birthday_config}

      %LoyaltyReward{} = reward ->
        if birthday_today?(customer, today, reward.birthday_window_days) do
          now = DateTime.utc_now() |> DateTime.truncate(:second)

          %LoyaltyRedemption{}
          |> LoyaltyRedemption.changeset(%{
            customer_id: customer.id,
            loyalty_reward_id: reward.id,
            kind: "birthday",
            benefit_snapshot: reward.benefit,
            cycle: 1,
            earned_at: now,
            status: "earned",
            birthday_year: today.year
          })
          |> Repo.insert()
          |> case do
            {:ok, redemption} ->
              {:ok, redemption}

            {:error, changeset} ->
              if unique_error?(changeset), do: {:ok, :already_granted}, else: {:error, changeset}
          end
        else
          {:error, :not_birthday}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Recompensas pendientes / redención
  # ---------------------------------------------------------------------------

  @doc "Recompensas ganadas y sin redimir de un cliente, más antiguas primero."
  def pending_rewards_for(customer_id) do
    from(r in LoyaltyRedemption,
      where: r.customer_id == ^customer_id and r.status == "earned",
      order_by: [asc: r.earned_at, asc: r.id],
      preload: [:loyalty_reward]
    )
    |> Repo.all()
  end

  @doc "La recompensa pendiente más antigua de un cliente, o `nil`."
  def pending_reward_for(customer_id) do
    customer_id |> pending_rewards_for() |> List.first()
  end

  def has_pending_reward?(customer_id) do
    Repo.exists?(
      from r in LoyaltyRedemption,
        where: r.customer_id == ^customer_id and r.status == "earned"
    )
  end

  @doc "Historial de recompensas (ganadas/redimidas/anuladas) de un cliente."
  def list_redemptions_for_customer(customer_id) do
    from(r in LoyaltyRedemption,
      where: r.customer_id == ^customer_id,
      order_by: [desc: r.earned_at, desc: r.id],
      preload: [:loyalty_reward, :order, :redeemed_by]
    )
    |> Repo.all()
  end

  def get_redemption!(id), do: Repo.get!(LoyaltyRedemption, id)

  @doc """
  Resumen ligero de lealtad de un cliente, para el banner del mostrador.

  `%{customer, visit_count, pending_reward, pending_count, birthday_today?,
     birthday_reward, birthday_grantable?, top_items}`.
  """
  def customer_counter_summary(customer_id) do
    customer = get_customer(customer_id)

    if is_nil(customer) do
      nil
    else
      today = Date.utc_today()
      birthday_reward = get_birthday_reward()
      pending = pending_rewards_for(customer_id)

      bday_today? =
        (birthday_reward &&
           birthday_today?(customer, today, birthday_reward.birthday_window_days)) || false

      %{
        customer: customer,
        visit_count: visit_count(customer_id),
        pending_reward: List.first(pending),
        pending_count: length(pending),
        birthday_today?: bday_today?,
        birthday_reward: birthday_reward,
        birthday_grantable?:
          bday_today? && not birthday_granted_this_year?(customer_id, today.year),
        top_items: Orders.customer_top_items(customer_id, 3)
      }
    end
  end

  @doc """
  Todo lo que necesita la ficha del cliente en el admin, en una llamada:
  `%{customer, visit_count, pending_rewards, redemptions, spend, top_items,
     orders, birthday_today?, birthday_reward}`.
  """
  def customer_profile(customer_id) do
    case get_customer(customer_id) do
      nil ->
        nil

      customer ->
        %{
          customer: customer,
          visit_count: visit_count(customer_id),
          pending_rewards: pending_rewards_for(customer_id),
          redemptions: list_redemptions_for_customer(customer_id),
          spend: Orders.customer_spend_summary(customer_id),
          top_items: Orders.customer_top_items(customer_id, 10),
          orders: Orders.list_orders_history(:all, customer_id: customer_id),
          birthday_today?: birthday_today?(customer),
          birthday_reward: get_birthday_reward()
        }
    end
  end

  # ---------------------------------------------------------------------------
  # Paquetes personalizados
  # ---------------------------------------------------------------------------

  @doc "Paquetes personales de un cliente."
  def list_personal_packages(customer_id), do: CRC.Catalog.list_personal_packages(customer_id)

  @doc """
  Crea un paquete personal para un cliente.

  `attrs` = %{name, description, price}; `items` = lista de
  `%{menu_item_id, quantity}`.
  """
  def create_personal_package(%Customer{id: customer_id}, attrs, items) do
    attrs =
      attrs
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.put("customer_id", customer_id)

    with {:ok, package} <- CRC.Catalog.create_package(attrs),
         {:ok, _} <- CRC.Catalog.set_package_items(package, normalize_items(items)) do
      {:ok, CRC.Catalog.get_package!(package.id)}
    end
  end

  defp normalize_items(items) do
    items
    |> Enum.map(fn item ->
      m = Map.new(item)

      %{
        menu_item_id: to_int(m[:menu_item_id] || m["menu_item_id"]),
        quantity: to_int(m[:quantity] || m["quantity"] || 1)
      }
    end)
    |> Enum.filter(&(&1.menu_item_id && &1.quantity > 0))
  end

  defp to_int(nil), do: nil
  defp to_int(n) when is_integer(n), do: n

  defp to_int(s) when is_binary(s),
    do:
      case(Integer.parse(s),
        do: (
          {n, _} -> n
          _ -> nil
        )
      )

  defp birthday_granted_this_year?(customer_id, year) do
    Repo.exists?(
      from r in LoyaltyRedemption,
        where:
          r.customer_id == ^customer_id and r.kind == "birthday" and
            r.birthday_year == ^year
    )
  end

  @doc """
  Redime una recompensa ganada.

  Con una comanda: la marca como redimida y, si el nivel tiene
  `benefit_menu_item_id`, inserta una línea de cortesía a $0 en la comanda
  (marcada con `loyalty_redemption_id`). Sin comanda (`nil`): solo la marca como
  entregada (uso desde el panel admin).

  Devuelve `{:ok, redemption}` o `{:error, :not_pending | changeset}`.
  """
  def redeem_reward(%LoyaltyRedemption{status: "earned"} = redemption, order, staff_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    reward = redemption.loyalty_reward_id && Repo.get(LoyaltyReward, redemption.loyalty_reward_id)

    result =
      Repo.transaction(fn ->
        {:ok, updated} =
          redemption
          |> LoyaltyRedemption.redeem_changeset(%{
            status: "redeemed",
            redeemed_at: now,
            redeemed_by_id: staff_id,
            order_id: order && order.id
          })
          |> Repo.update()

        if order && reward && reward.benefit_menu_item_id do
          {:ok, _item} =
            %OrderItem{}
            |> OrderItem.changeset(%{
              order_id: order.id,
              menu_item_id: reward.benefit_menu_item_id,
              quantity: 1,
              unit_price: Decimal.new(0),
              status: "pending",
              loyalty_redemption_id: updated.id,
              notes: "🎁 Recompensa de lealtad: #{redemption.benefit_snapshot}"
            })
            |> Repo.insert()
        end

        updated
      end)

    case result do
      {:ok, updated} ->
        if order, do: Orders.broadcast_order_updated(order.id)
        {:ok, updated}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def redeem_reward(%LoyaltyRedemption{}, _order, _staff_id), do: {:error, :not_pending}

  @doc "Revierte una redención: vuelve a `earned` y elimina la línea de cortesía."
  def unredeem_reward(%LoyaltyRedemption{status: "redeemed"} = redemption) do
    order_id = redemption.order_id

    result =
      Repo.transaction(fn ->
        from(oi in OrderItem, where: oi.loyalty_redemption_id == ^redemption.id)
        |> Repo.delete_all()

        {:ok, updated} =
          redemption
          |> LoyaltyRedemption.redeem_changeset(%{
            status: "earned",
            redeemed_at: nil,
            redeemed_by_id: nil,
            order_id: nil
          })
          |> Repo.update()

        updated
      end)

    case result do
      {:ok, updated} ->
        if order_id, do: Orders.broadcast_order_updated(order_id)
        {:ok, updated}

      other ->
        other
    end
  end

  def unredeem_reward(%LoyaltyRedemption{}), do: {:error, :not_redeemed}

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp normalize_query(nil), do: nil

  defp normalize_query(query) when is_binary(query) do
    case String.trim(query) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp filter_by_status(query, :all), do: query
  defp filter_by_status(query, :inactive), do: where(query, [c], c.active == false)
  defp filter_by_status(query, _active), do: where(query, [c], c.active == true)

  defp filter_by_query(query, nil), do: query

  defp filter_by_query(query, text) do
    pattern = "%#{escape_like(text)}%"
    where(query, [c], ilike(c.name, ^pattern) or ilike(c.phone, ^pattern))
  end

  defp escape_like(text) do
    text
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  defp maybe_exclude_id(query, nil), do: query
  defp maybe_exclude_id(query, id), do: where(query, [c], c.id != ^id)

  defp maybe_put_created_by(attrs, nil), do: attrs

  defp maybe_put_created_by(attrs, %{id: id}) do
    string_keyed? = Enum.any?(Map.keys(attrs), &is_binary/1)

    if string_keyed?,
      do: Map.put(attrs, "created_by_id", id),
      else: Map.put(attrs, :created_by_id, id)
  end

  defp foreign_key_error?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn {_field, {_msg, opts}} ->
      Keyword.get(opts, :constraint) == :foreign
    end)
  end

  defp unique_error?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn {_field, {_msg, opts}} ->
      Keyword.get(opts, :constraint) == :unique
    end)
  end
end
