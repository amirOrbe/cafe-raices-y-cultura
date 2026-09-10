defmodule CRC.CRMLoyaltyTest do
  use CRC.DataCase, async: true

  import CRC.E2EFixtures

  alias CRC.CRM
  alias CRC.CRM.LoyaltyRedemption
  alias CRC.Orders
  alias CRC.Repo

  # Closes a fresh order for the customer. `Orders.close_order/3` runs the
  # loyalty hook itself (records the visit + evaluates rewards), so this is all
  # a test needs to accrue a visit.
  defp visit(customer, staff) do
    order = create_order() |> associate_customer(customer)
    {:ok, closed} = close(order, staff)
    closed
  end

  defp visit_n(customer, staff, n), do: Enum.each(1..n, fn _ -> visit(customer, staff) end)

  defp close(order, staff) do
    Orders.close_order(
      Orders.get_order!(order.id),
      %{payment_method: "efectivo", amount_paid: Decimal.new(200)},
      staff && staff.id
    )
  end

  defp reward_ids(customer),
    do: CRM.pending_rewards_for(customer.id) |> Enum.map(& &1.loyalty_reward_id)

  describe "record_visit/1" do
    setup do
      %{staff: create_waiter(), customer: create_customer()}
    end

    test "one visit per closed order", %{customer: customer, staff: staff} do
      closed = visit(customer, staff)
      assert CRM.visit_count(customer.id) == 1
      assert [%{recorded_at: recorded}] = CRM.list_visits_for_customer(customer.id)
      assert recorded == closed.closed_at
    end

    test "is idempotent — re-recording the same order does nothing", %{
      customer: customer,
      staff: staff
    } do
      closed = visit(customer, staff)
      assert {:ok, :already_recorded} = CRM.record_visit(closed)
      assert CRM.visit_count(customer.id) == 1
    end

    test "refuses an order with no customer", %{staff: staff} do
      {:ok, closed} = close(create_order(), staff)
      assert {:error, :no_customer} = CRM.record_visit(closed)
    end

    test "refuses an open order", %{customer: customer} do
      order = create_order() |> associate_customer(customer)
      assert {:error, :not_closed} = CRM.record_visit(order)
    end
  end

  describe "Orders.close_order/3 loyalty hook" do
    setup do
      %{staff: create_waiter(), customer: create_customer()}
    end

    test "closing without a customer records no visit", %{staff: staff} do
      {:ok, _} = close(create_order(), staff)
      assert Repo.aggregate(CRC.CRM.CustomerVisit, :count) == 0
    end

    test "re-closing the same order does not double-count", %{customer: customer, staff: staff} do
      closed = visit(customer, staff)
      {:ok, _} = Orders.close_order(closed, %{payment_method: "tarjeta"}, staff.id)
      assert CRM.visit_count(customer.id) == 1
    end

    test "awards a reward when the visit crosses a tier", %{customer: customer, staff: staff} do
      create_reward_tier(%{visits_required: 1, benefit: "Café gratis"})
      visit(customer, staff)

      assert [%LoyaltyRedemption{benefit_snapshot: "Café gratis"}] =
               CRM.pending_rewards_for(customer.id)
    end
  end

  describe "reward engine — visit tiers" do
    setup do
      %{staff: create_waiter(), customer: create_customer()}
    end

    test "non-repeatable tier fires once at the threshold and never again", %{
      customer: customer,
      staff: staff
    } do
      create_reward_tier(%{visits_required: 3, repeatable: false, benefit: "Galleta"})

      visit_n(customer, staff, 2)
      assert CRM.pending_rewards_for(customer.id) == []

      visit(customer, staff)

      assert [%LoyaltyRedemption{cycle: 1, benefit_snapshot: "Galleta"}] =
               CRM.pending_rewards_for(customer.id)

      visit_n(customer, staff, 3)
      assert length(CRM.pending_rewards_for(customer.id)) == 1
    end

    test "repeatable tier fires every N visits with an incrementing cycle", %{
      customer: customer,
      staff: staff
    } do
      create_reward_tier(%{visits_required: 3, repeatable: true, benefit: "Café"})
      visit_n(customer, staff, 9)

      cycles =
        CRM.list_redemptions_for_customer(customer.id)
        |> Enum.filter(&(&1.kind == "visits"))
        |> Enum.map(& &1.cycle)
        |> Enum.sort()

      assert cycles == [1, 2, 3]
    end

    test "two tiers fire independently at their own thresholds", %{
      customer: customer,
      staff: staff
    } do
      a = create_reward_tier(%{visits_required: 3, name: "A", benefit: "Galleta"})
      b = create_reward_tier(%{visits_required: 6, name: "B", benefit: "Café"})

      visit_n(customer, staff, 3)
      assert reward_ids(customer) == [a.id]

      visit_n(customer, staff, 3)
      assert Enum.sort(reward_ids(customer)) == Enum.sort([a.id, a.id, b.id])
    end

    test "a tier created after the fact back-grants the earned cycles", %{
      customer: customer,
      staff: staff
    } do
      visit_n(customer, staff, 10)
      assert CRM.pending_rewards_for(customer.id) == []

      create_reward_tier(%{visits_required: 3, repeatable: true, benefit: "Café"})
      {:ok, granted} = CRM.evaluate_rewards_after_visit(customer.id)

      assert length(granted) == 3
    end

    test "deactivating a tier stops new grants but keeps earned ones", %{
      customer: customer,
      staff: staff
    } do
      tier = create_reward_tier(%{visits_required: 2, repeatable: true, benefit: "Café"})

      visit_n(customer, staff, 2)
      assert length(CRM.pending_rewards_for(customer.id)) == 1

      {:ok, _} = CRM.update_reward(tier, %{active: false})
      visit_n(customer, staff, 4)

      assert length(CRM.pending_rewards_for(customer.id)) == 1
    end

    test "changing the benefit text does not rewrite earned redemptions", %{
      customer: customer,
      staff: staff
    } do
      tier = create_reward_tier(%{visits_required: 2, benefit: "Café chico"})
      visit_n(customer, staff, 2)

      {:ok, _} = CRM.update_reward(tier, %{benefit: "Café grande"})
      assert [%{benefit_snapshot: "Café chico"}] = CRM.pending_rewards_for(customer.id)
    end
  end

  describe "redeem_reward/3" do
    setup do
      dish = create_food_item(create_category().id, "Café de olla")
      %{staff: create_waiter(), customer: create_customer(), dish: dish}
    end

    test "with a menu item inserts a $0 comp line tagged with the redemption", %{
      staff: staff,
      customer: customer,
      dish: dish
    } do
      create_reward_tier(%{
        visits_required: 1,
        benefit: "Café gratis",
        benefit_menu_item_id: dish.id
      })

      visit(customer, staff)
      redemption = CRM.pending_reward_for(customer.id)

      order = create_order() |> associate_customer(customer)
      assert {:ok, updated} = CRM.redeem_reward(redemption, order, staff.id)
      assert updated.status == "redeemed"
      assert updated.order_id == order.id

      order = Orders.get_order!(order.id)
      comp = Enum.find(order.order_items, &(&1.loyalty_redemption_id == redemption.id))
      assert comp
      assert Decimal.equal?(comp.unit_price, Decimal.new(0))
      assert comp.menu_item_id == dish.id
      assert Decimal.equal?(Orders.calculate_order_total(order), Decimal.new(0))
    end

    test "without an order just marks it delivered", %{staff: staff, customer: customer} do
      create_reward_tier(%{visits_required: 1, benefit: "Café gratis"})
      visit(customer, staff)
      redemption = CRM.pending_reward_for(customer.id)

      assert {:ok, updated} = CRM.redeem_reward(redemption, nil, staff.id)
      assert updated.status == "redeemed"
      assert updated.order_id == nil
    end

    test "refuses to redeem twice", %{staff: staff, customer: customer} do
      create_reward_tier(%{visits_required: 1, benefit: "Café gratis"})
      visit(customer, staff)
      redemption = CRM.pending_reward_for(customer.id)

      {:ok, redeemed} = CRM.redeem_reward(redemption, nil, staff.id)
      assert {:error, :not_pending} = CRM.redeem_reward(redeemed, nil, staff.id)
    end

    test "unredeem reverts the status and removes the comp line", %{
      staff: staff,
      customer: customer,
      dish: dish
    } do
      create_reward_tier(%{
        visits_required: 1,
        benefit: "Café gratis",
        benefit_menu_item_id: dish.id
      })

      visit(customer, staff)
      redemption = CRM.pending_reward_for(customer.id)

      order = create_order() |> associate_customer(customer)
      {:ok, redeemed} = CRM.redeem_reward(redemption, order, staff.id)

      assert {:ok, reverted} = CRM.unredeem_reward(redeemed)
      assert reverted.status == "earned"

      order = Orders.get_order!(order.id)
      refute Enum.any?(order.order_items, &(&1.loyalty_redemption_id == redemption.id))
    end
  end

  describe "grant_birthday_reward/2" do
    setup do
      %{customer: create_customer(%{birthday: ~D[1990-06-15]})}
    end

    test "grants once on the birthday", %{customer: customer} do
      create_birthday_reward(%{benefit: "Rebanada de pastel"})

      assert {:ok, %LoyaltyRedemption{kind: "birthday", birthday_year: 2026}} =
               CRM.grant_birthday_reward(customer, ~D[2026-06-15])

      assert {:ok, :already_granted} = CRM.grant_birthday_reward(customer, ~D[2026-06-15])
    end

    test "grants again the following year", %{customer: customer} do
      create_birthday_reward()
      {:ok, _} = CRM.grant_birthday_reward(customer, ~D[2026-06-15])
      assert {:ok, %{birthday_year: 2027}} = CRM.grant_birthday_reward(customer, ~D[2027-06-15])
    end

    test "errors when there is no active config", %{customer: customer} do
      assert {:error, :no_birthday_config} = CRM.grant_birthday_reward(customer, ~D[2026-06-15])
    end

    test "errors when it is not the birthday", %{customer: customer} do
      create_birthday_reward()
      assert {:error, :not_birthday} = CRM.grant_birthday_reward(customer, ~D[2026-01-01])
    end

    test "honors the window", %{customer: customer} do
      create_birthday_reward(%{birthday_window_days: 3})
      assert {:ok, _} = CRM.grant_birthday_reward(customer, ~D[2026-06-17])
    end
  end

  describe "void_visit_for_order/1" do
    test "removes the visit and rescinds now-excess earned rewards" do
      staff = create_waiter()
      customer = create_customer()
      create_reward_tier(%{visits_required: 3, repeatable: true, benefit: "Café"})

      orders = Enum.map(1..3, fn _ -> visit(customer, staff) end)
      assert length(CRM.pending_rewards_for(customer.id)) == 1

      {:ok, _} = CRM.void_visit_for_order(List.first(orders).id)

      assert CRM.visit_count(customer.id) == 2
      assert [%{status: "void"}] = Repo.all(LoyaltyRedemption)
      assert CRM.pending_rewards_for(customer.id) == []
    end
  end
end
