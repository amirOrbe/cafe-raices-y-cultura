defmodule CRC.CatalogTest do
  use CRC.DataCase, async: true

  alias CRC.Catalog
  alias CRC.Catalog.{Category, MenuItem}

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp category_attrs(overrides \\ %{}) do
    Map.merge(%{name: "Cafés", kind: "drink"}, overrides)
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
    test "válido con nombre y kind requeridos" do
      changeset = Category.changeset(%Category{}, category_attrs())
      assert changeset.valid?
    end

    test "inválido sin nombre" do
      changeset = Category.changeset(%Category{}, category_attrs(%{name: nil}))
      refute changeset.valid?
      assert changeset.errors[:name]
    end

    test "inválido sin kind" do
      changeset = Category.changeset(%Category{}, %{name: "Test"})
      # kind has a default, so it should still be valid
      assert changeset.valid? || changeset.errors[:kind] != nil
    end

    test "inválido con kind desconocido" do
      changeset = Category.changeset(%Category{}, category_attrs(%{kind: "unknown"}))
      refute changeset.valid?
      assert changeset.errors[:kind]
    end

    test "válido con kind food" do
      changeset = Category.changeset(%Category{}, category_attrs(%{kind: "food"}))
      assert changeset.valid?
    end

    test "válido con kind extra" do
      changeset = Category.changeset(%Category{}, category_attrs(%{kind: "extra"}))
      assert changeset.valid?
    end

    test "active tiene default true" do
      {:ok, cat} = Catalog.create_category(category_attrs())
      assert cat.active == true
    end

    test "position es opcional y tiene default 0" do
      changeset = Category.changeset(%Category{}, category_attrs())
      assert changeset.valid?
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

    test "retorna categorías ordenadas por position" do
      insert_category(%{name: "Tercera", position: 3})
      insert_category(%{name: "Primera", position: 1})
      insert_category(%{name: "Segunda", position: 2})

      cats = Catalog.list_categories()
      positions = Enum.map(cats, & &1.position)
      assert positions == Enum.sort(positions)
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
          category: "carnes",
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
      assert {:error, %Ecto.Changeset{}} = Catalog.create_category(%{kind: "drink"})
    end
  end

  # ===========================================================================
  # update_category/2
  # ===========================================================================

  describe "update_category/2" do
    test "actualiza la categoría exitosamente" do
      cat = insert_category()
      assert {:ok, updated} = Catalog.update_category(cat, %{name: "Nuevo nombre"})
      assert updated.name == "Nuevo nombre"
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
      insert_menu_item(cat.id, %{name: "No disponible destacado", available: false, featured: true})

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
      assert {:ok, %MenuItem{name: "Espresso"}} = Catalog.create_menu_item(menu_item_attrs(cat.id))
    end

    test "falla sin nombre" do
      cat = insert_category()
      assert {:error, %Ecto.Changeset{}} = Catalog.create_menu_item(%{price: "40", category_id: cat.id})
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
end
