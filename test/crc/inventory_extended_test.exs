defmodule CRC.InventoryExtendedTest do
  use CRC.DataCase, async: true

  alias CRC.Inventory
  alias CRC.Inventory.{Product, ProductVariant, StockAdjustment}

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp insert_user(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          name: "Inventory User",
          email: "inv#{System.unique_integer()}@cafe.com",
          role: "empleado",
          stations: ["sala"],
          password: "contraseña123"
        },
        overrides
      )

    {:ok, user} =
      %CRC.Accounts.User{}
      |> CRC.Accounts.User.changeset(attrs)
      |> CRC.Repo.insert()

    user
  end

  defp insert_product(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          name: "Insumo Test #{System.unique_integer()}",
          unit: "litros",
          net_cost: "10.00",
          stock_quantity: "100.0",
          min_stock: "10.0"
        },
        overrides
      )

    {:ok, product} = Inventory.create_product(attrs)
    product
  end

  # ===========================================================================
  # ProductVariant.changeset/2
  # ===========================================================================

  describe "ProductVariant.changeset/2" do
    test "GIVEN valid attrs WHEN building changeset THEN it is valid" do
      product = insert_product()

      cs =
        ProductVariant.changeset(%ProductVariant{}, %{
          product_id: product.id,
          name: "Entera",
          extra_charge: "0.00",
          stock_quantity: "50.0",
          min_stock: "5.0"
        })

      assert cs.valid?
    end

    test "GIVEN missing name WHEN building changeset THEN invalid" do
      product = insert_product()

      cs =
        ProductVariant.changeset(%ProductVariant{}, %{
          product_id: product.id
        })

      refute cs.valid?
      assert cs.errors[:name]
    end

    test "GIVEN missing product_id WHEN building changeset THEN invalid" do
      cs =
        ProductVariant.changeset(%ProductVariant{}, %{
          name: "Deslactosada"
        })

      refute cs.valid?
      assert cs.errors[:product_id]
    end

    test "GIVEN negative extra_charge WHEN building changeset THEN invalid" do
      product = insert_product()

      cs =
        ProductVariant.changeset(%ProductVariant{}, %{
          product_id: product.id,
          name: "Avena",
          extra_charge: "-1.00"
        })

      refute cs.valid?
      assert cs.errors[:extra_charge]
    end

    test "GIVEN negative stock_quantity WHEN building changeset THEN invalid" do
      product = insert_product()

      cs =
        ProductVariant.changeset(%ProductVariant{}, %{
          product_id: product.id,
          name: "Avena",
          stock_quantity: "-5.0"
        })

      refute cs.valid?
      assert cs.errors[:stock_quantity]
    end

    test "GIVEN name WHEN building changeset THEN name is title-cased" do
      product = insert_product()

      cs =
        ProductVariant.changeset(%ProductVariant{}, %{
          product_id: product.id,
          name: "entera full fat"
        })

      assert Ecto.Changeset.get_change(cs, :name) =~ "Entera"
    end
  end

  # ===========================================================================
  # StockAdjustment.changeset/2
  # ===========================================================================

  describe "StockAdjustment.changeset/2" do
    test "GIVEN valid attrs with negative quantity WHEN building changeset THEN valid" do
      product = insert_product()

      cs =
        StockAdjustment.changeset(%StockAdjustment{}, %{
          product_id: product.id,
          quantity: "-5.0",
          reason: "caducidad"
        })

      assert cs.valid?
    end

    test "GIVEN valid attrs with positive quantity WHEN building changeset THEN valid" do
      product = insert_product()

      cs =
        StockAdjustment.changeset(%StockAdjustment{}, %{
          product_id: product.id,
          quantity: "10.0",
          reason: "ajuste_manual"
        })

      assert cs.valid?
    end

    test "GIVEN quantity of zero WHEN building changeset THEN invalid" do
      product = insert_product()

      cs =
        StockAdjustment.changeset(%StockAdjustment{}, %{
          product_id: product.id,
          quantity: "0",
          reason: "derrame"
        })

      refute cs.valid?
      assert cs.errors[:quantity]
    end

    test "GIVEN invalid reason WHEN building changeset THEN invalid" do
      product = insert_product()

      cs =
        StockAdjustment.changeset(%StockAdjustment{}, %{
          product_id: product.id,
          quantity: "-1.0",
          reason: "accident"
        })

      refute cs.valid?
      assert cs.errors[:reason]
    end

    test "GIVEN missing reason WHEN building changeset THEN invalid" do
      product = insert_product()

      cs =
        StockAdjustment.changeset(%StockAdjustment{}, %{
          product_id: product.id,
          quantity: "-1.0"
        })

      refute cs.valid?
      assert cs.errors[:reason]
    end

    test "GIVEN all valid reasons WHEN building changesets THEN all are valid" do
      product = insert_product()

      for reason <- ~w(caducidad derrame robo ajuste_manual otro) do
        cs =
          StockAdjustment.changeset(%StockAdjustment{}, %{
            product_id: product.id,
            quantity: "-1.0",
            reason: reason
          })

        assert cs.valid?, "Expected valid for reason: #{reason}"
      end
    end
  end

  # ===========================================================================
  # Inventory.create_variant/2
  # ===========================================================================

  describe "create_variant/2" do
    test "GIVEN valid attrs WHEN creating variant THEN it is persisted" do
      product = insert_product(%{name: "Leche Base"})

      assert {:ok, %ProductVariant{} = variant} =
               Inventory.create_variant(product.id, %{"name" => "Entera"})

      assert variant.id
      assert variant.product_id == product.id
    end

    test "GIVEN invalid attrs WHEN creating variant THEN returns error changeset" do
      product = insert_product()

      assert {:error, %Ecto.Changeset{}} =
               Inventory.create_variant(product.id, %{"name" => ""})
    end

    test "GIVEN duplicate name for same product WHEN creating variant THEN returns error" do
      product = insert_product(%{name: "Leche Dup"})
      Inventory.create_variant(product.id, %{"name" => "Entera"})

      assert {:error, %Ecto.Changeset{}} =
               Inventory.create_variant(product.id, %{"name" => "Entera"})
    end
  end

  # ===========================================================================
  # Inventory.update_variant/2
  # ===========================================================================

  describe "update_variant/2" do
    test "GIVEN existing variant WHEN updating name THEN name is updated" do
      product = insert_product()
      {:ok, variant} = Inventory.create_variant(product.id, %{"name" => "Original"})

      assert {:ok, updated} = Inventory.update_variant(variant, %{"name" => "Actualizada"})
      assert updated.name == "Actualizada"
    end

    test "GIVEN invalid attrs WHEN updating variant THEN returns error changeset" do
      product = insert_product()
      {:ok, variant} = Inventory.create_variant(product.id, %{"name" => "Valida"})

      assert {:error, %Ecto.Changeset{}} = Inventory.update_variant(variant, %{"name" => ""})
    end
  end

  # ===========================================================================
  # Inventory.delete_variant/1
  # ===========================================================================

  describe "delete_variant/1" do
    test "GIVEN existing variant WHEN deleting THEN it is removed" do
      product = insert_product()
      {:ok, variant} = Inventory.create_variant(product.id, %{"name" => "Eliminar"})

      assert {:ok, _} = Inventory.delete_variant(variant)

      variants = Inventory.list_variants_for_product(product.id)
      ids = Enum.map(variants, & &1.id)
      refute variant.id in ids
    end
  end

  # ===========================================================================
  # Inventory.toggle_variant_active/1
  # ===========================================================================

  describe "toggle_variant_active/1" do
    test "GIVEN active variant WHEN toggling THEN becomes inactive" do
      product = insert_product()
      {:ok, variant} = Inventory.create_variant(product.id, %{"name" => "Activa"})
      assert variant.active == true

      {:ok, toggled} = Inventory.toggle_variant_active(variant)
      assert toggled.active == false
    end

    test "GIVEN inactive variant WHEN toggling THEN becomes active" do
      product = insert_product()
      {:ok, variant} = Inventory.create_variant(product.id, %{"name" => "Inactiva"})
      {:ok, inactive} = Inventory.toggle_variant_active(variant)

      {:ok, reactivated} = Inventory.toggle_variant_active(inactive)
      assert reactivated.active == true
    end
  end

  # ===========================================================================
  # Inventory.list_variants_for_product/1
  # ===========================================================================

  describe "list_variants_for_product/1" do
    test "GIVEN product with variants WHEN listing THEN all are returned ordered by name" do
      product = insert_product(%{name: "Leche Multi"})
      Inventory.create_variant(product.id, %{"name" => "Entera"})
      Inventory.create_variant(product.id, %{"name" => "Avena"})
      Inventory.create_variant(product.id, %{"name" => "Deslactosada"})

      variants = Inventory.list_variants_for_product(product.id)
      assert length(variants) == 3
      names = Enum.map(variants, & &1.name)
      assert names == Enum.sort(names)
    end

    test "GIVEN product with no variants WHEN listing THEN returns empty list" do
      product = insert_product()
      assert Inventory.list_variants_for_product(product.id) == []
    end
  end

  # ===========================================================================
  # Inventory.create_stock_adjustment/2
  # ===========================================================================

  describe "create_stock_adjustment/2" do
    test "GIVEN loss adjustment WHEN creating THEN product stock decreases" do
      product = insert_product(%{stock_quantity: "100.0"})
      user = insert_user()

      assert {:ok, adj} =
               Inventory.create_stock_adjustment(
                 %{product_id: product.id, quantity: Decimal.new("-10"), reason: "caducidad"},
                 user.id
               )

      assert adj.reason == "caducidad"
      refreshed = Inventory.get_product!(product.id)
      assert Decimal.compare(refreshed.stock_quantity, Decimal.new("90.0")) == :eq
    end

    test "GIVEN positive correction WHEN creating THEN product stock increases" do
      product = insert_product(%{stock_quantity: "50.0"})

      Inventory.create_stock_adjustment(
        %{product_id: product.id, quantity: Decimal.new("20"), reason: "ajuste_manual"},
        nil
      )

      refreshed = Inventory.get_product!(product.id)
      assert Decimal.compare(refreshed.stock_quantity, Decimal.new("70.0")) == :eq
    end

    test "GIVEN invalid attrs WHEN creating adjustment THEN returns error changeset" do
      product = insert_product()

      assert {:error, _cs} =
               Inventory.create_stock_adjustment(
                 %{product_id: product.id, quantity: Decimal.new("0"), reason: "caducidad"},
                 nil
               )
    end

    test "GIVEN invalid reason WHEN creating adjustment THEN returns error" do
      product = insert_product()

      assert {:error, _cs} =
               Inventory.create_stock_adjustment(
                 %{product_id: product.id, quantity: Decimal.new("-5"), reason: "invalid"},
                 nil
               )
    end

    test "GIVEN adjustment without user WHEN creating THEN adjusted_by_id is nil" do
      product = insert_product()

      {:ok, adj} =
        Inventory.create_stock_adjustment(
          %{product_id: product.id, quantity: Decimal.new("-1"), reason: "derrame"},
          nil
        )

      assert adj.adjusted_by_id == nil
    end
  end

  # ===========================================================================
  # Inventory.list_adjustments_for_product/2
  # ===========================================================================

  describe "list_adjustments_for_product/2" do
    test "GIVEN adjustments for product WHEN listing THEN they are returned newest first" do
      product = insert_product(%{stock_quantity: "500.0"})

      Inventory.create_stock_adjustment(
        %{product_id: product.id, quantity: Decimal.new("-5"), reason: "caducidad"},
        nil
      )

      Inventory.create_stock_adjustment(
        %{product_id: product.id, quantity: Decimal.new("-3"), reason: "derrame"},
        nil
      )

      adjs = Inventory.list_adjustments_for_product(product.id)
      assert length(adjs) == 2
      # Newest first (by inserted_at desc)
      [first, second] = adjs
      assert DateTime.compare(first.inserted_at, second.inserted_at) in [:gt, :eq]
    end

    test "GIVEN product with no adjustments WHEN listing THEN returns empty list" do
      product = insert_product()
      assert Inventory.list_adjustments_for_product(product.id) == []
    end
  end

  # ===========================================================================
  # Inventory.list_recent_adjustments/1
  # ===========================================================================

  describe "list_recent_adjustments/1" do
    test "GIVEN multiple adjustments WHEN listing with limit THEN respects limit" do
      product = insert_product(%{stock_quantity: "1000.0"})

      for _ <- 1..5 do
        Inventory.create_stock_adjustment(
          %{product_id: product.id, quantity: Decimal.new("-1"), reason: "otro"},
          nil
        )
      end

      adjs = Inventory.list_recent_adjustments(3)
      assert length(adjs) == 3
    end
  end

  # ===========================================================================
  # Inventory.change_stock_adjustment/1
  # ===========================================================================

  describe "change_stock_adjustment/1" do
    test "WHEN calling with no attrs THEN returns empty changeset" do
      assert %Ecto.Changeset{} = Inventory.change_stock_adjustment()
    end

    test "WHEN calling with attrs THEN returns changeset with data" do
      product = insert_product()

      cs =
        Inventory.change_stock_adjustment(%{
          product_id: product.id,
          quantity: "-3",
          reason: "caducidad"
        })

      assert %Ecto.Changeset{} = cs
    end
  end

  # ===========================================================================
  # Inventory.adjustment_reason_label/1
  # ===========================================================================

  describe "adjustment_reason_label/1" do
    test "GIVEN known reasons WHEN calling label THEN returns correct labels" do
      assert Inventory.adjustment_reason_label("caducidad") == "Caducidad"
      assert Inventory.adjustment_reason_label("derrame") == "Derrame / rotura"
      assert Inventory.adjustment_reason_label("robo") == "Robo / extravío"
      assert Inventory.adjustment_reason_label("ajuste_manual") == "Ajuste de inventario"
      assert Inventory.adjustment_reason_label("otro") == "Otro"
    end

    test "GIVEN unknown reason WHEN calling label THEN returns the reason itself" do
      assert Inventory.adjustment_reason_label("something") == "something"
    end
  end

  # ===========================================================================
  # Inventory.adjustment_reasons/0
  # ===========================================================================

  describe "adjustment_reasons/0" do
    test "WHEN calling adjustment_reasons THEN returns 5 entries" do
      reasons = Inventory.adjustment_reasons()
      assert length(reasons) == 5
      values = Enum.map(reasons, fn {_label, v} -> v end)
      assert "caducidad" in values
      assert "derrame" in values
      assert "robo" in values
      assert "ajuste_manual" in values
      assert "otro" in values
    end
  end

  # ===========================================================================
  # Low stock detection
  # ===========================================================================

  describe "list_low_stock_products/0" do
    test "GIVEN product with stock at or below min_stock WHEN listing THEN it appears" do
      product =
        insert_product(%{stock_quantity: "5.0", min_stock: "10.0", name: "Low Stock Item"})

      low = Inventory.list_low_stock_products()
      ids = Enum.map(low, & &1.id)
      assert product.id in ids
    end

    test "GIVEN product with stock above min_stock WHEN listing THEN it does NOT appear" do
      product =
        insert_product(%{
          stock_quantity: "50.0",
          min_stock: "10.0",
          name: "Sufficient Stock Item"
        })

      low = Inventory.list_low_stock_products()
      ids = Enum.map(low, & &1.id)
      refute product.id in ids
    end

    test "GIVEN inactive product with low stock WHEN listing THEN it does NOT appear" do
      product =
        insert_product(%{
          stock_quantity: "1.0",
          min_stock: "10.0",
          active: false,
          name: "Inactive Low"
        })

      low = Inventory.list_low_stock_products()
      ids = Enum.map(low, & &1.id)
      refute product.id in ids
    end
  end

  # ===========================================================================
  # Inventory.list_low_stock_variants/0
  # ===========================================================================

  describe "list_low_stock_variants/0" do
    test "GIVEN variant with stock at or below min_stock WHEN listing THEN it appears" do
      product = insert_product(%{name: "Leche Low Var"})

      {:ok, variant} =
        Inventory.create_variant(product.id, %{
          "name" => "Entera",
          "stock_quantity" => "2",
          "min_stock" => "5"
        })

      low = Inventory.list_low_stock_variants()
      ids = Enum.map(low, & &1.id)
      assert variant.id in ids
    end

    test "GIVEN variant with sufficient stock WHEN listing THEN it does NOT appear" do
      product = insert_product(%{name: "Leche High Var"})

      {:ok, variant} =
        Inventory.create_variant(product.id, %{
          "name" => "Deslactosada",
          "stock_quantity" => "50",
          "min_stock" => "5"
        })

      low = Inventory.list_low_stock_variants()
      ids = Enum.map(low, & &1.id)
      refute variant.id in ids
    end
  end

  # ===========================================================================
  # Inventory.toggle_product_active/1
  # ===========================================================================

  describe "toggle_product_active/1" do
    test "GIVEN active product WHEN toggling THEN becomes inactive" do
      product = insert_product()
      assert product.active == true

      {:ok, toggled} = Inventory.toggle_product_active(product)
      assert toggled.active == false
    end

    test "GIVEN inactive product WHEN toggling THEN becomes active" do
      product = insert_product(%{active: false})
      {:ok, reactivated} = Inventory.toggle_product_active(product)
      assert reactivated.active == true
    end
  end

  # ===========================================================================
  # Inventory.get_variant!/1
  # ===========================================================================

  describe "get_variant!/1" do
    test "GIVEN existing variant WHEN fetching by id THEN returns variant" do
      product = insert_product()
      {:ok, variant} = Inventory.create_variant(product.id, %{"name" => "Fetch Me"})

      fetched = Inventory.get_variant!(variant.id)
      assert fetched.id == variant.id
    end

    test "GIVEN non-existent id WHEN fetching THEN raises" do
      assert_raise Ecto.NoResultsError, fn ->
        Inventory.get_variant!(-999)
      end
    end
  end

  # ===========================================================================
  # End-to-end flow
  # ===========================================================================

  describe "full inventory flow" do
    test "create product → create variant → adjust stock → detect low stock → deactivate" do
      user = insert_user()

      # Create product
      {:ok, product} =
        Inventory.create_product(%{
          name: "Granos De Café",
          unit: "gramos",
          net_cost: "50.00",
          stock_quantity: "1000.0",
          min_stock: "100.0"
        })

      # Create variant
      {:ok, _variant} =
        Inventory.create_variant(product.id, %{"name" => "Arabica"})

      # Adjust stock (loss)
      {:ok, _adj} =
        Inventory.create_stock_adjustment(
          %{
            product_id: product.id,
            quantity: Decimal.new("-950"),
            reason: "caducidad",
            notes: "Lote vencido"
          },
          user.id
        )

      # Detect low stock (1000 - 950 = 50 < min_stock 100)
      low = Inventory.list_low_stock_products()
      ids = Enum.map(low, & &1.id)
      assert product.id in ids

      # Deactivate product
      refreshed = Inventory.get_product!(product.id)
      {:ok, inactive} = Inventory.toggle_product_active(refreshed)
      assert inactive.active == false

      # No longer in low stock (inactive)
      low_after = Inventory.list_low_stock_products()
      ids_after = Enum.map(low_after, & &1.id)
      refute product.id in ids_after
    end
  end
end
