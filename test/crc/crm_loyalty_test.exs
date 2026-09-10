defmodule CRC.CRMLoyaltyTest do
  use CRC.DataCase, async: true

  import CRC.E2EFixtures

  alias CRC.CRM
  alias CRC.CRM.LoyaltyRedemption
  alias CRC.Orders
  alias CRC.Repo

  # A closed order tied to a customer, without going through the fixture helper
  # (so tests can assert the pieces individually).
  defp closed_order(customer, staff) do
    order = create_order()
    associate_customer(order, customer)

    {:ok, closed} =
      Orders.close_order(
        Orders.get_order!(order.id),
        %{payment_method: "efectivo", amount_paid: Decimal.new(200)},
        staff.id
      )

    closed
  end

  describe "record_visit/1" do
    setup do
      %{staff: create_waiter(), customer: create_customer()}
    end

    test "records one visit per closed order", %{customer: customer, staff: staff} do
      closed = closed_order(customer, staff)

      assert {:ok, visit} = CRM.record_visit(closed)
      assert visit.customer_id == customer.id
      assert visit.recorded_at == closed.closed_at
      assert CRM.visit_count(customer.id) == 1
    end

    test "is idempotent — re-recording the same order does nothing", %{
      customer: customer,
      staff: staff
    } do
      closed = closed_order(customer, staff)

      assert {:ok, _} = CRM.record_visit(closed)
      assert {:ok, :already_recorded} = CRM.record_visit(closed)
      assert CRM.visit_count(customer.id) == 1
    end

    test "refuses an order with no customer", %{staff: staff} do
      order = create_order()

      {:ok, closed} =
        Orders.close_order(
          Orders.get_order!(order.id),
          %{payment_method: "efectivo", amount_paid: Decimal.new(1)},
          staff.id
        )

      assert {:error, :no_customer} = CRM.record_visit(closed)
    end

    test "refuses an open order", %{customer: customer} do
      order = create_order() |> associate_customer(customer)
      assert {:error, :not_closed} = CRM.record_visit(order)
    end
  end

  describe "evaluate_rewards_after_visit/1 — visit tiers" do
    setup do
      %{staff: create_waiter(), customer: create_customer()}
    end

    defp reward_ids(customer) do
      CRM.pending_rewards_for(customer.id) |> Enum.map(& &1.loyalty_reward_id)
    end

    defp record_n_visits(customer, staff, n) do
      for _ <- 1..n do
        closed = closed_order(customer, staff)
        {:ok, _} = CRM.record_visit(closed)
      end

      CRM.evaluate_rewards_after_visit(customer.id)
    end

    test "non-repeatable tier fires once at the threshold and never again", %{
      customer: customer,
      staff: staff
    } do
      create_reward_tier(%{visits_required: 3, repeatable: false, benefit: "Galleta"})

      record_n_visits(customer, staff, 2)
      assert CRM.pending_rewards_for(customer.id) == []

      record_n_visits(customer, staff, 1)

      assert [%LoyaltyRedemption{cycle: 1, benefit_snapshot: "Galleta"}] =
               CRM.pending_rewards_for(customer.id)

      record_n_visits(customer, staff, 3)
      assert length(CRM.pending_rewards_for(customer.id)) == 1
    end

    test "repeatable tier fires every N visits with an incrementing cycle", %{
      customer: customer,
      staff: staff
    } do
      create_reward_tier(%{visits_required: 3, repeatable: true, benefit: "Café"})

      record_n_visits(customer, staff, 9)

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

      record_n_visits(customer, staff, 3)
      assert reward_ids(customer) == [a.id]

      record_n_visits(customer, staff, 3)
      # tier A fired a 2nd cycle (6/3) and tier B fired its 1st (6/6)
      assert Enum.sort(reward_ids(customer)) == Enum.sort([a.id, a.id, b.id])
    end

    test "a tier created after the fact back-grants the earned cycles", %{
      customer: customer,
      staff: staff
    } do
      for _ <- 1..10 do
        closed = closed_order(customer, staff)
        {:ok, _} = CRM.record_visit(closed)
      end

      # No tier existed while the visits accumulated
      assert CRM.pending_rewards_for(customer.id) == []

      create_reward_tier(%{visits_required: 3, repeatable: true, benefit: "Café"})
      {:ok, granted} = CRM.evaluate_rewards_after_visit(customer.id)

      # 10 visits / 3 = 3 completed cycles
      assert length(granted) == 3
    end

    test "deactivating a tier stops new grants but keeps earned ones", %{
      customer: customer,
      staff: staff
    } do
      tier = create_reward_tier(%{visits_required: 2, repeatable: true, benefit: "Café"})

      record_n_visits(customer, staff, 2)
      assert length(CRM.pending_rewards_for(customer.id)) == 1

      {:ok, _} = CRM.update_reward(tier, %{active: false})
      record_n_visits(customer, staff, 4)

      assert length(CRM.pending_rewards_for(customer.id)) == 1
    end

    test "changing the benefit text does not rewrite earned redemptions", %{
      customer: customer,
      staff: staff
    } do
      tier = create_reward_tier(%{visits_required: 2, benefit: "Café chico"})
      record_n_visits(customer, staff, 2)

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

      closed = closed_order(customer, staff)
      {:ok, _} = CRM.record_visit(closed)
      {:ok, [redemption]} = CRM.evaluate_rewards_after_visit(customer.id)

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
      closed = closed_order(customer, staff)
      {:ok, _} = CRM.record_visit(closed)
      {:ok, [redemption]} = CRM.evaluate_rewards_after_visit(customer.id)

      assert {:ok, updated} = CRM.redeem_reward(redemption, nil, staff.id)
      assert updated.status == "redeemed"
      assert updated.order_id == nil
    end

    test "refuses to redeem twice", %{staff: staff, customer: customer} do
      create_reward_tier(%{visits_required: 1, benefit: "Café gratis"})
      closed = closed_order(customer, staff)
      {:ok, _} = CRM.record_visit(closed)
      {:ok, [redemption]} = CRM.evaluate_rewards_after_visit(customer.id)

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

      closed = closed_order(customer, staff)
      {:ok, _} = CRM.record_visit(closed)
      {:ok, [redemption]} = CRM.evaluate_rewards_after_visit(customer.id)

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

      orders =
        for _ <- 1..3 do
          closed = closed_order(customer, staff)
          {:ok, _} = CRM.record_visit(closed)
          closed
        end

      {:ok, _} = CRM.evaluate_rewards_after_visit(customer.id)
      assert length(CRM.pending_rewards_for(customer.id)) == 1

      {:ok, _} = CRM.void_visit_for_order(List.first(orders).id)

      assert CRM.visit_count(customer.id) == 2
      assert [%{status: "void"}] = Repo.all(LoyaltyRedemption)
      assert CRM.pending_rewards_for(customer.id) == []
    end
  end
end
