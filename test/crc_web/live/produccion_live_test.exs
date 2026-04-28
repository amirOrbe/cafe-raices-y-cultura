defmodule CRCWeb.ProduccionLiveTest do
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

  defp staff_conn(conn) do
    user = insert_user(%{role: "empleado", stations: ["sala"], email: "staff#{System.unique_integer()}@cafe.com"})
    conn = init_test_session(conn, %{"user_id" => user.id})
    {conn, user}
  end

  defp admin_conn(conn) do
    admin = insert_user(%{role: "admin"})
    conn = init_test_session(conn, %{"user_id" => admin.id})
    {conn, admin}
  end

  defp insert_product(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          name: "Insumo #{System.unique_integer()}",
          unit: "gramos",
          net_cost: "5.00",
          stock_quantity: "500.0",
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
          "name" => "Receta Staff #{System.unique_integer()}",
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
    test "GIVEN unauthenticated user WHEN visiting /produccion THEN redirects to login",
         %{conn: conn} do
      # WHEN / THEN
      assert {:error, {:redirect, %{to: "/iniciar-sesion"}}} =
               live(conn, ~p"/produccion")
    end

    test "GIVEN authenticated empleado WHEN visiting /produccion THEN page loads",
         %{conn: conn} do
      # GIVEN
      {conn, _} = staff_conn(conn)

      # WHEN / THEN
      assert {:ok, _lv, html} = live(conn, ~p"/produccion")
      assert html =~ "Producción Interna"
    end

    test "GIVEN authenticated admin WHEN visiting /produccion THEN page loads",
         %{conn: conn} do
      # GIVEN
      {conn, _} = admin_conn(conn)

      # WHEN / THEN
      assert {:ok, _lv, html} = live(conn, ~p"/produccion")
      assert html =~ "Producción Interna"
    end
  end

  # ---------------------------------------------------------------------------
  # Mount state
  # ---------------------------------------------------------------------------

  describe "page mount" do
    test "GIVEN active recipes exist WHEN mounting THEN recipes are shown in selection grid",
         %{conn: conn} do
      # GIVEN
      {conn, _} = staff_conn(conn)
      output = insert_product(%{name: "Jarabe Visible"})
      insert_recipe(output, %{"name" => "Receta Visible"})

      # WHEN
      {:ok, _lv, html} = live(conn, ~p"/produccion")

      # THEN
      assert html =~ "Receta Visible"
      assert html =~ "¿Qué vas a producir?"
    end

    test "GIVEN no active recipes WHEN mounting THEN empty state message is shown",
         %{conn: conn} do
      # GIVEN
      {conn, _} = staff_conn(conn)

      # WHEN
      {:ok, _lv, html} = live(conn, ~p"/produccion")

      # THEN
      assert html =~ "No hay recetas activas"
    end

    test "GIVEN no production logs today WHEN mounting THEN empty log message is shown",
         %{conn: conn} do
      # GIVEN
      {conn, _} = staff_conn(conn)

      # WHEN
      {:ok, _lv, html} = live(conn, ~p"/produccion")

      # THEN
      assert html =~ "Sin producción registrada hoy"
    end

    test "GIVEN inactive recipe WHEN mounting THEN inactive recipe is NOT shown",
         %{conn: conn} do
      # GIVEN
      {conn, _} = staff_conn(conn)
      output = insert_product(%{name: "Producto Inactivo"})
      recipe = insert_recipe(output, %{"name" => "Receta Inactiva"})
      {:ok, _} = Production.toggle_recipe_active(recipe)

      # WHEN
      {:ok, _lv, html} = live(conn, ~p"/produccion")

      # THEN
      refute html =~ "Receta Inactiva"
    end
  end

  # ---------------------------------------------------------------------------
  # select_recipe event
  # ---------------------------------------------------------------------------

  describe "select_recipe event" do
    test "GIVEN recipes listed WHEN selecting one THEN batch form is shown",
         %{conn: conn} do
      # GIVEN
      {conn, _} = staff_conn(conn)
      output = insert_product(%{name: "Salsa De Chile"})
      recipe = insert_recipe(output, %{"name" => "Salsa De Chile Rojo"})

      {:ok, lv, _} = live(conn, ~p"/produccion")

      # WHEN
      html = render_click(lv, "select_recipe", %{"id" => to_string(recipe.id)})

      # THEN
      assert html =~ "Salsa De Chile Rojo"
      assert html =~ "Receta seleccionada"
      assert html =~ "¿Cuántos lotes hiciste?"
      assert html =~ "Registrar lote"
    end

    test "GIVEN recipe with ingredients WHEN selecting THEN ingredient preview is shown",
         %{conn: conn} do
      # GIVEN
      {conn, _} = staff_conn(conn)
      output = insert_product(%{name: "Oleo Citrico", stock_quantity: "0.0"})
      ing = insert_product(%{name: "Naranja", stock_quantity: "200.0"})
      recipe = insert_recipe(
        output,
        %{"name" => "Oleo De Naranja"},
        [%{product_id: ing.id, quantity: "50"}]
      )

      {:ok, lv, _} = live(conn, ~p"/produccion")

      # WHEN
      html = render_click(lv, "select_recipe", %{"id" => to_string(recipe.id)})

      # THEN: ingredient listed in preview
      assert html =~ "Naranja"
      assert html =~ "Oleo De Naranja"
      assert html =~ "Resumen del lote"
    end

    test "GIVEN recipe selected WHEN clearing selection THEN recipe list is shown again",
         %{conn: conn} do
      # GIVEN
      {conn, _} = staff_conn(conn)
      output = insert_product()
      recipe = insert_recipe(output, %{"name" => "Receta Para Limpiar"})

      {:ok, lv, _} = live(conn, ~p"/produccion")
      render_click(lv, "select_recipe", %{"id" => to_string(recipe.id)})

      # WHEN
      html = render_click(lv, "clear_recipe", %{})

      # THEN: back to selection step
      assert html =~ "¿Qué vas a producir?"
      refute html =~ "Receta seleccionada"
    end
  end

  # ---------------------------------------------------------------------------
  # log_production event — success path
  # ---------------------------------------------------------------------------

  describe "log_production event — success" do
    test "GIVEN recipe selected WHEN logging THEN success flash is shown",
         %{conn: conn} do
      # GIVEN
      {conn, user} = staff_conn(conn)
      output = insert_product(%{name: "Almíbar", stock_quantity: "0.0"})
      ing = insert_product(%{name: "Azúcar", stock_quantity: "1000.0"})
      recipe = insert_recipe(
        output,
        %{"name" => "Almíbar Simple"},
        [%{product_id: ing.id, quantity: "100"}]
      )

      {:ok, lv, _} = live(conn, ~p"/produccion")
      render_click(lv, "select_recipe", %{"id" => to_string(recipe.id)})

      # WHEN
      html = render_click(lv, "log_production", %{})

      # THEN
      assert html =~ "Lote registrado"
    end

    test "GIVEN recipe selected WHEN logging THEN recipe selection is cleared after success",
         %{conn: conn} do
      # GIVEN
      {conn, _} = staff_conn(conn)
      output = insert_product(%{name: "Crema Vainilla", stock_quantity: "0.0"})
      ing = insert_product(%{name: "Nata", stock_quantity: "500.0"})
      recipe = insert_recipe(
        output,
        %{"name" => "Crema Sabor Vainilla"},
        [%{product_id: ing.id, quantity: "50"}]
      )

      {:ok, lv, _} = live(conn, ~p"/produccion")
      render_click(lv, "select_recipe", %{"id" => to_string(recipe.id)})

      # WHEN
      html = render_click(lv, "log_production", %{})

      # THEN: back to recipe selection view
      assert html =~ "¿Qué vas a producir?"
      refute html =~ "Receta seleccionada"
    end

    test "GIVEN recipe with ingredients WHEN logging 1 batch THEN ingredient stock is deducted",
         %{conn: conn} do
      # GIVEN
      {conn, _} = staff_conn(conn)
      output = insert_product(%{name: "Jarabe Canela Prueba", stock_quantity: "0.0"})
      ing = insert_product(%{name: "Canela En Polvo", stock_quantity: "500.0"})
      recipe = insert_recipe(
        output,
        %{"name" => "Jarabe Canela"},
        [%{product_id: ing.id, quantity: "30"}]
      )

      {:ok, lv, _} = live(conn, ~p"/produccion")
      render_click(lv, "select_recipe", %{"id" => to_string(recipe.id)})

      # WHEN: batches_input defaults to "1"
      render_click(lv, "log_production", %{})

      # THEN: 500 - 30 = 470
      refreshed = Inventory.get_product!(ing.id)
      assert Decimal.compare(refreshed.stock_quantity, Decimal.new("470.0")) == :eq
    end

    test "GIVEN recipe selected WHEN logging THEN output product stock increases",
         %{conn: conn} do
      # GIVEN
      {conn, _} = staff_conn(conn)
      output = insert_product(%{name: "Jarabe De Vainilla", stock_quantity: "0.0"})
      ing = insert_product(%{name: "Vainilla", stock_quantity: "200.0"})
      recipe = insert_recipe(
        output,
        %{"name" => "Jarabe Vainilla", "yield_quantity" => "500"},
        [%{product_id: ing.id, quantity: "10"}]
      )

      {:ok, lv, _} = live(conn, ~p"/produccion")
      render_click(lv, "select_recipe", %{"id" => to_string(recipe.id)})
      render_click(lv, "log_production", %{})

      # THEN: 0 + 500 = 500
      refreshed = Inventory.get_product!(output.id)
      assert Decimal.compare(refreshed.stock_quantity, Decimal.new("500.0")) == :eq
    end

    test "GIVEN log registered WHEN viewing page THEN log appears in today's production section",
         %{conn: conn} do
      # GIVEN
      {conn, _} = staff_conn(conn)
      output = insert_product(%{name: "Miel Jengibre", stock_quantity: "0.0"})
      ing = insert_product(%{name: "Jengibre", stock_quantity: "300.0"})
      recipe = insert_recipe(
        output,
        %{"name" => "Miel De Jengibre"},
        [%{product_id: ing.id, quantity: "20"}]
      )

      {:ok, lv, _} = live(conn, ~p"/produccion")
      render_click(lv, "select_recipe", %{"id" => to_string(recipe.id)})

      # WHEN
      html = render_click(lv, "log_production", %{})

      # THEN: today logs section updated
      assert html =~ "Miel De Jengibre"
      refute html =~ "Sin producción registrada hoy"
    end
  end

  # ---------------------------------------------------------------------------
  # log_production event — error paths
  # ---------------------------------------------------------------------------

  describe "log_production event — error" do
    test "GIVEN batches_input is 0 WHEN logging THEN error flash is shown",
         %{conn: conn} do
      # GIVEN
      {conn, _} = staff_conn(conn)
      output = insert_product(%{name: "Producto Cero"})
      ing = insert_product()
      recipe = insert_recipe(output, %{"name" => "Receta Cero"}, [%{product_id: ing.id, quantity: "1"}])

      {:ok, lv, _} = live(conn, ~p"/produccion")
      render_click(lv, "select_recipe", %{"id" => to_string(recipe.id)})

      # Override batches_input to "0"
      render_click(lv, "update_batches", %{"value" => "0"})

      # WHEN
      html = render_click(lv, "log_production", %{})

      # THEN
      assert html =~ "La cantidad de lotes debe ser mayor a 0"
    end

    test "GIVEN batches_input is negative WHEN logging THEN error flash is shown",
         %{conn: conn} do
      # GIVEN
      {conn, _} = staff_conn(conn)
      output = insert_product()
      ing = insert_product()
      recipe = insert_recipe(output, %{"name" => "Receta Negativa"}, [%{product_id: ing.id, quantity: "1"}])

      {:ok, lv, _} = live(conn, ~p"/produccion")
      render_click(lv, "select_recipe", %{"id" => to_string(recipe.id)})
      render_click(lv, "update_batches", %{"value" => "-5"})

      # WHEN
      html = render_click(lv, "log_production", %{})

      # THEN
      assert html =~ "La cantidad de lotes debe ser mayor a 0"
    end
  end

  # ---------------------------------------------------------------------------
  # update_batches and preview calculation
  # ---------------------------------------------------------------------------

  describe "update_batches event" do
    test "GIVEN recipe selected WHEN updating batches to 2 THEN preview shows doubled amounts",
         %{conn: conn} do
      # GIVEN
      {conn, _} = staff_conn(conn)
      output = insert_product(%{name: "Salsa Chipotle", stock_quantity: "0.0"})
      ing = insert_product(%{name: "Chipotle", stock_quantity: "400.0"})
      recipe = insert_recipe(
        output,
        %{"name" => "Salsa De Chipotle", "yield_quantity" => "200"},
        [%{product_id: ing.id, quantity: "50"}]
      )

      {:ok, lv, _} = live(conn, ~p"/produccion")
      render_click(lv, "select_recipe", %{"id" => to_string(recipe.id)})

      # WHEN
      html = render_click(lv, "update_batches", %{"value" => "2"})

      # THEN: yield 200 × 2 = 400 shown in preview
      assert html =~ "400"
    end
  end

  # ---------------------------------------------------------------------------
  # notes field
  # ---------------------------------------------------------------------------

  describe "update_notes event" do
    test "GIVEN recipe selected WHEN adding notes THEN notes are reflected in state",
         %{conn: conn} do
      # GIVEN
      {conn, _} = staff_conn(conn)
      output = insert_product(%{name: "Concentrado Cafe", stock_quantity: "0.0"})
      ing = insert_product()
      recipe = insert_recipe(output, %{"name" => "Concentrado De Café"}, [%{product_id: ing.id, quantity: "5"}])

      {:ok, lv, _} = live(conn, ~p"/produccion")
      render_click(lv, "select_recipe", %{"id" => to_string(recipe.id)})

      # WHEN
      html = render_click(lv, "update_notes", %{"value" => "Granos de la cosecha nueva"})

      # THEN: note text is present in the rendered HTML
      assert html =~ "Granos de la cosecha nueva"
    end

    test "GIVEN notes added WHEN logging THEN log is saved with notes",
         %{conn: conn} do
      # GIVEN
      {conn, user} = staff_conn(conn)
      output = insert_product(%{name: "Mermelada Fresa", stock_quantity: "0.0"})
      ing = insert_product(%{name: "Fresas", stock_quantity: "300.0"})
      recipe = insert_recipe(
        output,
        %{"name" => "Mermelada De Fresa"},
        [%{product_id: ing.id, quantity: "100"}]
      )

      {:ok, lv, _} = live(conn, ~p"/produccion")
      render_click(lv, "select_recipe", %{"id" => to_string(recipe.id)})
      render_click(lv, "update_notes", %{"value" => "Lote especial"})
      render_click(lv, "log_production", %{})

      # THEN: log stored with notes
      logs = Production.list_today_logs()
      log = Enum.find(logs, fn l -> l.recipe && l.recipe.name == "Mermelada De Fresa" end)
      assert log
      assert log.notes == "Lote especial"
    end
  end

  # ---------------------------------------------------------------------------
  # Today's log section
  # ---------------------------------------------------------------------------

  describe "today's log section" do
    test "GIVEN production logged today WHEN mounting page THEN log is shown immediately",
         %{conn: conn} do
      # GIVEN
      {conn, user} = staff_conn(conn)
      output = insert_product(%{name: "Té Verde Frío", stock_quantity: "0.0"})
      ing = insert_product(%{name: "Té Verde", stock_quantity: "200.0"})
      recipe = insert_recipe(
        output,
        %{"name" => "Té Verde Frío"},
        [%{product_id: ing.id, quantity: "10"}]
      )
      Production.log_production(recipe.id, "1", user.id, "Lote previo")

      # WHEN: fresh mount
      {:ok, _lv, html} = live(conn, ~p"/produccion")

      # THEN
      assert html =~ "Té Verde Frío"
      assert html =~ "Lote previo"
    end

    test "GIVEN multiple logs today WHEN viewing page THEN all logs are listed",
         %{conn: conn} do
      # GIVEN
      {conn, user} = staff_conn(conn)
      out1 = insert_product(%{name: "Producto A", stock_quantity: "0.0"})
      out2 = insert_product(%{name: "Producto B", stock_quantity: "0.0"})
      ing1 = insert_product(%{name: "Ing A", stock_quantity: "500.0"})
      ing2 = insert_product(%{name: "Ing B", stock_quantity: "500.0"})
      r1 = insert_recipe(out1, %{"name" => "Receta Log A"}, [%{product_id: ing1.id, quantity: "5"}])
      r2 = insert_recipe(out2, %{"name" => "Receta Log B"}, [%{product_id: ing2.id, quantity: "5"}])
      Production.log_production(r1.id, "1", user.id, "")
      Production.log_production(r2.id, "1", user.id, "")

      # WHEN
      {:ok, _lv, html} = live(conn, ~p"/produccion")

      # THEN
      assert html =~ "Receta Log A"
      assert html =~ "Receta Log B"
    end
  end
end
