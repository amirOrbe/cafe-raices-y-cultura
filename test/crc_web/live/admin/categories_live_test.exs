defmodule CRCWeb.Admin.CategoriesLiveTest do
  use CRCWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias CRC.Accounts.User
  alias CRC.Catalog

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

  describe "authentication" do
    test "redirects to login when not authenticated", %{conn: conn} do
      {:error, {:redirect, %{to: path}}} = live(conn, "/admin/platillos/categorias")
      assert path =~ "/iniciar-sesion"
    end
  end

  describe "mount" do
    test "shows categories page", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      {:ok, _lv, html} = live(conn, "/admin/platillos/categorias")
      assert html =~ "Categorías de platillos"
    end

    test "shows empty state when no categories", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      {:ok, _lv, html} = live(conn, "/admin/platillos/categorias")
      assert html =~ "No hay categorías registradas"
    end

    test "shows category list when categories exist", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      cat = insert_category(%{name: "Cafés Especiales"})
      {:ok, _lv, html} = live(conn, "/admin/platillos/categorias")
      assert html =~ cat.name
    end
  end

  describe "new_category" do
    test "opens modal for new category", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      {:ok, lv, _} = live(conn, "/admin/platillos/categorias")

      html = render_click(lv, "new_category", %{})
      assert html =~ "Nueva categoría"
    end
  end

  describe "save_category (create)" do
    test "creates category with valid params", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      {:ok, lv, _} = live(conn, "/admin/platillos/categorias")
      render_click(lv, "new_category", %{})

      html =
        form(lv, "#category-form")
        |> render_submit(%{category: %{name: "Pasteles"}})

      assert html =~ "Pasteles"
      assert html =~ "creada correctamente"
    end

    test "shows error with blank name", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      {:ok, lv, _} = live(conn, "/admin/platillos/categorias")
      render_click(lv, "new_category", %{})

      html =
        form(lv, "#category-form")
        |> render_submit(%{category: %{name: ""}})

      assert html =~ "Nueva categoría"
    end
  end

  describe "edit_category" do
    test "opens edit modal", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      cat = insert_category(%{name: "Editable"})
      {:ok, lv, _} = live(conn, "/admin/platillos/categorias")

      html = render_click(lv, "edit_category", %{"id" => to_string(cat.id)})
      assert html =~ "Editar categoría"
    end

    test "updates category with valid params", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      cat = insert_category(%{name: "Antes"})
      {:ok, lv, _} = live(conn, "/admin/platillos/categorias")
      render_click(lv, "edit_category", %{"id" => to_string(cat.id)})

      html =
        form(lv, "#category-form")
        |> render_submit(%{category: %{name: "Después"}})

      assert html =~ "Después"
      assert html =~ "actualizada correctamente"
    end
  end

  describe "close_modal" do
    test "closes modal", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      {:ok, lv, _} = live(conn, "/admin/platillos/categorias")
      render_click(lv, "new_category", %{})

      html = render_click(lv, "close_modal", %{})
      refute html =~ "category-modal"
    end
  end

  describe "toggle_active" do
    test "deactivates an active category", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      cat = insert_category(%{name: "Activa Toggle", active: true})
      {:ok, lv, _} = live(conn, "/admin/platillos/categorias")

      html = render_click(lv, "toggle_active", %{"id" => to_string(cat.id)})
      assert html =~ "desactivada correctamente"
    end

    test "activates an inactive category", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      cat = insert_category(%{name: "Inactiva Toggle", active: false})
      {:ok, lv, _} = live(conn, "/admin/platillos/categorias")

      html = render_click(lv, "toggle_active", %{"id" => to_string(cat.id)})
      assert html =~ "activada correctamente"
    end
  end

  describe "delete_category" do
    test "deletes a category", %{conn: conn} do
      {conn, _} = insert_admin(conn)
      cat = insert_category(%{name: "Para Borrar"})
      {:ok, lv, _} = live(conn, "/admin/platillos/categorias")

      html = render_click(lv, "delete_category", %{"id" => to_string(cat.id)})
      refute html =~ "Para Borrar"
      assert html =~ "eliminada correctamente"
    end
  end
end
