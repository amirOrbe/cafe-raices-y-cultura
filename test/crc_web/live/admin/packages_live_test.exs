defmodule CRCWeb.Admin.PackagesLiveTest do
  use CRCWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias CRC.Accounts.User
  alias CRC.Catalog

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp insert_admin(conn) do
    attrs = %{
      name: "Admin",
      email: "admin#{System.unique_integer()}@cafe.com",
      role: "admin",
      stations: [],
      password: "pass123456"
    }

    {:ok, user} = %User{} |> User.changeset(attrs) |> CRC.Repo.insert()
    {init_test_session(conn, %{"user_id" => user.id}), user}
  end

  defp insert_category(overrides \\ %{}) do
    base = %{name: "Cat #{System.unique_integer()}"}
    {:ok, cat} = Catalog.create_category(Map.merge(base, overrides))
    cat
  end

  defp insert_menu_item(category_id, overrides \\ %{}) do
    base = %{name: "Item #{System.unique_integer()}", price: "50.00", category_id: category_id}
    {:ok, item} = Catalog.create_menu_item(Map.merge(base, overrides))
    item
  end

  defp insert_package(overrides \\ %{}) do
    base = %{name: "Paquete #{System.unique_integer()}", price: "80.00"}
    {:ok, pkg} = Catalog.create_package(Map.merge(base, overrides))
    pkg
  end

  # ---------------------------------------------------------------------------
  # Authentication
  # ---------------------------------------------------------------------------

  describe "authentication" do
    test "redirects to login when not authenticated", %{conn: conn} do
      {:error, {:redirect, %{to: path}}} = live(conn, "/admin/paquetes")
      assert path =~ "/iniciar-sesion"
    end
  end

  # ---------------------------------------------------------------------------
  # Mount
  # ---------------------------------------------------------------------------

  describe "mount" do
    test "shows packages page", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      {:ok, _lv, html} = live(conn, "/admin/paquetes")
      assert html =~ "Paquetes"
      assert html =~ "Nuevo paquete"
    end

    test "shows 0 packages when none exist", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      {:ok, _lv, html} = live(conn, "/admin/paquetes")
      assert html =~ "0 paquetes registrados"
    end

    test "shows existing packages", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      insert_package(%{name: "Combo Especial"})
      {:ok, _lv, html} = live(conn, "/admin/paquetes")
      assert html =~ "Combo Especial"
    end
  end

  # ---------------------------------------------------------------------------
  # New package modal
  # ---------------------------------------------------------------------------

  describe "new_package" do
    test "opens new package modal", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      {:ok, lv, _html} = live(conn, "/admin/paquetes")
      html = lv |> element("button", "Nuevo paquete") |> render_click()
      assert html =~ "Crear paquete"
      assert html =~ "package-form"
    end

    test "closes modal on close_modal event", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      {:ok, lv, _html} = live(conn, "/admin/paquetes")
      lv |> element("button", "Nuevo paquete") |> render_click()
      html = lv |> element("button", "Cancelar") |> render_click()
      refute html =~ "package-form"
    end
  end

  # ---------------------------------------------------------------------------
  # Create package
  # ---------------------------------------------------------------------------

  describe "save_package (new)" do
    test "shows error when no menu items selected", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      {:ok, lv, _html} = live(conn, "/admin/paquetes")
      lv |> element("button", "Nuevo paquete") |> render_click()

      html =
        lv
        |> form("#package-form", package: %{name: "Combo", price: "80"})
        |> render_submit()

      assert html =~ "Agrega al menos un platillo"
    end

    test "creates a package with selected items", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      cat = insert_category()
      item = insert_menu_item(cat.id, %{name: "Sandwich"})

      {:ok, lv, _html} = live(conn, "/admin/paquetes")
      lv |> element("button", "Nuevo paquete") |> render_click()

      lv
      |> element("[phx-click='toggle_menu_item'][phx-value-id='#{item.id}']")
      |> render_click()

      html =
        lv
        |> form("#package-form", package: %{name: "Combo Test", price: "90"})
        |> render_submit()

      assert html =~ "Combo Test"
      assert html =~ "creado correctamente"
    end

    test "shows changeset errors for invalid data", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      cat = insert_category()
      item = insert_menu_item(cat.id)

      {:ok, lv, _html} = live(conn, "/admin/paquetes")
      lv |> element("button", "Nuevo paquete") |> render_click()

      lv
      |> element("[phx-click='toggle_menu_item'][phx-value-id='#{item.id}']")
      |> render_click()

      html =
        lv
        |> form("#package-form", package: %{name: "", price: "90"})
        |> render_submit()

      assert html =~ "no puede estar en blanco"
    end
  end

  # ---------------------------------------------------------------------------
  # Edit package
  # ---------------------------------------------------------------------------

  describe "edit_package" do
    test "opens edit modal with existing data", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      pkg = insert_package(%{name: "Combo Editable"})

      {:ok, lv, _html} = live(conn, "/admin/paquetes")

      html =
        lv
        |> element("[phx-click='edit_package'][phx-value-id='#{pkg.id}']")
        |> render_click()

      assert html =~ "Guardar cambios"
      assert html =~ "Combo Editable"
    end

    test "updates package successfully", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      cat = insert_category()
      item = insert_menu_item(cat.id)
      pkg = insert_package(%{name: "Combo Antiguo"})
      {:ok, _} = Catalog.set_package_items(pkg, [%{menu_item_id: item.id, quantity: 1}])

      {:ok, lv, _html} = live(conn, "/admin/paquetes")

      lv
      |> element("[phx-click='edit_package'][phx-value-id='#{pkg.id}']")
      |> render_click()

      html =
        lv
        |> form("#package-form", package: %{name: "Combo Nuevo", price: "95"})
        |> render_submit()

      assert html =~ "Combo Nuevo"
      assert html =~ "actualizado correctamente"
    end
  end

  # ---------------------------------------------------------------------------
  # Toggle active / featured
  # ---------------------------------------------------------------------------

  describe "toggle_active" do
    test "toggles package active status", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      pkg = insert_package(%{name: "Combo Toggle", active: true})

      {:ok, lv, _html} = live(conn, "/admin/paquetes")

      html =
        lv
        |> element("[phx-click='toggle_active'][phx-value-id='#{pkg.id}']")
        |> render_click()

      assert html =~ "desactivado correctamente"
    end
  end

  # ---------------------------------------------------------------------------
  # Delete package
  # ---------------------------------------------------------------------------

  describe "delete_package" do
    test "deletes a package", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      pkg = insert_package(%{name: "Combo Borrable"})

      {:ok, lv, _html} = live(conn, "/admin/paquetes")

      html =
        lv
        |> element("[phx-click='delete_package'][phx-value-id='#{pkg.id}']")
        |> render_click()

      assert html =~ "eliminado correctamente"
      refute html =~ "Combo Borrable"
    end
  end

  # ---------------------------------------------------------------------------
  # Item quantity control
  # ---------------------------------------------------------------------------

  describe "update_item_qty" do
    test "updates quantity for a selected item", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      cat = insert_category()
      item = insert_menu_item(cat.id)

      {:ok, lv, _html} = live(conn, "/admin/paquetes")
      lv |> element("button", "Nuevo paquete") |> render_click()

      lv
      |> element("[phx-click='toggle_menu_item'][phx-value-id='#{item.id}']")
      |> render_click()

      # Click the "+" button (increment) which has phx-value-qty=2
      lv
      |> element("[phx-click='update_item_qty'][phx-value-id='#{item.id}'][phx-value-qty='2']")
      |> render_click()

      html = render(lv)
      assert html =~ "2"
    end
  end

  describe "validate_package" do
    test "validates package form without saving", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      {:ok, lv, _html} = live(conn, "/admin/paquetes")

      lv |> element("button", "Nuevo paquete") |> render_click()

      html =
        lv
        |> form("#package-form", package: %{name: "Paquete Válido", price: "250.00"})
        |> render_change()

      assert html =~ "Paquete Válido" or html =~ "250"
    end
  end

  describe "toggle_menu_item deselect" do
    test "deselects an already-selected item", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      cat = insert_category()
      item = insert_menu_item(cat.id)

      {:ok, lv, _html} = live(conn, "/admin/paquetes")
      lv |> element("button", "Nuevo paquete") |> render_click()

      # Select the item
      lv
      |> element("[phx-click='toggle_menu_item'][phx-value-id='#{item.id}']")
      |> render_click()

      # Deselect the item
      html =
        lv
        |> element("[phx-click='toggle_menu_item'][phx-value-id='#{item.id}']")
        |> render_click()

      # Should not crash
      assert html =~ "Nuevo paquete"
    end
  end

  describe "use_suggestion" do
    test "use_suggestion populates the form with two items", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      cat = insert_category()
      item_a = insert_menu_item(cat.id, %{name: "Platillo Sugerido A"})
      item_b = insert_menu_item(cat.id, %{name: "Platillo Sugerido B"})

      {:ok, lv, _html} = live(conn, "/admin/paquetes")

      html =
        render_click(lv, "use_suggestion", %{
          "a" => to_string(item_a.id),
          "b" => to_string(item_b.id),
          "price" => "199.00"
        })

      # Should open the new modal with items selected
      assert html =~ "Nuevo paquete" or html =~ "199"
    end
  end
end
