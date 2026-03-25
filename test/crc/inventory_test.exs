defmodule CRC.InventoryTest do
  use CRC.DataCase, async: true

  alias CRC.Inventory
  alias CRC.Inventory.{Product, Supplier}

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp supplier_attrs(overrides \\ %{}) do
    Map.merge(%{name: "Distribuidora López", contact_name: "Carlos López", phone: "55 1234 5678"}, overrides)
  end

  defp product_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        name: "Leche entera",
        category: "lacteos",
        unit: "litros",
        net_cost: "25.00",
        stock_quantity: "10.0",
        min_stock: "2.0"
      },
      overrides
    )
  end

  defp insert_supplier(overrides \\ %{}) do
    {:ok, supplier} = Inventory.create_supplier(supplier_attrs(overrides))
    supplier
  end

  defp insert_product(overrides \\ %{}) do
    {:ok, product} = Inventory.create_product(product_attrs(overrides))
    product
  end

  # ===========================================================================
  # SUPPLIERS
  # ===========================================================================

  describe "Supplier.changeset/2" do
    test "valid with required fields" do
      changeset = Supplier.changeset(%Supplier{}, supplier_attrs())
      assert changeset.valid?
    end

    test "invalid without name" do
      changeset = Supplier.changeset(%Supplier{}, supplier_attrs(%{name: nil}))
      refute changeset.valid?
      assert changeset.errors[:name]
    end

    test "valid with only name (all others optional)" do
      changeset = Supplier.changeset(%Supplier{}, %{name: "Solo nombre"})
      assert changeset.valid?
    end
  end

  describe "create_supplier/1" do
    test "creates a supplier with valid attrs" do
      assert {:ok, %Supplier{name: "Distribuidora López"}} =
               Inventory.create_supplier(supplier_attrs())
    end

    test "returns error changeset with invalid attrs" do
      assert {:error, %Ecto.Changeset{}} = Inventory.create_supplier(%{name: nil})
    end

    test "new supplier is active by default" do
      {:ok, supplier} = Inventory.create_supplier(supplier_attrs())
      assert supplier.active == true
    end
  end

  describe "list_suppliers/0" do
    test "returns all suppliers ordered by name" do
      insert_supplier(%{name: "Zeta Proveedores"})
      insert_supplier(%{name: "Alpha Distribuciones"})

      names = Inventory.list_suppliers() |> Enum.map(& &1.name)
      assert names == Enum.sort(names)
    end

    test "includes both active and inactive suppliers" do
      {:ok, s} = Inventory.create_supplier(supplier_attrs())
      Inventory.toggle_supplier_active(s)

      assert length(Inventory.list_suppliers()) == 1
    end
  end

  describe "list_active_suppliers/0" do
    test "returns only active suppliers" do
      {:ok, active} = Inventory.create_supplier(supplier_attrs(%{name: "Activo"}))
      {:ok, inactive} = Inventory.create_supplier(supplier_attrs(%{name: "Inactivo"}))
      Inventory.toggle_supplier_active(inactive)

      result = Inventory.list_active_suppliers()
      ids = Enum.map(result, & &1.id)

      assert active.id in ids
      refute inactive.id in ids
    end
  end

  describe "update_supplier/2" do
    test "updates supplier fields" do
      supplier = insert_supplier()
      assert {:ok, updated} = Inventory.update_supplier(supplier, %{name: "Nuevo Nombre"})
      assert updated.name == "Nuevo Nombre"
    end

    test "returns error changeset with invalid attrs" do
      supplier = insert_supplier()
      assert {:error, %Ecto.Changeset{}} = Inventory.update_supplier(supplier, %{name: nil})
    end
  end

  describe "toggle_supplier_active/1" do
    test "deactivates an active supplier" do
      supplier = insert_supplier()
      assert supplier.active == true

      {:ok, toggled} = Inventory.toggle_supplier_active(supplier)
      assert toggled.active == false
    end

    test "reactivates an inactive supplier" do
      supplier = insert_supplier()
      {:ok, inactive} = Inventory.toggle_supplier_active(supplier)
      assert inactive.active == false

      {:ok, reactivated} = Inventory.toggle_supplier_active(inactive)
      assert reactivated.active == true
    end
  end

  describe "get_supplier!/1" do
    test "returns supplier by id" do
      supplier = insert_supplier()
      assert Inventory.get_supplier!(supplier.id).id == supplier.id
    end

    test "raises if not found" do
      assert_raise Ecto.NoResultsError, fn -> Inventory.get_supplier!(0) end
    end
  end

  # ===========================================================================
  # PRODUCTS
  # ===========================================================================

  describe "Product.changeset/2" do
    test "valid with all required fields" do
      changeset = Product.changeset(%Product{}, product_attrs())
      assert changeset.valid?
    end

    test "invalid without name" do
      changeset = Product.changeset(%Product{}, product_attrs(%{name: nil}))
      refute changeset.valid?
      assert changeset.errors[:name]
    end

    test "invalid without category" do
      changeset = Product.changeset(%Product{}, product_attrs(%{category: nil}))
      refute changeset.valid?
      assert changeset.errors[:category]
    end

    test "invalid without unit" do
      changeset = Product.changeset(%Product{}, product_attrs(%{unit: nil}))
      refute changeset.valid?
      assert changeset.errors[:unit]
    end

    test "invalid without net_cost" do
      changeset = Product.changeset(%Product{}, product_attrs(%{net_cost: nil}))
      refute changeset.valid?
      assert changeset.errors[:net_cost]
    end

    test "invalid with unknown category" do
      changeset = Product.changeset(%Product{}, product_attrs(%{category: "no_existe"}))
      refute changeset.valid?
      assert changeset.errors[:category]
    end

    test "invalid with unknown unit" do
      changeset = Product.changeset(%Product{}, product_attrs(%{unit: "toneladas"}))
      refute changeset.valid?
      assert changeset.errors[:unit]
    end

    test "sale_price is optional" do
      changeset = Product.changeset(%Product{}, product_attrs(%{sale_price: nil}))
      assert changeset.valid?
    end
  end

  describe "create_product/1" do
    test "creates a product with valid attrs" do
      assert {:ok, %Product{name: "Leche entera"}} = Inventory.create_product(product_attrs())
    end

    test "new product is active by default" do
      {:ok, product} = Inventory.create_product(product_attrs())
      assert product.active == true
    end

    test "returns error changeset with invalid attrs" do
      assert {:error, %Ecto.Changeset{}} = Inventory.create_product(%{name: nil})
    end

    test "creates product linked to a supplier" do
      supplier = insert_supplier()
      attrs = product_attrs(%{supplier_id: supplier.id})
      {:ok, product} = Inventory.create_product(attrs)
      assert product.supplier_id == supplier.id
    end
  end

  describe "list_products/0" do
    test "returns all products with supplier preloaded" do
      supplier = insert_supplier()
      insert_product(%{name: "Café", supplier_id: supplier.id})

      [product | _] = Inventory.list_products()
      assert %Supplier{} = product.supplier
    end

    test "returns products ordered by category then name" do
      insert_product(%{name: "Leche", category: "lacteos"})
      insert_product(%{name: "Azúcar", category: "alimentos"})
      insert_product(%{name: "Café", category: "granos"})

      products = Inventory.list_products()
      pairs = Enum.map(products, &{&1.category, &1.name})
      assert pairs == Enum.sort(pairs)
    end

    test "includes both active and inactive products" do
      {:ok, p} = Inventory.create_product(product_attrs())
      Inventory.toggle_product_active(p)

      assert length(Inventory.list_products()) == 1
    end
  end

  describe "list_low_stock_products/0" do
    test "returns only active products at or below min_stock" do
      {:ok, low} = Inventory.create_product(product_attrs(%{
        name: "Bajo stock", stock_quantity: "1.0", min_stock: "2.0"
      }))
      {:ok, _ok} = Inventory.create_product(product_attrs(%{
        name: "Stock ok", stock_quantity: "10.0", min_stock: "2.0",
        category: "alimentos"
      }))

      result = Inventory.list_low_stock_products()
      ids = Enum.map(result, & &1.id)

      assert low.id in ids
    end

    test "does not include inactive products even if below min_stock" do
      {:ok, product} = Inventory.create_product(product_attrs(%{
        stock_quantity: "1.0", min_stock: "5.0"
      }))
      Inventory.toggle_product_active(product)

      assert Inventory.list_low_stock_products() == []
    end

    test "returns empty list when all stock is sufficient" do
      insert_product(%{stock_quantity: "100.0", min_stock: "2.0"})
      assert Inventory.list_low_stock_products() == []
    end
  end

  describe "update_product/2" do
    test "updates product fields" do
      product = insert_product()
      assert {:ok, updated} = Inventory.update_product(product, %{name: "Leche descremada"})
      assert updated.name == "Leche descremada"
    end

    test "returns error changeset with invalid attrs" do
      product = insert_product()
      assert {:error, %Ecto.Changeset{}} = Inventory.update_product(product, %{name: nil})
    end
  end

  describe "toggle_product_active/1" do
    test "deactivates an active product" do
      product = insert_product()
      {:ok, toggled} = Inventory.toggle_product_active(product)
      assert toggled.active == false
    end

    test "reactivates an inactive product" do
      product = insert_product()
      {:ok, inactive} = Inventory.toggle_product_active(product)
      {:ok, reactivated} = Inventory.toggle_product_active(inactive)
      assert reactivated.active == true
    end
  end

  describe "get_product!/1" do
    test "returns product with supplier preloaded" do
      supplier = insert_supplier()
      {:ok, product} = Inventory.create_product(product_attrs(%{supplier_id: supplier.id}))

      fetched = Inventory.get_product!(product.id)
      assert fetched.id == product.id
      assert %Supplier{} = fetched.supplier
    end

    test "raises if not found" do
      assert_raise Ecto.NoResultsError, fn -> Inventory.get_product!(0) end
    end
  end

  describe "change_supplier/2 and change_product/2" do
    test "change_supplier returns an empty changeset" do
      cs = Inventory.change_supplier(%Supplier{})
      assert %Ecto.Changeset{} = cs
    end

    test "change_product returns an empty changeset" do
      cs = Inventory.change_product(%Product{})
      assert %Ecto.Changeset{} = cs
    end
  end
end
