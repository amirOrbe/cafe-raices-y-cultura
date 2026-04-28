defmodule CRC.ProductionOutputProductTest do
  @moduledoc """
  Tests for Inventory.find_product_by_name/1 and
  Inventory.find_or_create_production_output/2 — the auto-resolution of output
  products when creating production recipes.
  """

  use CRC.DataCase, async: true

  alias CRC.Inventory

  defp insert_product(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          name: "Producto Base #{System.unique_integer()}",
          unit: "gramos",
          net_cost: "5.00",
          stock_quantity: "100.0",
          min_stock: "10.0"
        },
        overrides
      )

    {:ok, product} = Inventory.create_product(attrs)
    product
  end

  # ---------------------------------------------------------------------------
  # find_product_by_name/1
  # ---------------------------------------------------------------------------

  describe "find_product_by_name/1" do
    test "GIVEN existing product WHEN searching with exact name THEN returns the product" do
      # GIVEN
      insert_product(%{name: "Oleo De Naranja"})

      # WHEN
      result = Inventory.find_product_by_name("Oleo De Naranja")

      # THEN
      assert result.name == "Oleo De Naranja"
    end

    test "GIVEN existing product WHEN searching with lowercase name THEN returns the product (case-insensitive)" do
      # GIVEN
      insert_product(%{name: "Oleo De Naranja"})

      # WHEN
      result = Inventory.find_product_by_name("oleo de naranja")

      # THEN
      assert result != nil
      assert result.name == "Oleo De Naranja"
    end

    test "GIVEN existing product WHEN searching with mixed case THEN returns the product" do
      # GIVEN
      insert_product(%{name: "Leche De Avena"})

      # WHEN
      result = Inventory.find_product_by_name("LECHE DE AVENA")

      # THEN
      assert result != nil
    end

    test "GIVEN no product with that name WHEN searching THEN returns nil" do
      # WHEN
      result = Inventory.find_product_by_name("Producto Inexistente XYZ")

      # THEN
      assert result == nil
    end

    test "GIVEN empty string WHEN searching THEN returns nil" do
      result = Inventory.find_product_by_name("")
      assert result == nil
    end
  end

  # ---------------------------------------------------------------------------
  # find_or_create_production_output/2
  # ---------------------------------------------------------------------------

  describe "find_or_create_production_output/2" do
    test "GIVEN product does not exist WHEN calling find_or_create THEN product is created with correct attrs" do
      # GIVEN: no product named "Oleo De Naranja" exists

      # WHEN
      assert {:ok, product} =
               Inventory.find_or_create_production_output("Oleo de Naranja", "mililitros")

      # THEN: product is created
      assert product.id
      assert product.unit == "mililitros"
      assert product.active == true
      assert Decimal.compare(product.net_cost, Decimal.new(0)) == :eq
      assert Decimal.compare(product.stock_quantity, Decimal.new(0)) == :eq
    end

    test "GIVEN product does not exist WHEN creating THEN name is title-cased" do
      # WHEN
      {:ok, product} = Inventory.find_or_create_production_output("oleo de naranja", "ml")

      # THEN: title case applied
      assert product.name == "Oleo De Naranja"
    end

    test "GIVEN product already exists WHEN calling find_or_create THEN existing product is returned" do
      # GIVEN: product already exists
      existing = insert_product(%{name: "Salsa Bbq"})

      # WHEN
      assert {:ok, found} =
               Inventory.find_or_create_production_output("Salsa Bbq", "gramos")

      # THEN: same product, no duplicate created
      assert found.id == existing.id
    end

    test "GIVEN product already exists WHEN calling find_or_create THEN no duplicate is inserted in DB" do
      # GIVEN
      insert_product(%{name: "Mantequilla De Maní"})
      initial_count = CRC.Repo.aggregate(CRC.Inventory.Product, :count)

      # WHEN
      Inventory.find_or_create_production_output("Mantequilla De Maní", "gramos")

      # THEN: count unchanged
      assert CRC.Repo.aggregate(CRC.Inventory.Product, :count) == initial_count
    end

    test "GIVEN product does not exist WHEN creating THEN it appears in inventory list" do
      # WHEN
      {:ok, product} =
        Inventory.find_or_create_production_output("Almíbar De Tamarindo", "litros")

      # THEN
      products = Inventory.list_products()
      ids = Enum.map(products, & &1.id)
      assert product.id in ids
    end
  end
end
