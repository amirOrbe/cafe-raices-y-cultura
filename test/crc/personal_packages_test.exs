defmodule CRC.PersonalPackagesTest do
  use CRC.DataCase, async: true

  import CRC.E2EFixtures

  alias CRC.Catalog
  alias CRC.CRM
  alias CRC.Orders

  setup do
    dish = create_food_item(create_category().id, "Latte")
    %{customer: create_customer(%{name: "VIP"}), dish: dish}
  end

  test "create_personal_package/3 makes a customer-scoped package", %{
    customer: customer,
    dish: dish
  } do
    assert {:ok, package} =
             CRM.create_personal_package(
               customer,
               %{"name" => "combo vip", "price" => "99"},
               [%{"menu_item_id" => to_string(dish.id), "quantity" => "2"}]
             )

    assert package.customer_id == customer.id
    assert [%{quantity: 2}] = package.package_items
  end

  test "list_packages/0 excludes personal packages", %{customer: customer, dish: dish} do
    {:ok, _} =
      CRM.create_personal_package(customer, %{"name" => "p", "price" => "10"}, [
        %{"menu_item_id" => to_string(dish.id), "quantity" => "1"}
      ])

    {:ok, _public} = Catalog.create_package(%{name: "Público", price: Decimal.new(50)})

    names = Catalog.list_packages() |> Enum.map(& &1.name)
    assert "Público" in names
    refute "P" in names
  end

  test "list_packages_for_order/1 includes the order customer's personal packages", %{
    customer: customer,
    dish: dish
  } do
    {:ok, _personal} =
      CRM.create_personal_package(customer, %{"name" => "Suyo", "price" => "10"}, [
        %{"menu_item_id" => to_string(dish.id), "quantity" => "1"}
      ])

    other = create_customer(%{name: "Otro"})

    {:ok, _other_personal} =
      CRM.create_personal_package(other, %{"name" => "Ajeno", "price" => "10"}, [
        %{"menu_item_id" => to_string(dish.id), "quantity" => "1"}
      ])

    {:ok, _public} = Catalog.create_package(%{name: "Público", price: Decimal.new(50)})

    order = create_order() |> associate_customer(customer)

    names =
      Orders.get_order!(order.id) |> Catalog.list_packages_for_order() |> Enum.map(& &1.name)

    assert "Público" in names
    assert "Suyo" in names
    refute "Ajeno" in names

    no_customer = create_order()
    assert Catalog.list_packages_for_order(no_customer) |> Enum.map(& &1.name) == ["Público"]
  end
end
