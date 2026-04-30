defmodule CRC.ProductionTest do
  use CRC.DataCase, async: true

  alias CRC.Inventory
  alias CRC.Production
  alias CRC.Production.{Recipe, RecipeIngredient, ProductionLog}

  # ---------------------------------------------------------------------------
  # Helpers / fixtures
  # ---------------------------------------------------------------------------

  defp insert_product(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          name: "Insumo Test #{System.unique_integer()}",
          unit: "mililitros",
          net_cost: "10.00",
          stock_quantity: "500.0",
          min_stock: "50.0"
        },
        overrides
      )

    {:ok, product} = Inventory.create_product(attrs)
    product
  end

  defp insert_user(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          name: "Empleado Test",
          email: "empleado#{System.unique_integer()}@cafe.com",
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

  defp recipe_attrs(output_product, overrides \\ %{}) do
    Map.merge(
      %{
        "name" => "Receta Test #{System.unique_integer()}",
        "yield_quantity" => "100",
        "yield_unit" => "mililitros",
        "output_product_id" => output_product.id
      },
      overrides
    )
  end

  defp insert_recipe(output_product, ingredients \\ []) do
    {:ok, recipe} =
      Production.create_recipe(recipe_attrs(output_product), ingredients)

    recipe
  end

  # ---------------------------------------------------------------------------
  # Recipe.changeset/2
  # ---------------------------------------------------------------------------

  describe "Recipe.changeset/2" do
    test "GIVEN valid attrs WHEN building changeset THEN it is valid" do
      output = insert_product()

      changeset =
        Recipe.changeset(%Recipe{}, %{
          "name" => "Oleo de Naranja",
          "yield_quantity" => "500",
          "yield_unit" => "mililitros",
          "output_product_id" => output.id
        })

      assert changeset.valid?
    end

    test "GIVEN missing name WHEN building changeset THEN it is invalid" do
      output = insert_product()

      changeset =
        Recipe.changeset(%Recipe{}, %{
          "yield_quantity" => "100",
          "yield_unit" => "mililitros",
          "output_product_id" => output.id
        })

      refute changeset.valid?
      assert changeset.errors[:name]
    end

    test "GIVEN yield_quantity zero WHEN building changeset THEN it is invalid" do
      output = insert_product()

      changeset =
        Recipe.changeset(%Recipe{}, %{
          "name" => "Receta Inválida",
          "yield_quantity" => "0",
          "yield_unit" => "gramos",
          "output_product_id" => output.id
        })

      refute changeset.valid?
      assert changeset.errors[:yield_quantity]
    end

    test "GIVEN missing output_product_id WHEN building changeset THEN it is invalid" do
      changeset =
        Recipe.changeset(%Recipe{}, %{
          "name" => "Sin Producto",
          "yield_quantity" => "100",
          "yield_unit" => "gramos"
        })

      refute changeset.valid?
      assert changeset.errors[:output_product_id]
    end

    test "GIVEN valid attrs with all fields WHEN building changeset THEN changeset is valid" do
      output = insert_product()

      changeset =
        Recipe.changeset(%Recipe{}, %{
          "name" => "Receta Completa",
          "yield_quantity" => "200",
          "yield_unit" => "mililitros",
          "output_product_id" => output.id
        })

      assert changeset.valid?
    end
  end

  # ---------------------------------------------------------------------------
  # RecipeIngredient.changeset/2
  # ---------------------------------------------------------------------------

  describe "RecipeIngredient.changeset/2" do
    test "GIVEN valid attrs WHEN building changeset THEN it is valid" do
      output = insert_product()
      ingredient = insert_product()
      {:ok, recipe} = Production.create_recipe(recipe_attrs(output), [])

      changeset =
        RecipeIngredient.changeset(%RecipeIngredient{}, %{
          recipe_id: recipe.id,
          product_id: ingredient.id,
          quantity: "2.5"
        })

      assert changeset.valid?
    end

    test "GIVEN quantity of zero WHEN building changeset THEN it is invalid" do
      output = insert_product()
      ingredient = insert_product()
      {:ok, recipe} = Production.create_recipe(recipe_attrs(output), [])

      changeset =
        RecipeIngredient.changeset(%RecipeIngredient{}, %{
          recipe_id: recipe.id,
          product_id: ingredient.id,
          quantity: "0"
        })

      refute changeset.valid?
      assert changeset.errors[:quantity]
    end
  end

  # ---------------------------------------------------------------------------
  # create_recipe/2
  # ---------------------------------------------------------------------------

  describe "create_recipe/2" do
    test "GIVEN valid attrs and no ingredients WHEN creating recipe THEN recipe is persisted" do
      output = insert_product()

      assert {:ok, %Recipe{} = recipe} =
               Production.create_recipe(recipe_attrs(output), [])

      assert recipe.id
      assert recipe.active == true
      assert recipe.output_product_id == output.id
    end

    test "GIVEN valid attrs and ingredient list WHEN creating recipe THEN ingredients are persisted" do
      output = insert_product()
      ing1 = insert_product(%{name: "Naranja"})
      ing2 = insert_product(%{name: "Canela"})

      ingredient_list = [
        %{product_id: ing1.id, quantity: "3"},
        %{product_id: ing2.id, quantity: "1"}
      ]

      {:ok, recipe} = Production.create_recipe(recipe_attrs(output), ingredient_list)
      recipe = Production.get_recipe!(recipe.id)

      assert length(recipe.recipe_ingredients) == 2
      product_ids = Enum.map(recipe.recipe_ingredients, & &1.product_id)
      assert ing1.id in product_ids
      assert ing2.id in product_ids
    end

    test "GIVEN invalid attrs WHEN creating recipe THEN returns error changeset" do
      assert {:error, %Ecto.Changeset{}} =
               Production.create_recipe(%{"name" => ""}, [])
    end

    test "GIVEN attrs with title-case enforcement WHEN creating recipe THEN name is title-cased" do
      output = insert_product()

      {:ok, recipe} =
        Production.create_recipe(
          %{
            "name" => "oleo de naranja",
            "yield_quantity" => "500",
            "yield_unit" => "ml",
            "output_product_id" => output.id
          },
          []
        )

      assert recipe.name == "Oleo De Naranja"
    end
  end

  # ---------------------------------------------------------------------------
  # update_recipe/3
  # ---------------------------------------------------------------------------

  describe "update_recipe/3" do
    test "GIVEN existing recipe WHEN updating attrs THEN recipe is updated" do
      output = insert_product()
      recipe = insert_recipe(output)

      assert {:ok, updated} =
               Production.update_recipe(
                 recipe,
                 %{
                   "name" => "Nuevo Nombre",
                   "yield_quantity" => "200",
                   "yield_unit" => "gramos",
                   "output_product_id" => output.id
                 },
                 []
               )

      assert updated.name == "Nuevo Nombre"
      assert Decimal.to_string(updated.yield_quantity) == "200"
    end

    test "GIVEN existing recipe with ingredients WHEN updating ingredient list THEN old ingredients are replaced" do
      output = insert_product()
      old_ing = insert_product(%{name: "Ingrediente Viejo"})
      new_ing = insert_product(%{name: "Ingrediente Nuevo"})

      recipe = insert_recipe(output, [%{product_id: old_ing.id, quantity: "5"}])

      {:ok, _} =
        Production.update_recipe(recipe, recipe_attrs(output), [
          %{product_id: new_ing.id, quantity: "3"}
        ])

      updated = Production.get_recipe!(recipe.id)
      product_ids = Enum.map(updated.recipe_ingredients, & &1.product_id)

      refute old_ing.id in product_ids
      assert new_ing.id in product_ids
    end

    test "GIVEN invalid attrs WHEN updating recipe THEN returns error changeset" do
      output = insert_product()
      recipe = insert_recipe(output)

      assert {:error, %Ecto.Changeset{}} =
               Production.update_recipe(recipe, %{"name" => ""}, [])
    end
  end

  # ---------------------------------------------------------------------------
  # toggle_recipe_active/1
  # ---------------------------------------------------------------------------

  describe "toggle_recipe_active/1" do
    test "GIVEN active recipe WHEN toggling THEN recipe becomes inactive" do
      output = insert_product()
      recipe = insert_recipe(output)
      assert recipe.active == true

      {:ok, toggled} = Production.toggle_recipe_active(recipe)
      assert toggled.active == false
    end

    test "GIVEN inactive recipe WHEN toggling THEN recipe becomes active" do
      output = insert_product()
      recipe = insert_recipe(output)
      {:ok, inactive} = Production.toggle_recipe_active(recipe)

      {:ok, reactivated} = Production.toggle_recipe_active(inactive)
      assert reactivated.active == true
    end
  end

  # ---------------------------------------------------------------------------
  # list_active_recipes/0
  # ---------------------------------------------------------------------------

  describe "list_active_recipes/0" do
    test "GIVEN active and inactive recipes WHEN listing active THEN only active are returned" do
      output = insert_product()

      active_recipe = insert_recipe(output)
      inactive_recipe = insert_recipe(insert_product())
      Production.toggle_recipe_active(inactive_recipe)

      results = Production.list_active_recipes()
      ids = Enum.map(results, & &1.id)

      assert active_recipe.id in ids
      refute inactive_recipe.id in ids
    end

    test "GIVEN active recipe WHEN listing THEN output_product and ingredients are preloaded" do
      output = insert_product(%{name: "Producto Salida"})
      ing = insert_product(%{name: "Ingrediente Preload"})
      insert_recipe(output, [%{product_id: ing.id, quantity: "2"}])

      [recipe | _] = Production.list_active_recipes()

      assert recipe.output_product.id == output.id
      assert length(recipe.recipe_ingredients) == 1
      assert hd(recipe.recipe_ingredients).product.id == ing.id
    end
  end

  # ---------------------------------------------------------------------------
  # list_all_recipes/0
  # ---------------------------------------------------------------------------

  describe "list_all_recipes/0" do
    test "GIVEN active and inactive recipes WHEN listing all THEN both are returned" do
      output = insert_product()
      active = insert_recipe(output)
      inactive = insert_recipe(insert_product())
      Production.toggle_recipe_active(inactive)

      ids = Production.list_all_recipes() |> Enum.map(& &1.id)

      assert active.id in ids
      assert inactive.id in ids
    end
  end

  # ---------------------------------------------------------------------------
  # list_today_logs/0
  # ---------------------------------------------------------------------------

  describe "list_today_logs/0" do
    test "GIVEN a log from today WHEN listing today logs THEN it is included" do
      output = insert_product()
      ing = insert_product(%{stock_quantity: "1000.0"})
      recipe = insert_recipe(output, [%{product_id: ing.id, quantity: "10"}])
      user = insert_user()

      {:ok, _} = Production.log_production(recipe.id, "1", user.id)

      logs = Production.list_today_logs()
      assert length(logs) >= 1
    end

    test "GIVEN a log from today WHEN listing THEN recipe and user are preloaded" do
      output = insert_product()
      ing = insert_product(%{stock_quantity: "1000.0"})
      recipe = insert_recipe(output, [%{product_id: ing.id, quantity: "5"}])
      user = insert_user()

      {:ok, _} = Production.log_production(recipe.id, "1", user.id)

      [log | _] = Production.list_today_logs()
      assert log.recipe.id == recipe.id
      assert log.produced_by.id == user.id
    end
  end

  # ---------------------------------------------------------------------------
  # log_production/4  — THE CRITICAL SCENARIO
  # ---------------------------------------------------------------------------

  describe "log_production/4" do
    test "GIVEN a recipe with 1 ingredient WHEN logging 1 batch THEN ingredient stock is deducted" do
      # GIVEN
      output = insert_product(%{name: "Oleo", stock_quantity: "0.0"})
      ing = insert_product(%{name: "Naranja", stock_quantity: "100.0"})
      # recipe: consumes 5 naranjas per batch, yields 500 ml
      recipe = insert_recipe(output, [%{product_id: ing.id, quantity: "5"}])
      user = insert_user()

      # WHEN
      assert {:ok, %ProductionLog{}} = Production.log_production(recipe.id, "1", user.id)

      # THEN
      refreshed_ing = Inventory.get_product!(ing.id)
      assert Decimal.compare(refreshed_ing.stock_quantity, Decimal.new("95.0")) == :eq
    end

    test "GIVEN a recipe WHEN logging 1 batch THEN output product stock is increased" do
      # GIVEN
      output = insert_product(%{name: "Oleo", stock_quantity: "0.0"})
      ing = insert_product(%{stock_quantity: "500.0"})
      recipe = insert_recipe(output, [%{product_id: ing.id, quantity: "3"}])
      user = insert_user()

      # WHEN
      Production.log_production(recipe.id, "1", user.id)

      # THEN — yield_quantity is 100 (from recipe_attrs default)
      refreshed_output = Inventory.get_product!(output.id)
      assert Decimal.compare(refreshed_output.stock_quantity, Decimal.new("100.0")) == :eq
    end

    test "GIVEN a recipe WHEN logging 2.5 batches THEN stock is scaled proportionally" do
      # GIVEN
      output = insert_product(%{stock_quantity: "0.0"})
      ing = insert_product(%{stock_quantity: "500.0"})
      # 10 units per batch
      recipe = insert_recipe(output, [%{product_id: ing.id, quantity: "10"}])
      user = insert_user()

      # WHEN: 2.5 batches
      {:ok, log} = Production.log_production(recipe.id, "2.5", user.id)

      # THEN: 10 × 2.5 = 25 deducted → 475 remaining; yield 100 × 2.5 = 250 added
      refreshed_ing = Inventory.get_product!(ing.id)
      refreshed_out = Inventory.get_product!(output.id)

      assert Decimal.compare(refreshed_ing.stock_quantity, Decimal.new("475.0")) == :eq
      assert Decimal.compare(refreshed_out.stock_quantity, Decimal.new("250.0")) == :eq
      assert Decimal.compare(log.batches, Decimal.new("2.5")) == :eq
    end

    test "GIVEN a recipe with multiple ingredients WHEN logging THEN all ingredients are deducted" do
      # GIVEN
      output = insert_product(%{stock_quantity: "0.0"})
      ing1 = insert_product(%{name: "Ing A", stock_quantity: "100.0"})
      ing2 = insert_product(%{name: "Ing B", stock_quantity: "200.0"})

      recipe =
        insert_recipe(output, [
          %{product_id: ing1.id, quantity: "4"},
          %{product_id: ing2.id, quantity: "8"}
        ])

      user = insert_user()

      # WHEN: 1 batch
      {:ok, _} = Production.log_production(recipe.id, "1", user.id)

      # THEN
      assert Decimal.compare(Inventory.get_product!(ing1.id).stock_quantity, Decimal.new("96.0")) ==
               :eq

      assert Decimal.compare(Inventory.get_product!(ing2.id).stock_quantity, Decimal.new("192.0")) ==
               :eq
    end

    test "GIVEN zero batches WHEN logging production THEN returns :invalid_batches error" do
      # GIVEN
      output = insert_product()
      recipe = insert_recipe(output)
      user = insert_user()

      # WHEN / THEN
      assert {:error, :invalid_batches} = Production.log_production(recipe.id, "0", user.id)
    end

    test "GIVEN negative batches WHEN logging production THEN returns :invalid_batches error" do
      # GIVEN
      output = insert_product()
      recipe = insert_recipe(output)
      user = insert_user()

      # WHEN / THEN
      assert {:error, :invalid_batches} = Production.log_production(recipe.id, "-1", user.id)
    end

    test "GIVEN non-numeric batches WHEN logging production THEN returns :invalid_batches error" do
      # GIVEN
      output = insert_product()
      recipe = insert_recipe(output)
      user = insert_user()

      # WHEN / THEN
      assert {:error, :invalid_batches} = Production.log_production(recipe.id, "abc", user.id)
    end

    test "GIVEN optional notes WHEN logging production THEN notes are persisted in log" do
      # GIVEN
      output = insert_product(%{stock_quantity: "0.0"})
      ing = insert_product(%{stock_quantity: "500.0"})
      recipe = insert_recipe(output, [%{product_id: ing.id, quantity: "1"}])
      user = insert_user()

      # WHEN
      {:ok, log} = Production.log_production(recipe.id, "1", user.id, "Lote de prueba especial")

      # THEN
      assert log.notes == "Lote de prueba especial"
    end

    test "GIVEN a log WHEN production is logged THEN log references recipe and user" do
      # GIVEN
      output = insert_product(%{stock_quantity: "0.0"})
      ing = insert_product(%{stock_quantity: "500.0"})
      recipe = insert_recipe(output, [%{product_id: ing.id, quantity: "2"}])
      user = insert_user()

      # WHEN
      {:ok, log} = Production.log_production(recipe.id, "1", user.id)

      # THEN
      assert log.recipe_id == recipe.id
      assert log.produced_by_id == user.id
      assert %DateTime{} = log.produced_at
    end
  end

  # ---------------------------------------------------------------------------
  # recipe_unit_cost/1
  # ---------------------------------------------------------------------------

  describe "recipe_unit_cost/1" do
    test "GIVEN recipe with priced ingredients WHEN computing cost THEN returns cost per output unit" do
      # GIVEN: 2 naranjas @ $5 each = $10 total; yield = 100 ml → $0.10/ml
      output = insert_product()
      naranja = insert_product(%{net_cost: "5.00"})
      recipe = insert_recipe(output, [%{product_id: naranja.id, quantity: "2"}])
      recipe = Production.get_recipe!(recipe.id)

      # WHEN
      cost = Production.recipe_unit_cost(recipe)

      # THEN: (2 × 5.00) / 100 = 0.1000
      assert Decimal.compare(cost, Decimal.new("0.1000")) == :eq
    end

    test "GIVEN recipe with no ingredients WHEN computing cost THEN returns nil" do
      output = insert_product()
      recipe = insert_recipe(output, [])
      recipe = Production.get_recipe!(recipe.id)

      assert Production.recipe_unit_cost(recipe) == nil
    end

    test "GIVEN recipe with multiple ingredients WHEN computing cost THEN sums all ingredient costs" do
      # GIVEN: 3 units @ $2 + 1 unit @ $6 = $12; yield = 100 → $0.12/unit
      output = insert_product()
      ing1 = insert_product(%{net_cost: "2.00"})
      ing2 = insert_product(%{net_cost: "6.00"})

      recipe =
        insert_recipe(output, [
          %{product_id: ing1.id, quantity: "3"},
          %{product_id: ing2.id, quantity: "1"}
        ])

      recipe = Production.get_recipe!(recipe.id)
      cost = Production.recipe_unit_cost(recipe)

      assert Decimal.compare(cost, Decimal.new("0.1200")) == :eq
    end
  end

  # ---------------------------------------------------------------------------
  # list_recent_logs/1
  # ---------------------------------------------------------------------------

  describe "list_recent_logs/1" do
    test "GIVEN multiple logs WHEN listing with limit THEN respects the limit" do
      output = insert_product(%{stock_quantity: "9999.0"})
      ing = insert_product(%{stock_quantity: "9999.0"})
      recipe = insert_recipe(output, [%{product_id: ing.id, quantity: "1"}])
      user = insert_user()

      for _ <- 1..5, do: Production.log_production(recipe.id, "1", user.id)

      assert length(Production.list_recent_logs(3)) == 3
    end

    test "GIVEN logs WHEN listing THEN they are ordered by most recent first" do
      output = insert_product(%{stock_quantity: "9999.0"})
      ing = insert_product(%{stock_quantity: "9999.0"})
      recipe = insert_recipe(output, [%{product_id: ing.id, quantity: "1"}])
      user = insert_user()

      Production.log_production(recipe.id, "1", user.id)
      Production.log_production(recipe.id, "2", user.id)

      [first | _] = Production.list_recent_logs(10)
      assert Decimal.compare(first.batches, Decimal.new("2")) == :eq
    end
  end
end
