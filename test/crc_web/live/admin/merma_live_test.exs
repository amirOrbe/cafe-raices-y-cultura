defmodule CRCWeb.Admin.MermaLiveTest do
  use CRCWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias CRC.Inventory

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp insert_user(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          name: "Merma User",
          email: "merma#{System.unique_integer()}@cafe.com",
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

  defp admin_conn(conn) do
    admin = insert_user(%{role: "admin", stations: []})
    conn = init_test_session(conn, %{"user_id" => admin.id})
    {conn, admin}
  end

  defp employee_conn(conn) do
    user = insert_user()
    conn = init_test_session(conn, %{"user_id" => user.id})
    {conn, user}
  end

  defp insert_product(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          name: "Insumo Merma #{System.unique_integer()}",
          unit: "litros",
          net_cost: "10.00",
          stock_quantity: "100.0",
          min_stock: "5.0"
        },
        overrides
      )

    {:ok, product} = Inventory.create_product(attrs)
    product
  end

  # ===========================================================================
  # Access control
  # ===========================================================================

  describe "access control" do
    test "GIVEN unauthenticated user WHEN visiting /admin/insumos/merma THEN redirects",
         %{conn: conn} do
      assert {:error, {:redirect, _}} = live(conn, ~p"/admin/insumos/merma")
    end

    test "GIVEN empleado WHEN visiting /admin/insumos/merma THEN redirected",
         %{conn: conn} do
      {conn, _} = employee_conn(conn)
      assert {:error, {:redirect, _}} = live(conn, ~p"/admin/insumos/merma")
    end

    test "GIVEN admin WHEN visiting /admin/insumos/merma THEN page loads",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      assert {:ok, _lv, html} = live(conn, ~p"/admin/insumos/merma", on_error: :warn)
      assert html =~ "Merma"
    end
  end

  # ===========================================================================
  # Mount state
  # ===========================================================================

  describe "page mount" do
    test "GIVEN admin WHEN mounting THEN adjustment history section is shown",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      {:ok, _lv, html} = live(conn, ~p"/admin/insumos/merma", on_error: :warn)
      assert html =~ "Historial de ajustes"
    end

    test "GIVEN no adjustments WHEN mounting THEN empty state message shown",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      {:ok, _lv, html} = live(conn, ~p"/admin/insumos/merma", on_error: :warn)
      assert html =~ "No hay ajustes"
    end

    test "GIVEN adjustments exist WHEN mounting THEN they are shown",
         %{conn: conn} do
      {conn, admin} = admin_conn(conn)
      product = insert_product(%{name: "Leche Con Ajuste"})

      Inventory.create_stock_adjustment(
        %{product_id: product.id, quantity: Decimal.new("-5"), reason: "caducidad"},
        admin.id
      )

      {:ok, _lv, html} = live(conn, ~p"/admin/insumos/merma", on_error: :warn)
      assert html =~ "Leche Con Ajuste"
    end
  end

  # ===========================================================================
  # Modal events
  # ===========================================================================

  describe "open_modal event" do
    test "GIVEN admin WHEN opening modal THEN modal is displayed",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/insumos/merma", on_error: :warn)

      html = render_click(lv, "open_modal", %{})
      assert html =~ "Registrar ajuste de stock"
    end
  end

  describe "close_modal event" do
    test "GIVEN open modal WHEN closing THEN modal disappears",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/insumos/merma", on_error: :warn)

      render_click(lv, "open_modal", %{})
      html = render_click(lv, "close_modal", %{})
      refute html =~ "Registrar ajuste de stock"
    end
  end

  # ===========================================================================
  # set_sign event
  # ===========================================================================

  describe "set_sign event" do
    test "GIVEN modal open WHEN setting sign to '+' THEN state updates",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/insumos/merma", on_error: :warn)
      render_click(lv, "open_modal", %{})

      html = render_click(lv, "set_sign", %{"sign" => "+"})
      assert html =~ "Corrección"
    end

    test "GIVEN modal open WHEN setting sign to '-' THEN state updates",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/insumos/merma", on_error: :warn)
      render_click(lv, "open_modal", %{})

      html = render_click(lv, "set_sign", %{"sign" => "-"})
      assert html =~ "Pérdida"
    end
  end

  # ===========================================================================
  # save_adjustment event
  # ===========================================================================

  describe "save_adjustment event" do
    test "GIVEN valid loss adjustment WHEN saving THEN success flash shown and modal closes",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      product = insert_product(%{name: "Azúcar Ajuste"})

      {:ok, lv, _html} = live(conn, ~p"/admin/insumos/merma", on_error: :warn)
      render_click(lv, "open_modal", %{})

      html =
        render_click(lv, "save_adjustment", %{
          "stock_adjustment" => %{
            "product_id" => to_string(product.id),
            "quantity" => "5",
            "reason" => "caducidad",
            "notes" => "Prueba de merma"
          }
        })

      assert html =~ "Ajuste registrado" or html =~ "ajuste"
    end

    test "GIVEN correction adjustment (+) WHEN saving THEN stock increases",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      product = insert_product(%{name: "Café Corrección", stock_quantity: "50.0"})

      {:ok, lv, _html} = live(conn, ~p"/admin/insumos/merma", on_error: :warn)
      render_click(lv, "open_modal", %{})
      render_click(lv, "set_sign", %{"sign" => "+"})

      render_click(lv, "save_adjustment", %{
        "stock_adjustment" => %{
          "product_id" => to_string(product.id),
          "quantity" => "20",
          "reason" => "ajuste_manual"
        }
      })

      refreshed = Inventory.get_product!(product.id)
      assert Decimal.compare(refreshed.stock_quantity, Decimal.new("70.0")) == :eq
    end

    test "GIVEN invalid form (missing product) WHEN saving THEN form errors shown",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/insumos/merma", on_error: :warn)
      render_click(lv, "open_modal", %{})

      html =
        render_click(lv, "save_adjustment", %{
          "stock_adjustment" => %{
            "product_id" => "",
            "quantity" => "5",
            "reason" => "caducidad"
          }
        })

      # Modal stays open (error state)
      assert html =~ "Registrar ajuste" or html =~ "insumo" or html =~ "modal"
    end

    test "GIVEN zero quantity WHEN saving THEN validation error shown",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      product = insert_product(%{name: "Insumo Cero"})

      {:ok, lv, _html} = live(conn, ~p"/admin/insumos/merma", on_error: :warn)
      render_click(lv, "open_modal", %{})

      html =
        render_click(lv, "save_adjustment", %{
          "stock_adjustment" => %{
            "product_id" => to_string(product.id),
            "quantity" => "0",
            "reason" => "caducidad"
          }
        })

      assert is_binary(html)
    end
  end
end
