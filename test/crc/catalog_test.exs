defmodule CRC.CatalogTest do
  use CRC.DataCase, async: true

  alias CRC.Catalog
  alias CRC.Catalog.{Category, MenuItem}

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp category_attrs(overrides \\ %{}) do
    Map.merge(%{name: "Cafés"}, Map.drop(overrides, [:kind, "kind"]))
  end

  defp insert_category(overrides \\ %{}) do
    {:ok, cat} = Catalog.create_category(category_attrs(overrides))
    cat
  end

  defp menu_item_attrs(category_id, overrides \\ %{}) do
    Map.merge(
      %{
        name: "Espresso",
        price: "40.00",
        category_id: category_id
      },
      overrides
    )
  end

  defp insert_menu_item(category_id, overrides \\ %{}) do
    {:ok, item} = Catalog.create_menu_item(menu_item_attrs(category_id, overrides))
    item
  end

  # ===========================================================================
  # Category.changeset/2
  # ===========================================================================

  describe "Category.changeset/2" do
    test "válido con nombre" do
      changeset = Category.changeset(%Category{}, category_attrs())
      assert changeset.valid?
    end

    test "inválido sin nombre" do
      changeset = Category.changeset(%Category{}, category_attrs(%{name: nil}))
      refute changeset.valid?
      assert changeset.errors[:name]
    end

    test "active tiene default true" do
      {:ok, cat} = Catalog.create_category(category_attrs())
      assert cat.active == true
    end
  end

  # ===========================================================================
  # list_categories/0
  # ===========================================================================

  describe "list_categories/0" do
    test "retorna solo las categorías activas" do
      insert_category(%{name: "Activa", active: true})
      insert_category(%{name: "Inactiva", active: false, slug: "inactiva"})

      cats = Catalog.list_categories()
      names = Enum.map(cats, & &1.name)

      assert "Activa" in names
      refute "Inactiva" in names
    end

    test "retorna categorías ordenadas por nombre" do
      insert_category(%{name: "Tercera"})
      insert_category(%{name: "Primera"})
      insert_category(%{name: "Segunda"})

      cats = Catalog.list_categories()
      names = Enum.map(cats, & &1.name)
      assert names == Enum.sort(names)
    end

    test "retorna categorías con menu_items precargados" do
      cat = insert_category()
      insert_menu_item(cat.id, %{available: true})

      [loaded_cat | _] = Catalog.list_categories()
      assert is_list(loaded_cat.menu_items)
    end

    test "solo precarga menu items disponibles" do
      cat = insert_category()
      insert_menu_item(cat.id, %{name: "Disponible", available: true})
      insert_menu_item(cat.id, %{name: "No disponible", available: false})

      [loaded_cat] = Catalog.list_categories()
      item_names = Enum.map(loaded_cat.menu_items, & &1.name)
      assert "Disponible" in item_names
      refute "No disponible" in item_names
    end

    test "precarga menu_item_ingredients con product en cada item" do
      cat = insert_category()
      mi = insert_menu_item(cat.id, %{name: "Platillo con ingrediente"})

      product =
        CRC.Repo.insert!(%CRC.Inventory.Product{
          name: "Arrachera Prueba #{System.unique_integer()}",
          unit: "g",
          net_cost: Decimal.new("5.00"),
          stock_quantity: Decimal.new("500"),
          active: true
        })

      CRC.Repo.insert!(%CRC.Catalog.MenuItemIngredient{
        menu_item_id: mi.id,
        product_id: product.id,
        quantity: Decimal.new("120")
      })

      [loaded_cat] = Catalog.list_categories()
      [loaded_item] = loaded_cat.menu_items
      assert is_list(loaded_item.menu_item_ingredients)
      assert length(loaded_item.menu_item_ingredients) == 1
      [mii] = loaded_item.menu_item_ingredients
      assert mii.product.name == product.name
      assert Decimal.equal?(mii.quantity, Decimal.new("120"))
    end

    test "menu_item_ingredients es lista vacía si el platillo no tiene ingredientes" do
      cat = insert_category()
      insert_menu_item(cat.id, %{name: "Sin ingredientes"})

      [loaded_cat] = Catalog.list_categories()
      [loaded_item] = loaded_cat.menu_items
      assert loaded_item.menu_item_ingredients == []
    end
  end

  # ===========================================================================
  # list_all_categories/0
  # ===========================================================================

  describe "list_all_categories/0" do
    test "retorna todas las categorías incluyendo inactivas" do
      insert_category(%{name: "Activa", active: true})
      insert_category(%{name: "Inactiva", active: false, slug: "inactiva-all"})

      cats = Catalog.list_all_categories()
      names = Enum.map(cats, & &1.name)

      assert "Activa" in names
      assert "Inactiva" in names
    end
  end

  # ===========================================================================
  # get_category!/1
  # ===========================================================================

  describe "get_category!/1" do
    test "retorna la categoría por id" do
      cat = insert_category()
      assert Catalog.get_category!(cat.id).id == cat.id
    end

    test "lanza excepción si no existe" do
      assert_raise Ecto.NoResultsError, fn -> Catalog.get_category!(0) end
    end
  end

  # ===========================================================================
  # create_category/1
  # ===========================================================================

  describe "create_category/1" do
    test "crea categoría con datos válidos" do
      assert {:ok, %Category{name: "Cafés"}} = Catalog.create_category(category_attrs())
    end

    test "falla sin nombre" do
      assert {:error, %Ecto.Changeset{}} = Catalog.create_category(%{active: true})
    end
  end

  # ===========================================================================
  # update_category/2
  # ===========================================================================

  describe "update_category/2" do
    test "actualiza la categoría exitosamente" do
      cat = insert_category()
      assert {:ok, updated} = Catalog.update_category(cat, %{name: "Nuevo nombre"})
      assert updated.name == "Nuevo Nombre"
    end

    test "falla con datos inválidos" do
      cat = insert_category()
      assert {:error, %Ecto.Changeset{}} = Catalog.update_category(cat, %{name: nil})
    end
  end

  # ===========================================================================
  # delete_category/1
  # ===========================================================================

  describe "delete_category/1" do
    test "elimina la categoría exitosamente" do
      cat = insert_category()
      assert {:ok, _deleted} = Catalog.delete_category(cat)
      assert_raise Ecto.NoResultsError, fn -> Catalog.get_category!(cat.id) end
    end
  end

  # ===========================================================================
  # MenuItem.changeset/2
  # ===========================================================================

  describe "MenuItem.changeset/2" do
    setup do
      cat = insert_category()
      {:ok, cat: cat}
    end

    test "válido con nombre, precio y category_id", %{cat: cat} do
      changeset = MenuItem.changeset(%MenuItem{}, menu_item_attrs(cat.id))
      assert changeset.valid?
    end

    test "inválido sin nombre", %{cat: cat} do
      changeset = MenuItem.changeset(%MenuItem{}, menu_item_attrs(cat.id, %{name: nil}))
      refute changeset.valid?
      assert changeset.errors[:name]
    end

    test "inválido sin precio", %{cat: cat} do
      changeset = MenuItem.changeset(%MenuItem{}, menu_item_attrs(cat.id, %{price: nil}))
      refute changeset.valid?
      assert changeset.errors[:price]
    end

    test "inválido sin category_id" do
      changeset = MenuItem.changeset(%MenuItem{}, %{name: "Item", price: "40.00"})
      refute changeset.valid?
      assert changeset.errors[:category_id]
    end

    test "inválido con precio <= 0", %{cat: cat} do
      changeset = MenuItem.changeset(%MenuItem{}, menu_item_attrs(cat.id, %{price: "0"}))
      refute changeset.valid?
      assert changeset.errors[:price]
    end

    test "available tiene default true", %{cat: cat} do
      {:ok, item} = Catalog.create_menu_item(menu_item_attrs(cat.id))
      assert item.available == true
    end

    test "featured tiene default false", %{cat: cat} do
      {:ok, item} = Catalog.create_menu_item(menu_item_attrs(cat.id))
      assert item.featured == false
    end

    test "description e image_url son opcionales", %{cat: cat} do
      changeset = MenuItem.changeset(%MenuItem{}, menu_item_attrs(cat.id))
      assert changeset.valid?
    end
  end

  # ===========================================================================
  # list_menu_items/0
  # ===========================================================================

  describe "list_menu_items/0" do
    test "retorna solo los items disponibles" do
      cat = insert_category()
      insert_menu_item(cat.id, %{name: "Disponible", available: true})
      insert_menu_item(cat.id, %{name: "No disponible", available: false})

      items = Catalog.list_menu_items()
      names = Enum.map(items, & &1.name)

      assert "Disponible" in names
      refute "No disponible" in names
    end

    test "retorna items con categoría precargada" do
      cat = insert_category()
      insert_menu_item(cat.id)

      items = Catalog.list_menu_items()
      assert [item | _] = items
      assert %Category{} = item.category
    end
  end

  # ===========================================================================
  # list_featured_items/0
  # ===========================================================================

  describe "list_featured_items/0" do
    test "retorna solo items disponibles y destacados" do
      cat = insert_category()
      insert_menu_item(cat.id, %{name: "Destacado", available: true, featured: true})
      insert_menu_item(cat.id, %{name: "No destacado", available: true, featured: false})

      insert_menu_item(cat.id, %{
        name: "No disponible destacado",
        available: false,
        featured: true
      })

      items = Catalog.list_featured_items()
      names = Enum.map(items, & &1.name)

      assert "Destacado" in names
      refute "No destacado" in names
      refute "No disponible destacado" in names
    end

    test "retorna items con categoría precargada" do
      cat = insert_category()
      insert_menu_item(cat.id, %{featured: true})

      items = Catalog.list_featured_items()
      assert [item | _] = items
      assert %Category{} = item.category
    end
  end

  # ===========================================================================
  # get_menu_item!/1
  # ===========================================================================

  describe "get_menu_item!/1" do
    test "retorna el item con categoría precargada" do
      cat = insert_category()
      item = insert_menu_item(cat.id)

      fetched = Catalog.get_menu_item!(item.id)
      assert fetched.id == item.id
      assert %Category{} = fetched.category
    end

    test "lanza excepción si no existe" do
      assert_raise Ecto.NoResultsError, fn -> Catalog.get_menu_item!(0) end
    end
  end

  # ===========================================================================
  # create_menu_item/1
  # ===========================================================================

  describe "create_menu_item/1" do
    test "crea item con datos válidos" do
      cat = insert_category()

      assert {:ok, %MenuItem{name: "Espresso"}} =
               Catalog.create_menu_item(menu_item_attrs(cat.id))
    end

    test "falla sin nombre" do
      cat = insert_category()

      assert {:error, %Ecto.Changeset{}} =
               Catalog.create_menu_item(%{price: "40", category_id: cat.id})
    end
  end

  # ===========================================================================
  # update_menu_item/2
  # ===========================================================================

  describe "update_menu_item/2" do
    test "actualiza el item exitosamente" do
      cat = insert_category()
      item = insert_menu_item(cat.id)
      assert {:ok, updated} = Catalog.update_menu_item(item, %{name: "Americano"})
      assert updated.name == "Americano"
    end

    test "falla con datos inválidos" do
      cat = insert_category()
      item = insert_menu_item(cat.id)
      assert {:error, %Ecto.Changeset{}} = Catalog.update_menu_item(item, %{name: nil})
    end
  end

  # ===========================================================================
  # delete_menu_item/1
  # ===========================================================================

  describe "delete_menu_item/1" do
    test "elimina el item exitosamente" do
      cat = insert_category()
      item = insert_menu_item(cat.id)
      assert {:ok, _deleted} = Catalog.delete_menu_item(item)
      assert_raise Ecto.NoResultsError, fn -> Catalog.get_menu_item!(item.id) end
    end
  end

  describe "create_category/0 default arg" do
    test "returns error with empty attrs (required name missing)" do
      assert {:error, %Ecto.Changeset{}} = Catalog.create_category()
    end
  end

  describe "create_menu_item/0 default arg" do
    test "returns error with empty attrs (required fields missing)" do
      assert {:error, %Ecto.Changeset{}} = Catalog.create_menu_item()
    end
  end

  # ===========================================================================
  # available_portions/1 — stock-aware availability
  # ===========================================================================

  defp insert_product(name, stock) do
    CRC.Repo.insert!(%CRC.Inventory.Product{
      name: "#{name}_#{System.unique_integer()}",
      unit: "g",
      net_cost: Decimal.new("1.00"),
      stock_quantity: Decimal.new(stock),
      active: true
    })
  end

  defp link_ingredient(menu_item_id, product_id, qty) do
    CRC.Repo.insert!(%CRC.Catalog.MenuItemIngredient{
      menu_item_id: menu_item_id,
      product_id: product_id,
      quantity: Decimal.new(qty)
    })
  end

  defp item_with_ingredients(category_id, ingredients) do
    item = insert_menu_item(category_id)
    for {product_id, qty} <- ingredients, do: link_ingredient(item.id, product_id, qty)
    Catalog.get_menu_item_with_ingredients!(item.id)
  end

  describe "available_portions/1" do
    test "returns nil for items with no recipe (always available)" do
      cat = insert_category()
      item = insert_menu_item(cat.id)
      loaded = Catalog.get_menu_item_with_ingredients!(item.id)
      assert is_nil(Catalog.available_portions(loaded))
    end

    test "returns integer portions when recipe is present" do
      cat = insert_category()
      prod = insert_product("jitomate", "100")
      # recipe: 25g per portion → 100 / 25 = 4 portions
      item = item_with_ingredients(cat.id, [{prod.id, "25"}])
      assert Catalog.available_portions(item) == 4
    end

    test "returns 0 when any ingredient is fully depleted" do
      cat = insert_category()
      pan = insert_product("pan", "200")
      # depleted
      queso = insert_product("queso", "0")
      item = item_with_ingredients(cat.id, [{pan.id, "50"}, {queso.id, "30"}])
      assert Catalog.available_portions(item) == 0
    end

    test "returns the minimum across all ingredients (bottleneck ingredient)" do
      cat = insert_category()
      # tortilla: 500g stock / 100g each = 5 portions
      # lechuga:  200g stock / 50g each  = 4 portions  ← bottleneck
      # pollo:    1000g stock / 120g each = 8 portions
      tortilla = insert_product("tortilla", "500")
      lechuga = insert_product("lechuga", "200")
      pollo = insert_product("pollo", "1000")

      item =
        item_with_ingredients(cat.id, [
          {tortilla.id, "100"},
          {lechuga.id, "50"},
          {pollo.id, "120"}
        ])

      assert Catalog.available_portions(item) == 4
    end

    test "floors fractional portions (never rounds up)" do
      cat = insert_category()
      # 100g stock, 30g per portion → 3.33 → floors to 3
      prod = insert_product("arroz", "100")
      item = item_with_ingredients(cat.id, [{prod.id, "30"}])
      assert Catalog.available_portions(item) == 3
    end

    test "returns 0 for inactive product ingredient" do
      cat = insert_category()

      prod =
        CRC.Repo.insert!(%CRC.Inventory.Product{
          name: "Prod inactivo #{System.unique_integer()}",
          unit: "g",
          net_cost: Decimal.new("1.00"),
          stock_quantity: Decimal.new("999"),
          active: false
        })

      item = item_with_ingredients(cat.id, [{prod.id, "10"}])
      assert Catalog.available_portions(item) == 0
    end
  end

  describe "item_in_stock?/1 — backward-compatible wrapper" do
    test "returns true when portions is nil (no recipe)" do
      cat = insert_category()
      item = insert_menu_item(cat.id)
      loaded = Catalog.get_menu_item_with_ingredients!(item.id)
      assert Catalog.item_in_stock?(loaded) == true
    end

    test "returns true when portions > 0" do
      cat = insert_category()
      prod = insert_product("ingr_stock", "100")
      item = item_with_ingredients(cat.id, [{prod.id, "10"}])
      assert Catalog.item_in_stock?(item) == true
    end

    test "returns false when portions == 0 (depleted)" do
      cat = insert_category()
      prod = insert_product("ingr_empty", "0")
      item = item_with_ingredients(cat.id, [{prod.id, "10"}])
      assert Catalog.item_in_stock?(item) == false
    end
  end

  describe "list_menu_items_for_category_with_stock/1" do
    test "returns {MenuItem, nil} for item with no recipe" do
      cat = insert_category()
      insert_menu_item(cat.id)
      results = Catalog.list_menu_items_for_category_with_stock(cat.id)
      assert length(results) == 1
      [{_item, portions}] = results
      assert is_nil(portions)
    end

    test "returns {MenuItem, n} with correct portions count" do
      cat = insert_category()
      prod = insert_product("stock_cat_test", "200")
      item = insert_menu_item(cat.id)
      # 200/50 = 4 portions
      link_ingredient(item.id, prod.id, "50")
      results = Catalog.list_menu_items_for_category_with_stock(cat.id)
      assert length(results) == 1
      [{_item, portions}] = results
      assert portions == 4
    end

    test "returns {MenuItem, 0} when ingredient is depleted" do
      cat = insert_category()
      prod = insert_product("empty_cat", "0")
      item = insert_menu_item(cat.id)
      link_ingredient(item.id, prod.id, "10")
      results = Catalog.list_menu_items_for_category_with_stock(cat.id)
      [{_item, portions}] = results
      assert portions == 0
    end

    test "excludes unavailable menu items" do
      cat = insert_category()
      insert_menu_item(cat.id, %{available: false})
      results = Catalog.list_menu_items_for_category_with_stock(cat.id)
      assert results == []
    end
  end

  # ===========================================================================
  # toggle_menu_item_available/1
  # ===========================================================================

  describe "toggle_menu_item_available/1" do
    test "hides an available item" do
      cat = insert_category()
      item = insert_menu_item(cat.id, %{available: true})
      assert {:ok, updated} = Catalog.toggle_menu_item_available(item)
      refute updated.available
    end

    test "publishes a hidden item" do
      cat = insert_category()
      item = insert_menu_item(cat.id, %{available: false})
      assert {:ok, updated} = Catalog.toggle_menu_item_available(item)
      assert updated.available
    end
  end

  # ===========================================================================
  # set_menu_item_ingredients/2
  # ===========================================================================

  describe "set_menu_item_ingredients/2" do
    test "inserts ingredients for a menu item" do
      cat = insert_category()
      item = insert_menu_item(cat.id)
      prod = insert_product("setingr", "100")

      assert {:ok, _} =
               Catalog.set_menu_item_ingredients(item.id, [
                 %{product_id: prod.id, quantity: Decimal.new("25")}
               ])

      loaded = Catalog.get_menu_item_with_ingredients!(item.id)
      assert length(loaded.menu_item_ingredients) == 1
      assert hd(loaded.menu_item_ingredients).product_id == prod.id
    end

    test "replaces existing ingredients on second call" do
      cat = insert_category()
      item = insert_menu_item(cat.id)
      prod1 = insert_product("repl1", "100")
      prod2 = insert_product("repl2", "200")

      Catalog.set_menu_item_ingredients(item.id, [
        %{product_id: prod1.id, quantity: Decimal.new("10")}
      ])

      Catalog.set_menu_item_ingredients(item.id, [
        %{product_id: prod2.id, quantity: Decimal.new("20")}
      ])

      loaded = Catalog.get_menu_item_with_ingredients!(item.id)
      assert length(loaded.menu_item_ingredients) == 1
      assert hd(loaded.menu_item_ingredients).product_id == prod2.id
    end

    test "clears all ingredients when given empty list" do
      cat = insert_category()
      item = insert_menu_item(cat.id)
      prod = insert_product("clr", "50")

      Catalog.set_menu_item_ingredients(item.id, [
        %{product_id: prod.id, quantity: Decimal.new("5")}
      ])

      Catalog.set_menu_item_ingredients(item.id, [])

      loaded = Catalog.get_menu_item_with_ingredients!(item.id)
      assert loaded.menu_item_ingredients == []
    end
  end

  # ===========================================================================
  # list_extras_for_category/1
  # ===========================================================================

  describe "list_extras_for_category/1" do
    test "returns distinct products used by available items in the category" do
      cat = insert_category()
      prod = insert_product("extras_cat", "100")
      item = insert_menu_item(cat.id)
      link_ingredient(item.id, prod.id, "10")

      results = Catalog.list_extras_for_category(cat.id)
      assert Enum.any?(results, &(&1.id == prod.id))
    end

    test "returns empty list when category has no items with ingredients" do
      cat = insert_category()
      _item = insert_menu_item(cat.id)
      assert Catalog.list_extras_for_category(cat.id) == []
    end

    test "does not return products from other categories" do
      cat1 = insert_category(%{name: "Cat Extras A #{System.unique_integer()}"})
      cat2 = insert_category(%{name: "Cat Extras B #{System.unique_integer()}"})
      prod = insert_product("other_cat", "100")
      item2 = insert_menu_item(cat2.id)
      link_ingredient(item2.id, prod.id, "10")

      results = Catalog.list_extras_for_category(cat1.id)
      refute Enum.any?(results, &(&1.id == prod.id))
    end

    test "does not return products from unavailable items" do
      cat = insert_category()
      prod = insert_product("unavail_extra", "100")
      item = insert_menu_item(cat.id, %{available: false})
      link_ingredient(item.id, prod.id, "10")

      assert Catalog.list_extras_for_category(cat.id) == []
    end
  end

  # ===========================================================================
  # list_extras_for_menu_item/2
  # ===========================================================================

  describe "list_extras_for_menu_item/2" do
    test "returns {product, qty} using exact recipe quantity for the item" do
      cat = insert_category()
      prod = insert_product("exact_qty", "200")
      item = insert_menu_item(cat.id)
      link_ingredient(item.id, prod.id, "75")

      results = Catalog.list_extras_for_menu_item(item.id, cat.id)
      assert length(results) == 1
      [{returned_prod, qty}] = results
      assert returned_prod.id == prod.id
      assert Decimal.equal?(qty, Decimal.new("75"))
    end

    test "returns category-avg quantity for products not in the item's recipe" do
      cat = insert_category()
      prod = insert_product("avg_qty", "200")
      item1 = insert_menu_item(cat.id)
      item2 = insert_menu_item(cat.id)
      # Only item2 has this ingredient; item1 gets category avg
      link_ingredient(item2.id, prod.id, "40")

      results = Catalog.list_extras_for_menu_item(item1.id, cat.id)
      assert length(results) == 1
      [{_p, qty}] = results
      assert Decimal.compare(qty, Decimal.new("0")) == :gt
    end

    test "returns empty list when category has no ingredients" do
      cat = insert_category()
      item = insert_menu_item(cat.id)
      assert Catalog.list_extras_for_menu_item(item.id, cat.id) == []
    end
  end

  # ===========================================================================
  # MenuItem.destinations/0
  # ===========================================================================

  describe "MenuItem.destinations/0" do
    alias CRC.Catalog.MenuItem

    test "returns the list of valid destinations" do
      assert MenuItem.destinations() == ["cocina", "barra"]
    end
  end

  # ===========================================================================
  # list_all_menu_items/0
  # ===========================================================================

  describe "list_all_menu_items/0" do
    test "includes unavailable items" do
      cat = insert_category()
      insert_menu_item(cat.id, %{name: "Oculto", available: false})
      items = Catalog.list_all_menu_items()
      assert Enum.any?(items, &(&1.name == "Oculto"))
    end
  end

  # ===========================================================================
  # Package CRUD
  # ===========================================================================

  defp insert_package(overrides \\ %{}) do
    base = %{name: "Combo #{System.unique_integer()}", price: "90.00"}
    {:ok, pkg} = Catalog.create_package(Map.merge(base, overrides))
    pkg
  end

  describe "Package.changeset/2" do
    alias CRC.Catalog.Package

    test "valid with name and price" do
      changeset = Package.changeset(%Package{}, %{name: "Combo Café", price: "80.00"})
      assert changeset.valid?
    end

    test "invalid without name" do
      changeset = Package.changeset(%Package{}, %{price: "80.00"})
      refute changeset.valid?
      assert changeset.errors[:name]
    end

    test "invalid without price" do
      changeset = Package.changeset(%Package{}, %{name: "Combo"})
      refute changeset.valid?
      assert changeset.errors[:price]
    end

    test "invalid with price <= 0" do
      changeset = Package.changeset(%Package{}, %{name: "Combo", price: "0"})
      refute changeset.valid?
      assert changeset.errors[:price]
    end

    test "active defaults to true" do
      pkg = insert_package()
      assert pkg.active == true
    end

    test "featured defaults to false" do
      pkg = insert_package()
      assert pkg.featured == false
    end
  end

  describe "list_packages/0" do
    test "returns only active packages" do
      insert_package(%{active: true})
      insert_package(%{active: false})
      pkgs = Catalog.list_packages()
      assert Enum.all?(pkgs, & &1.active)
    end
  end

  describe "list_all_packages/0" do
    test "returns all packages including inactive" do
      insert_package(%{active: true})
      insert_package(%{active: false})
      pkgs = Catalog.list_all_packages()
      assert Enum.any?(pkgs, &(not &1.active))
    end
  end

  describe "get_package!/1" do
    test "returns package by id with items preloaded" do
      pkg = insert_package()
      found = Catalog.get_package!(pkg.id)
      assert found.id == pkg.id
      assert found.package_items == []
    end

    test "raises for unknown id" do
      assert_raise Ecto.NoResultsError, fn -> Catalog.get_package!(0) end
    end
  end

  describe "create_package/1" do
    test "creates package successfully" do
      assert {:ok, pkg} = Catalog.create_package(%{name: "Combo Nuevo", price: "75.00"})
      assert pkg.name == "Combo Nuevo"
    end

    test "returns error changeset for invalid attrs" do
      assert {:error, changeset} = Catalog.create_package(%{})
      refute changeset.valid?
    end
  end

  describe "update_package/2" do
    test "updates package fields" do
      pkg = insert_package(%{name: "Original"})
      {:ok, updated} = Catalog.update_package(pkg, %{name: "Actualizado"})
      assert updated.name == "Actualizado"
    end
  end

  describe "delete_package/1" do
    test "deletes a package" do
      pkg = insert_package()
      assert {:ok, _} = Catalog.delete_package(pkg)
      assert_raise Ecto.NoResultsError, fn -> Catalog.get_package!(pkg.id) end
    end
  end

  describe "change_package/2" do
    test "returns a changeset" do
      alias CRC.Catalog.Package
      changeset = Catalog.change_package(%Package{})
      assert %Ecto.Changeset{} = changeset
    end
  end

  describe "set_package_items/2" do
    test "sets items for a package" do
      cat = insert_category()
      item = insert_menu_item(cat.id)
      pkg = insert_package()

      {:ok, updated} = Catalog.set_package_items(pkg, [%{menu_item_id: item.id, quantity: 2}])
      assert length(updated.package_items) == 1
      assert hd(updated.package_items).menu_item_id == item.id
      assert hd(updated.package_items).quantity == 2
    end

    test "replaces existing items" do
      cat = insert_category()
      item1 = insert_menu_item(cat.id)
      item2 = insert_menu_item(cat.id)
      pkg = insert_package()

      {:ok, _} = Catalog.set_package_items(pkg, [%{menu_item_id: item1.id, quantity: 1}])
      {:ok, updated} = Catalog.set_package_items(pkg, [%{menu_item_id: item2.id, quantity: 1}])

      assert length(updated.package_items) == 1
      assert hd(updated.package_items).menu_item_id == item2.id
    end
  end

  describe "suggest_packages/1" do
    test "returns empty list when not enough items with cost data" do
      assert Catalog.suggest_packages() == []
    end
  end

  describe "menu_items_with_margin/0" do
    test "returns empty list when no items have ingredient cost data" do
      # Items without ingredients have nil cost and are filtered out
      cat = insert_category()
      insert_menu_item(cat.id)
      result = Catalog.menu_items_with_margin()
      assert result == []
    end
  end
end
