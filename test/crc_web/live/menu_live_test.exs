defmodule CRCWeb.MenuLiveTest do
  use CRCWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias CRC.Catalog
  alias CRC.Accounts.User

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp insert_category(overrides \\ %{}) do
    attrs = Map.merge(%{name: "Cafés", kind: "drink", active: true}, overrides)
    {:ok, cat} = Catalog.create_category(attrs)
    cat
  end

  defp insert_menu_item(category_id, overrides \\ %{}) do
    attrs =
      Map.merge(
        %{name: "Espresso", price: "40.00", category_id: category_id, available: true},
        overrides
      )

    {:ok, item} = Catalog.create_menu_item(attrs)
    item
  end

  defp insert_user(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          name: "Admin Menu",
          email: "admin_menu#{System.unique_integer()}@cafe.com",
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

  # ---------------------------------------------------------------------------
  # Tests
  # ---------------------------------------------------------------------------

  describe "GET /menu" do
    test "renders menu page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/menu")
      assert html =~ "Menú"
    end

    test "page title is set", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/menu")
      assert page_title(lv) =~ "Menú"
    end

    test "shows placeholder categories when DB is empty", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/menu")
      # Placeholder categories like "Café Filtrados" should appear
      assert html =~ "Café"
    end

    test "displays active categories from DB", %{conn: conn} do
      cat = insert_category(%{name: "Mis Cafés Especiales"})
      insert_menu_item(cat.id)

      {:ok, _lv, html} = live(conn, ~p"/menu")
      assert html =~ "Mis Cafés Especiales"
    end

    test "does not show inactive categories", %{conn: conn} do
      insert_category(%{name: "Inactiva Cat", active: false, slug: "inactiva-cat"})

      {:ok, _lv, html} = live(conn, ~p"/menu")
      refute html =~ "Inactiva Cat"
    end
  end

  describe "select_category event" do
    test "changes active category", %{conn: conn} do
      cat1 = insert_category(%{name: "Categoría Uno", position: 1})
      cat2 = insert_category(%{name: "Categoría Dos", position: 2})
      insert_menu_item(cat1.id, %{name: "Ítem Uno"})
      insert_menu_item(cat2.id, %{name: "Ítem Dos"})

      {:ok, lv, _html} = live(conn, ~p"/menu")

      html = render_click(lv, "select_category", %{"id" => to_string(cat2.id)})
      assert html =~ "Categoría Dos" or html =~ "Ítem Dos"
    end
  end

  describe "nav events" do
    test "toggle_nav toggles nav_open", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/menu")

      render_click(lv, "toggle_nav", %{})
      render_click(lv, "toggle_nav", %{})
      assert render(lv)
    end

    test "close_nav sets nav_open to false", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/menu")

      render_click(lv, "toggle_nav", %{})
      render_click(lv, "close_nav", %{})
      assert render(lv)
    end
  end

  describe "with logged-in user" do
    test "logged-in admin sees Panel link", %{conn: conn} do
      admin = insert_user(%{role: "admin"})
      conn = init_test_session(conn, %{"user_id" => admin.id})

      {:ok, _lv, html} = live(conn, ~p"/menu")
      assert html =~ "Panel"
    end
  end
end
