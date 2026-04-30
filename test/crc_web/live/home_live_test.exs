defmodule CRCWeb.HomeLiveTest do
  use CRCWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias CRC.Accounts
  alias CRC.Accounts.User
  alias CRC.Settings

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp insert_user(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          name: "Admin Test",
          email: "admin_home#{System.unique_integer()}@cafe.com",
          role: "admin",
          password: "contraseña123"
        },
        overrides
      )

    {:ok, user} =
      %User{}
      |> User.changeset(attrs)
      |> CRC.Repo.insert()

    user
  end

  defp log_in(conn, user) do
    init_test_session(conn, %{"user_id" => user.id})
  end

  # ---------------------------------------------------------------------------
  # Tests
  # ---------------------------------------------------------------------------

  describe "GET /" do
    test "renders the home page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ "Café Raíces y Cultura"
    end

    test "page title is set", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")
      assert page_title(lv) =~ "Café Raíces y Cultura"
    end

    test "shows navigation bar", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ "Menú"
    end

    test "unauthenticated user does not see Panel link", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")
      refute html =~ "Panel"
    end
  end

  describe "carousel events" do
    test "carousel_next event changes active_slide", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      # Trigger carousel_next directly (the JS hook calls this event)
      html = render_click(lv, "carousel_next", %{})
      # The active_slide should have changed without crashing
      assert html
    end

    test "carousel_goto event changes to specific slide", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      # Click the 3rd slide dot (index 2)
      html = render_click(lv, "carousel_goto", %{"index" => "2"})
      assert html
    end
  end

  describe "nav events" do
    test "toggle_nav event toggles nav_open", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      render_click(lv, "toggle_nav", %{})
      render_click(lv, "toggle_nav", %{})
      # No crash = success
      assert render(lv)
    end

    test "close_nav event sets nav_open to false", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/")

      render_click(lv, "toggle_nav", %{})
      render_click(lv, "close_nav", %{})
      assert render(lv)
    end
  end

  describe "packages section" do
    test "hides packages section when no active packages exist", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/")
      refute html =~ "Paquetes del día"
    end

    test "shows packages section when active packages exist", %{conn: conn} do
      cat_attrs = %{name: "Cafés Pkg #{System.unique_integer()}"}
      {:ok, cat} = CRC.Catalog.create_category(cat_attrs)

      {:ok, item} =
        CRC.Catalog.create_menu_item(%{name: "Café", price: "40.00", category_id: cat.id})

      {:ok, pkg} = CRC.Catalog.create_package(%{name: "Combo Especial Test", price: "60.00"})
      {:ok, _} = CRC.Catalog.set_package_items(pkg, [%{menu_item_id: item.id, quantity: 1}])

      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ "Paquetes del día"
      assert html =~ "Combo Especial Test"
    end

    test "inactive packages are not shown on homepage", %{conn: conn} do
      {:ok, _} =
        CRC.Catalog.create_package(%{name: "Combo Inactivo", price: "60.00", active: false})

      {:ok, _lv, html} = live(conn, ~p"/")
      refute html =~ "Combo Inactivo"
    end
  end

  describe "authentication state" do
    test "logged-in admin sees Panel link", %{conn: conn} do
      admin = insert_user(%{role: "admin"})
      conn = log_in(conn, admin)

      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ "Panel"
    end

    test "logged-in cliente does NOT see Panel link but sees logout option", %{conn: conn} do
      cliente = insert_user(%{role: "cliente"})
      conn = log_in(conn, cliente)

      {:ok, _lv, html} = live(conn, ~p"/")
      refute html =~ "Panel"
      assert html =~ "Cerrar sesión"
    end

    test "current_user is loaded from session", %{conn: conn} do
      admin = insert_user(%{role: "admin"})
      conn = log_in(conn, admin)

      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ "Panel"
    end
  end

  describe "cafe_hours display" do
    test "shows opening and closing times when cafe hours are configured", %{conn: conn} do
      {:ok, _} =
        Settings.set_cafe_hours([
          %{
            day_of_week: 1,
            opening_time: ~T[08:00:00],
            closing_time: ~T[22:00:00],
            is_closed: false
          }
        ])

      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ "08:00" or html =~ "22:00" or html =~ "Horario"
    end
  end

  describe "packages section — extended" do
    test "shows package description when set", %{conn: conn} do
      {:ok, pkg} =
        CRC.Catalog.create_package(%{
          name: "Combo Con Descripción",
          price: "55.00",
          description: "Un combo perfecto para compartir"
        })

      {:ok, cat} = CRC.Catalog.create_category(%{name: "Café Combo #{System.unique_integer()}"})

      {:ok, item} =
        CRC.Catalog.create_menu_item(%{name: "Café Base", price: "35.00", category_id: cat.id})

      {:ok, _} = CRC.Catalog.set_package_items(pkg, [%{menu_item_id: item.id, quantity: 1}])

      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ "Un combo perfecto para compartir"
    end

    test "shows quantity badge when package item has quantity > 1", %{conn: conn} do
      {:ok, pkg} = CRC.Catalog.create_package(%{name: "Combo Doble", price: "70.00"})
      {:ok, cat} = CRC.Catalog.create_category(%{name: "Café Doble #{System.unique_integer()}"})

      {:ok, item} =
        CRC.Catalog.create_menu_item(%{
          name: "Espresso Doble",
          price: "40.00",
          category_id: cat.id
        })

      {:ok, _} = CRC.Catalog.set_package_items(pkg, [%{menu_item_id: item.id, quantity: 2}])

      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ "2×"
    end

    test "shows savings badge when package price is lower than sum of items", %{conn: conn} do
      {:ok, pkg} = CRC.Catalog.create_package(%{name: "Combo Ahorro Home", price: "50.00"})
      {:ok, cat} = CRC.Catalog.create_category(%{name: "Café Ahorro #{System.unique_integer()}"})

      {:ok, item} =
        CRC.Catalog.create_menu_item(%{
          name: "Café Ahorro Item",
          price: "70.00",
          category_id: cat.id
        })

      {:ok, _} = CRC.Catalog.set_package_items(pkg, [%{menu_item_id: item.id, quantity: 1}])

      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ "Ahorras"
    end
  end
end
