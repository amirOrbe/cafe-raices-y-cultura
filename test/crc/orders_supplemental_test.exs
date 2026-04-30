defmodule CRC.OrdersSupplementalTest do
  @moduledoc """
  Supplemental tests targeting CRC.Orders functions not yet covered:
  - create_manual_order/3
  - set_item_notes/2
  - employee_rankings/1
  - Default argument coverage for list_closed_orders/0, sales_summary/0, financial_summary/0
  - decimal_or_zero via package_item path
  """
  use CRC.DataCase, async: true

  alias CRC.Orders
  alias CRC.Orders.Order
  alias CRC.Catalog
  alias CRC.Accounts.User

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp insert_user(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          name: "User Supp #{System.unique_integer()}",
          email: "supp#{System.unique_integer()}@cafe.com",
          role: "empleado",
          stations: ["sala"],
          password: "pass123456"
        },
        overrides
      )

    {:ok, user} = %User{} |> User.changeset(attrs) |> CRC.Repo.insert()
    user
  end

  defp insert_category do
    {:ok, cat} = Catalog.create_category(%{name: "Cat Supp #{System.unique_integer()}"})
    cat
  end

  defp insert_menu_item(category_id) do
    {:ok, item} =
      Catalog.create_menu_item(%{
        name: "Platillo Supp #{System.unique_integer()}",
        price: "50.00",
        category_id: category_id
      })

    item
  end

  # ---------------------------------------------------------------------------
  # create_manual_order/3
  # ---------------------------------------------------------------------------

  describe "create_manual_order/3" do
    test "GIVEN valid attrs and items WHEN creating manual order THEN order is closed and items served" do
      cat = insert_category()
      item = insert_menu_item(cat.id)

      attrs = %{
        "customer_name" => "Mesa 10",
        "payment_method" => "tarjeta",
        "total" => "100.00",
        "closed_at" => DateTime.utc_now()
      }

      items = [%{menu_item_id: item.id, quantity: 2}]

      assert {:ok, order} = Orders.create_manual_order(attrs, items)
      assert order.status == "closed"
      assert order.manual_entry == true
      assert order.customer_name == "Mesa 10"

      loaded = Orders.get_order!(order.id)
      assert length(loaded.order_items) == 1
      assert hd(loaded.order_items).status == "served"
      assert hd(loaded.order_items).quantity == 2
    end

    test "GIVEN valid attrs with closed_by_id WHEN creating manual order THEN closed_by is set" do
      cat = insert_category()
      item = insert_menu_item(cat.id)
      user = insert_user()

      attrs = %{
        "customer_name" => "Mesa 11",
        "payment_method" => "efectivo",
        "amount_paid" => "120.00",
        "total" => "100.00",
        "closed_at" => DateTime.utc_now()
      }

      items = [%{menu_item_id: item.id, quantity: 1}]

      assert {:ok, order} = Orders.create_manual_order(attrs, items, user.id)
      assert order.closed_by_id == user.id
    end

    test "GIVEN empty items list WHEN creating manual order THEN order is still created" do
      attrs = %{
        "customer_name" => "Mesa 12",
        "payment_method" => "tarjeta",
        "total" => "0.00",
        "closed_at" => DateTime.utc_now()
      }

      assert {:ok, order} = Orders.create_manual_order(attrs, [])
      assert order.status == "closed"
    end

    test "GIVEN invalid attrs WHEN creating manual order THEN transaction fails" do
      attrs = %{"payment_method" => "tarjeta"}

      # Missing customer_name — should cause changeset error and transaction rollback
      assert_raise Ecto.InvalidChangesetError, fn ->
        Orders.create_manual_order(attrs, [])
      end
    end

    test "GIVEN efectivo payment with amount_paid WHEN creating THEN order is valid" do
      cat = insert_category()
      item = insert_menu_item(cat.id)

      attrs = %{
        "customer_name" => "Mesa 13",
        "payment_method" => "efectivo",
        "amount_paid" => "150.00",
        "total" => "120.00",
        "closed_at" => DateTime.utc_now()
      }

      assert {:ok, order} =
               Orders.create_manual_order(attrs, [%{menu_item_id: item.id, quantity: 1}])

      assert order.manual_entry == true
    end
  end

  # ---------------------------------------------------------------------------
  # set_item_notes/2
  # ---------------------------------------------------------------------------

  describe "set_item_notes/2" do
    test "GIVEN existing order item WHEN setting notes THEN notes are saved" do
      cat = insert_category()
      item = insert_menu_item(cat.id)
      {:ok, order} = Orders.create_order(%{customer_name: "Notes Test"})

      {:ok, order_item} =
        Orders.add_item(%{order_id: order.id, menu_item_id: item.id, quantity: 1})

      assert {:ok, updated} = Orders.set_item_notes(order_item.id, "Sin sal, por favor")
      assert updated.notes == "Sin sal, por favor"
    end

    test "GIVEN non-existent order item id WHEN setting notes THEN returns error" do
      assert {:error, :not_found} = Orders.set_item_notes(0, "Some notes")
    end

    test "GIVEN existing item WHEN clearing notes THEN notes become nil" do
      cat = insert_category()
      item = insert_menu_item(cat.id)
      {:ok, order} = Orders.create_order(%{customer_name: "Clear Notes"})

      {:ok, order_item} =
        Orders.add_item(%{order_id: order.id, menu_item_id: item.id, quantity: 1})

      {:ok, _} = Orders.set_item_notes(order_item.id, "Some note")
      assert {:ok, updated} = Orders.set_item_notes(order_item.id, nil)
      assert is_nil(updated.notes)
    end
  end

  # ---------------------------------------------------------------------------
  # Default argument coverage for list_closed_orders/0, sales_summary/0, financial_summary/0
  # ---------------------------------------------------------------------------

  describe "list_closed_orders/0 default arg" do
    test "GIVEN no arguments WHEN calling list_closed_orders THEN returns list" do
      result = Orders.list_closed_orders()
      assert is_list(result)
    end
  end

  describe "sales_summary/0 default arg" do
    test "GIVEN no arguments WHEN calling sales_summary THEN returns summary map" do
      result = Orders.sales_summary()
      assert is_map(result)
      assert Map.has_key?(result, :total_revenue)
      assert Map.has_key?(result, :order_count)
    end
  end

  describe "financial_summary/0 default arg" do
    test "GIVEN no arguments WHEN calling financial_summary THEN returns financial map" do
      result = Orders.financial_summary()
      assert is_map(result)
      assert Map.has_key?(result, :revenue)
      assert Map.has_key?(result, :cogs)
    end
  end

  # ---------------------------------------------------------------------------
  # employee_rankings/1
  # ---------------------------------------------------------------------------

  describe "employee_rankings/1" do
    test "GIVEN no closed non-manual orders WHEN calling with future range THEN returns empty lists" do
      future = {:range, ~D[2035-01-01], ~D[2035-01-02]}
      result = Orders.employee_rankings(future)

      assert result.revenue_ranking == []
      assert result.speed_ranking == []
    end

    test "GIVEN closed orders with waiter WHEN calling employee_rankings THEN returns revenue ranking" do
      user = insert_user(%{name: "Mesero Rankings #{System.unique_integer()}"})

      d = ~U[2027-11-01 10:00:00Z]

      CRC.Repo.insert!(%Order{
        customer_name: "Rank Order",
        status: "closed",
        payment_method: "tarjeta",
        total: Decimal.new("250.00"),
        closed_at: d,
        user_id: user.id,
        manual_entry: false,
        inserted_at: d,
        updated_at: d
      })

      result = Orders.employee_rankings({:range, ~D[2027-11-01], ~D[2027-11-01]})
      assert is_list(result.revenue_ranking)

      entry = Enum.find(result.revenue_ranking, &(&1.user_id == user.id))
      assert entry
      assert entry.order_count == 1
      assert entry.rank >= 1
    end

    test "GIVEN no arguments WHEN calling employee_rankings THEN returns map" do
      result = Orders.employee_rankings()
      assert is_map(result)
      assert Map.has_key?(result, :revenue_ranking)
      assert Map.has_key?(result, :speed_ranking)
    end
  end

  # ---------------------------------------------------------------------------
  # employee_stats/0 default argument
  # ---------------------------------------------------------------------------

  describe "employee_stats/0 default arg" do
    test "GIVEN no arguments WHEN calling employee_stats THEN returns map" do
      result = Orders.employee_stats()
      assert is_map(result)
      assert Map.has_key?(result, :station_stats)
      assert Map.has_key?(result, :waiter_stats)
    end
  end
end
