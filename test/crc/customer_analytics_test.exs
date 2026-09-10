defmodule CRC.CustomerAnalyticsTest do
  use CRC.DataCase, async: true

  import CRC.E2EFixtures

  alias CRC.CRM
  alias CRC.Orders

  setup do
    staff = create_waiter()
    customer = create_customer(%{name: "Analítica"})
    dish = create_food_item(create_category().id, "Latte")
    %{staff: staff, customer: customer, dish: dish}
  end

  defp closed_order_with(customer, staff, dish, qty) do
    order = create_order(%{customer_name: "c", user_id: staff.id}) |> associate_customer(customer)
    add_item(order.id, dish.id, qty)
    close_order_for(order, staff)
  end

  test "customer_spend_summary aggregates only that customer's closed orders", %{
    staff: staff,
    customer: customer,
    dish: dish
  } do
    closed_order_with(customer, staff, dish, 1)
    closed_order_with(customer, staff, dish, 2)
    # a different customer's order should not count
    other = create_customer(%{name: "Otro"})
    closed_order_with(other, staff, dish, 5)
    # an open order for our customer should not count
    _open = create_order(%{customer_name: "x", user_id: staff.id}) |> associate_customer(customer)

    s = Orders.customer_spend_summary(customer.id)
    assert s.order_count == 2
    assert Decimal.gt?(s.total_spend, Decimal.new(0))
    assert s.first_order_at
    assert s.last_order_at
  end

  test "customer_top_items ranks by quantity for that customer", %{
    staff: staff,
    customer: customer,
    dish: dish
  } do
    closed_order_with(customer, staff, dish, 3)
    assert [{"Latte", 3}] = Orders.customer_top_items(customer.id, 10)
  end

  test "list_orders_history filters by customer", %{staff: staff, customer: customer, dish: dish} do
    closed_order_with(customer, staff, dish, 1)
    assert [_one] = Orders.list_orders_history(:all, customer_id: customer.id)
  end

  test "customer_profile bundles everything", %{staff: staff, customer: customer, dish: dish} do
    create_reward_tier(%{visits_required: 1, benefit: "Café gratis"})
    closed_order_with(customer, staff, dish, 1)

    p = CRM.customer_profile(customer.id)
    assert p.visit_count == 1
    assert p.spend.order_count == 1
    assert [{"Latte", 1}] = p.top_items
    assert [%{benefit_snapshot: "Café gratis"}] = p.pending_rewards
  end
end
