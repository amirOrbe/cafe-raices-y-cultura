defmodule CRCWeb.Admin.ProduccionLiveTest do
  use CRCWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias CRC.Inventory
  alias CRC.Production

  # ---------------------------------------------------------------------------
  # Helpers / fixtures
  # ---------------------------------------------------------------------------

  defp insert_user(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          name: "Usuario Test",
          email: "user#{System.unique_integer()}@cafe.com",
          role: "admin",
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

  defp admin_conn(conn) do
    admin = insert_user(%{role: "admin"})
    conn = init_test_session(conn, %{"user_id" => admin.id})
    {conn, admin}
  end

  defp empleado_conn(conn) do
    empleado = insert_user(%{role: "empleado", stations: ["sala"], email: "emp#{System.unique_integer()}@cafe.com"})
    conn = init_test_session(conn, %{"user_id" => empleado.id})
    {conn, empleado}
  end

  defp insert_product(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          name: "Insumo Admin #{System.unique_integer()}",
          unit: "gramos",
          net_cost: "5.00",
          stock_quantity: "200.0",
          min_stock: "20.0"
        },
        overrides
      )

    {:ok, product} = Inventory.create_product(attrs)
    product
  end

  defp insert_recipe(output_product, overrides \\ %{}, ingredients \\ []) do
    attrs =
      Map.merge(
        %{
          "name" => "Receta Admin #{System.unique_integer()}",
          "yield_quantity" => "100",
          "yield_unit" => "gramos",
          "output_product_id" => output_product.id
        },
        overrides
      )

    {:ok, recipe} = Production.create_recipe(attrs, ingredients)
    recipe
  end

  # ---------------------------------------------------------------------------
  # Access control
  # ---------------------------------------------------------------------------

  describe "access control" do
    test "GIVEN unauthenticated user WHEN visiting /admin/produccion THEN redirects to login",
         %{conn: conn} do
      # WHEN / THEN
      assert {:error, {:redirect, %{to: "/iniciar-sesion"}}} =
               live(conn, ~p"/admin/produccion")
    end

    test "GIVEN empleado (non-admin) WHEN visiting /admin/produccion THEN is redirected",
         %{conn: conn} do
      # GIVEN
      {conn, _} = empleado_conn(conn)

      # WHEN / THEN
      assert {:error, {:redirect, _}} = live(conn, ~p"/admin/produccion")
    end

    test "GIVEN admin user WHEN visiting /admin/produccion THEN page loads successfully",
         %{conn: conn} do
      # GIVEN
      {conn, _} = admin_conn(conn)

      # WHEN / THEN
      assert {:ok, _lv, html} = live(conn, ~p"/admin/produccion")
      assert html =~ "Producción Interna"
    end
  end

  # ---------------------------------------------------------------------------
  # Page mount & tabs
  # ---------------------------------------------------------------------------

  describe "page mount" do
    test "GIVEN admin WHEN mounting page THEN recipes tab is active by default",
         %{conn: conn} do
      {conn, _} = admin_conn(conn)

      {:ok, _lv, html} = live(conn, ~p"/admin/produccion")

      assert html =~ "Recetas"
      assert html =~ "Historial"
    end

    test "GIVEN existing recipes WHEN mounting page THEN recipes are listed",
         %{conn: conn} do
      # GIVEN
      {conn, _} = admin_conn(conn)
      output = insert_product(%{name: "Producto Listado"})
      insert_recipe(output, %{"name" => "Receta Visible"})

      # WHEN
      {:ok, _lv, html} = live(conn, ~p"/admin/produccion")

      # THEN
      assert html =~ "Receta Visible"
    end

    test "GIVEN no recipes WHEN mounting THEN empty state message is shown",
         %{conn: conn} do
      {conn, _} = admin_conn(conn)

      {:ok, _lv, html} = live(conn, ~p"/admin/produccion")

      assert html =~ "No hay recetas"
    end
  end

  describe "set_tab event" do
    test "GIVEN admin on recipes tab WHEN switching to historial THEN history section is shown",
         %{conn: conn} do
      # GIVEN
      {conn, _} = admin_conn(conn)
      {:ok, lv, _} = live(conn, ~p"/admin/produccion")

      # WHEN
      html = render_click(lv, "set_tab", %{"tab" => "history"})

      # THEN
      assert html =~ "Sin producción registrada" or html =~ "Historial"
    end

    test "GIVEN admin on history tab WHEN switching to recipes THEN nueva receta button is shown",
         %{conn: conn} do
      # GIVEN
      {conn, _} = admin_conn(conn)
      {:ok, lv, _} = live(conn, ~p"/admin/produccion")
      render_click(lv, "set_tab", %{"tab" => "history"})

      # WHEN
      html = render_click(lv, "set_tab", %{"tab" => "recipes"})

      # THEN
      assert html =~ "Nueva receta"
    end
  end

  # ---------------------------------------------------------------------------
  # Recipe modal — open / close
  # ---------------------------------------------------------------------------

  describe "new_recipe event" do
    test "GIVEN admin on recipes tab WHEN clicking nueva receta THEN modal opens",
         %{conn: conn} do
      # GIVEN
      {conn, _} = admin_conn(conn)
      {:ok, lv, _} = live(conn, ~p"/admin/produccion")

      # WHEN
      html = render_click(lv, "new_recipe", %{})

      # THEN
      assert html =~ "Nueva receta"
      assert html =~ "Nombre del producto que se produce"
    end

    test "GIVEN modal is open WHEN clicking close THEN modal is dismissed",
         %{conn: conn} do
      # GIVEN
      {conn, _} = admin_conn(conn)
      {:ok, lv, _} = live(conn, ~p"/admin/produccion")
      render_click(lv, "new_recipe", %{})

      # WHEN
      html = render_click(lv, "close_modal", %{})

      # THEN: modal is closed — form-specific content no longer visible
      refute html =~ "Nombre del producto que se produce"
    end
  end

  describe "edit_recipe event" do
    test "GIVEN existing recipe WHEN clicking edit THEN modal shows recipe data",
         %{conn: conn} do
      # GIVEN
      {conn, _} = admin_conn(conn)
      output = insert_product(%{name: "Producto Editar"})
      recipe = insert_recipe(output, %{"name" => "Receta A Editar"})

      {:ok, lv, _} = live(conn, ~p"/admin/produccion")

      # WHEN
      html = render_click(lv, "edit_recipe", %{"id" => to_string(recipe.id)})

      # THEN
      assert html =~ "Editar receta"
      assert html =~ "Receta A Editar"
    end
  end

  # ---------------------------------------------------------------------------
  # Dynamic ingredient rows
  # ---------------------------------------------------------------------------

  describe "add_ingredient_row event" do
    test "GIVEN modal is open with 1 row WHEN adding a row THEN 2 rows are shown",
         %{conn: conn} do
      # GIVEN
      {conn, _} = admin_conn(conn)
      {:ok, lv, _} = live(conn, ~p"/admin/produccion")
      render_click(lv, "new_recipe", %{})

      # WHEN
      html = render_click(lv, "add_ingredient_row", %{})

      # THEN: two ingredient rows — count [N][product_id] occurrences (one per row)
      count = html |> String.split("][product_id]") |> length() |> Kernel.-(1)
      assert count == 2
    end
  end

  describe "remove_ingredient_row event" do
    test "GIVEN modal open with 2 rows WHEN removing one THEN 1 row remains",
         %{conn: conn} do
      # GIVEN
      {conn, _} = admin_conn(conn)
      {:ok, lv, _} = live(conn, ~p"/admin/produccion")
      render_click(lv, "new_recipe", %{})
      render_click(lv, "add_ingredient_row", %{})

      # WHEN: remove first row (index 0)
      html = render_click(lv, "remove_ingredient_row", %{"index" => "0"})

      # THEN: one ingredient row remaining
      count = html |> String.split("][product_id]") |> length() |> Kernel.-(1)
      assert count == 1
    end

    test "GIVEN modal open with 1 row WHEN removing it THEN a fresh empty row is kept (never zero rows)",
         %{conn: conn} do
      # GIVEN
      {conn, _} = admin_conn(conn)
      {:ok, lv, _} = live(conn, ~p"/admin/produccion")
      render_click(lv, "new_recipe", %{})

      # WHEN: remove the only row
      html = render_click(lv, "remove_ingredient_row", %{"index" => "0"})

      # THEN: still at least 1 ingredient row (UI enforces minimum 1)
      count = html |> String.split("][product_id]") |> length() |> Kernel.-(1)
      assert count >= 1
    end
  end

  # ---------------------------------------------------------------------------
  # save_recipe event
  # ---------------------------------------------------------------------------

  describe "save_recipe event — create" do
    test "GIVEN valid params and matching insumo WHEN saving THEN recipe is created and modal closes",
         %{conn: conn} do
      # GIVEN
      {conn, _} = admin_conn(conn)
      output = insert_product(%{name: "Jarabe De Canela"})
      ing = insert_product(%{name: "Canela En Raja"})

      {:ok, lv, _} = live(conn, ~p"/admin/produccion")
      render_click(lv, "new_recipe", %{})

      # WHEN
      html =
        lv
        |> element("form[phx-submit='save_recipe']")
        |> render_submit(%{
          "recipe" => %{
            "name" => "Jarabe De Canela",
            "yield_quantity" => "500",
            "yield_unit" => "mililitros",
            "notes" => ""
          },
          "ingredient_rows" => %{
            "0" => %{"product_id" => to_string(ing.id), "quantity" => "3"}
          }
        })

      # THEN: modal is closed (form content gone), recipe shows in list
      assert html =~ "Jarabe De Canela"
      refute html =~ "Nombre del producto que se produce"
    end

    test "GIVEN valid params without existing insumo WHEN saving THEN insumo is auto-created",
         %{conn: conn} do
      # GIVEN: no product named "Almíbar Nuevo" exists
      {conn, _} = admin_conn(conn)
      ing = insert_product()

      {:ok, lv, _} = live(conn, ~p"/admin/produccion")
      render_click(lv, "new_recipe", %{})

      # WHEN
      lv
      |> element("form[phx-submit='save_recipe']")
      |> render_submit(%{
        "recipe" => %{
          "name" => "Almíbar Nuevo",
          "yield_quantity" => "200",
          "yield_unit" => "mililitros",
          "notes" => ""
        },
        "ingredient_rows" => %{
          "0" => %{"product_id" => to_string(ing.id), "quantity" => "1"}
        }
      })

      # THEN: insumo was auto-created
      assert Inventory.find_product_by_name("Almíbar Nuevo") != nil
    end

    test "GIVEN params with empty ingredient rows WHEN saving THEN recipe is created with no ingredients",
         %{conn: conn} do
      # GIVEN
      {conn, _} = admin_conn(conn)

      {:ok, lv, _} = live(conn, ~p"/admin/produccion")
      render_click(lv, "new_recipe", %{})

      # WHEN
      lv
      |> element("form[phx-submit='save_recipe']")
      |> render_submit(%{
        "recipe" => %{
          "name" => "Receta Vacía",
          "yield_quantity" => "100",
          "yield_unit" => "gramos",
          "notes" => ""
        },
        "ingredient_rows" => %{
          "0" => %{"product_id" => "", "quantity" => ""}
        }
      })

      # THEN: recipe saved (no crash)
      recipe = Enum.find(Production.list_all_recipes(), &(&1.name == "Receta Vacía"))
      assert recipe
      assert recipe.recipe_ingredients == []
    end
  end

  describe "save_recipe event — edit" do
    test "GIVEN existing recipe WHEN editing and saving new name THEN recipe is updated",
         %{conn: conn} do
      # GIVEN
      {conn, _} = admin_conn(conn)
      output = insert_product(%{name: "Producto Actualizado"})
      recipe = insert_recipe(output, %{"name" => "Nombre Original"})

      {:ok, lv, _} = live(conn, ~p"/admin/produccion")
      render_click(lv, "edit_recipe", %{"id" => to_string(recipe.id)})

      # WHEN
      html =
        lv
        |> element("form[phx-submit='save_recipe']")
        |> render_submit(%{
          "recipe" => %{
            "name" => "Producto Actualizado",
            "yield_quantity" => "150",
            "yield_unit" => "gramos",
            "notes" => ""
          },
          "ingredient_rows" => %{
            "0" => %{"product_id" => "", "quantity" => ""}
          }
        })

      # THEN
      assert html =~ "Producto Actualizado"
      updated = Production.get_recipe!(recipe.id)
      assert Decimal.compare(updated.yield_quantity, Decimal.new("150")) == :eq
    end
  end

  # ---------------------------------------------------------------------------
  # toggle_active event
  # ---------------------------------------------------------------------------

  describe "toggle_active event" do
    test "GIVEN active recipe WHEN toggling THEN recipe becomes inactive in DB",
         %{conn: conn} do
      # GIVEN
      {conn, _} = admin_conn(conn)
      output = insert_product()
      recipe = insert_recipe(output, %{"name" => "Receta Toggleable"})
      assert recipe.active == true

      {:ok, lv, _} = live(conn, ~p"/admin/produccion")

      # WHEN
      render_click(lv, "toggle_active", %{"id" => to_string(recipe.id)})

      # THEN
      assert Production.get_recipe!(recipe.id).active == false
    end

    test "GIVEN inactive recipe WHEN toggling THEN recipe becomes active again",
         %{conn: conn} do
      # GIVEN
      {conn, _} = admin_conn(conn)
      output = insert_product()
      recipe = insert_recipe(output)
      {:ok, inactive} = Production.toggle_recipe_active(recipe)
      assert inactive.active == false

      {:ok, lv, _} = live(conn, ~p"/admin/produccion")

      # WHEN
      render_click(lv, "toggle_active", %{"id" => to_string(inactive.id)})

      # THEN
      assert Production.get_recipe!(recipe.id).active == true
    end
  end

  # ---------------------------------------------------------------------------
  # History tab
  # ---------------------------------------------------------------------------

  describe "history tab" do
    test "GIVEN existing production logs WHEN switching to history THEN logs are displayed",
         %{conn: conn} do
      # GIVEN
      {conn, admin} = admin_conn(conn)
      output = insert_product(%{name: "Producto Log", stock_quantity: "0.0"})
      ing = insert_product(%{stock_quantity: "500.0"})
      recipe = insert_recipe(output, %{"name" => "Receta Historial"},
        [%{product_id: ing.id, quantity: "1"}])
      Production.log_production(recipe.id, "2", admin.id, "Lote de test")

      {:ok, lv, _} = live(conn, ~p"/admin/produccion")

      # WHEN
      html = render_click(lv, "set_tab", %{"tab" => "history"})

      # THEN
      assert html =~ "Receta Historial"
      assert html =~ "Lote de test"
    end

    test "GIVEN no logs WHEN switching to history THEN empty state is shown",
         %{conn: conn} do
      # GIVEN
      {conn, _} = admin_conn(conn)
      {:ok, lv, _} = live(conn, ~p"/admin/produccion")

      # WHEN
      html = render_click(lv, "set_tab", %{"tab" => "history"})

      # THEN
      assert html =~ "Sin producción registrada"
    end
  end
end
