defmodule CRC.E2EFixtures do
  @moduledoc """
  Shared fixture helpers for end-to-end LiveView tests.

  Provides factory functions for creating users (by role/station),
  catalog items, orders, and tables. All functions insert directly
  into the test sandbox — no cleanup needed (DataCase handles rollback).
  """

  alias CRC.Accounts.User
  alias CRC.Catalog
  alias CRC.Orders

  # ---------------------------------------------------------------------------
  # User factories
  # ---------------------------------------------------------------------------

  @doc "Creates a user with the given attrs merged over safe defaults."
  def create_user(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          name: "Test User",
          email: "user#{System.unique_integer()}@e2e.test",
          role: "empleado",
          stations: ["sala"],
          password: "pass123456"
        },
        overrides
      )

    {:ok, user} = %User{} |> User.changeset(attrs) |> CRC.Repo.insert()
    user
  end

  @doc "Creates an employee with station 'sala' (waiter role)."
  def create_waiter(name \\ "Mesero") do
    create_user(%{
      name: name,
      email: "waiter#{System.unique_integer()}@e2e.test",
      role: "empleado",
      stations: ["sala"]
    })
  end

  @doc "Creates an employee with station 'cocina' (kitchen role)."
  def create_cocinero(name \\ "Cocinero") do
    create_user(%{
      name: name,
      email: "cocina#{System.unique_integer()}@e2e.test",
      role: "empleado",
      stations: ["cocina"]
    })
  end

  @doc "Creates an employee with station 'barra' (bar role)."
  def create_barman(name \\ "Barman") do
    create_user(%{
      name: name,
      email: "barra#{System.unique_integer()}@e2e.test",
      role: "empleado",
      stations: ["barra"]
    })
  end

  @doc "Creates an admin user."
  def create_admin(name \\ "Admin") do
    create_user(%{
      name: name,
      email: "admin#{System.unique_integer()}@e2e.test",
      role: "admin",
      stations: []
    })
  end

  # ---------------------------------------------------------------------------
  # Catalog factories
  # ---------------------------------------------------------------------------

  @doc "Creates a menu category with an auto-generated name."
  def create_category(name \\ nil) do
    {:ok, cat} = Catalog.create_category(%{name: name || "Cat E2E #{System.unique_integer()}"})
    cat
  end

  @doc "Creates a menu item routed to 'cocina' (food)."
  def create_food_item(category_id, name \\ nil) do
    {:ok, item} =
      Catalog.create_menu_item(%{
        name: name || "Platillo #{System.unique_integer()}",
        price: "80.00",
        category_id: category_id,
        destination: "cocina"
      })

    item
  end

  @doc "Creates a menu item routed to 'barra' (drinks)."
  def create_drink_item(category_id, name \\ nil) do
    {:ok, item} =
      Catalog.create_menu_item(%{
        name: name || "Bebida #{System.unique_integer()}",
        price: "50.00",
        category_id: category_id,
        destination: "barra"
      })

    item
  end

  # ---------------------------------------------------------------------------
  # Order factories
  # ---------------------------------------------------------------------------

  @doc "Creates an order with the given attrs merged over safe defaults."
  def create_order(attrs \\ %{}) do
    {:ok, order} = Orders.create_order(Map.merge(%{customer_name: "Cliente E2E"}, attrs))
    order
  end

  @doc "Adds a menu item to an existing order."
  def add_item(order_id, menu_item_id, qty \\ 1) do
    {:ok, item} =
      Orders.add_item(%{order_id: order_id, menu_item_id: menu_item_id, quantity: qty})

    item
  end

  # ---------------------------------------------------------------------------
  # Table factories
  # ---------------------------------------------------------------------------

  @doc "Creates a restaurant table with the given attrs merged over safe defaults."
  def create_table(overrides \\ %{}) do
    {:ok, table} =
      Orders.create_table(
        Map.merge(
          %{
            number: System.unique_integer([:positive]),
            label: "Mesa E2E #{System.unique_integer()}",
            capacity: 4,
            x_pct: 50.0,
            y_pct: 50.0
          },
          overrides
        )
      )

    table
  end

  # ---------------------------------------------------------------------------
  # CRM factories
  # ---------------------------------------------------------------------------

  @doc "Creates a loyalty customer with the given attrs merged over safe defaults."
  def create_customer(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          name: "Cliente Lealtad",
          phone: "55#{System.unique_integer([:positive])}"
        },
        Map.new(overrides)
      )

    {:ok, customer} = CRC.CRM.create_customer(attrs)
    customer
  end

  @doc "Creates a repeatable visits reward tier (default: 6 visits → free coffee)."
  def create_reward_tier(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          kind: "visits",
          name: "Tarjeta de lealtad",
          visits_required: 6,
          benefit: "Café gratis",
          repeatable: true,
          active: true
        },
        Map.new(overrides)
      )

    {:ok, reward} = CRC.CRM.create_reward(attrs)
    reward
  end

  @doc "Creates the active birthday reward config."
  def create_birthday_reward(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          kind: "birthday",
          name: "Cumpleaños",
          benefit: "Postre gratis",
          birthday_window_days: 0,
          active: true
        },
        Map.new(overrides)
      )

    {:ok, reward} = CRC.CRM.create_reward(attrs)
    reward
  end

  @doc "Associates a customer to an order."
  def associate_customer(order, customer) do
    {:ok, updated} = CRC.Orders.update_order(order, %{customer_id: customer.id})
    updated
  end

  @doc """
  Closes an order for a customer, recording the loyalty visit + evaluating
  rewards (mirrors what the close_order hook does in production).
  """
  def close_order_for(order, staff) do
    {:ok, closed} =
      CRC.Orders.close_order(
        CRC.Orders.get_order!(order.id),
        %{payment_method: "efectivo", amount_paid: Decimal.new(500)},
        staff && staff.id
      )

    if closed.customer_id do
      {:ok, _} = CRC.CRM.record_visit(closed)
      CRC.CRM.evaluate_rewards_after_visit(closed.customer_id)
    end

    closed
  end

  # ---------------------------------------------------------------------------
  # Auth helpers
  # ---------------------------------------------------------------------------

  @doc "Injects a user_id into the test session, simulating login."
  def auth_conn(conn, user) do
    Phoenix.ConnTest.init_test_session(conn, %{"user_id" => user.id})
  end
end
