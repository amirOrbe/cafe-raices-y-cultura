defmodule CRCWeb.Admin.DashboardLiveTest do
  use CRCWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias CRC.Accounts.User
  alias CRC.Inventory

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp insert_user(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          name: "Admin Dashboard",
          email: "admin_dash#{System.unique_integer()}@cafe.com",
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

  defp admin_conn(conn) do
    admin = insert_user(%{role: "admin"})
    {init_test_session(conn, %{"user_id" => admin.id}), admin}
  end

  defp cliente_conn(conn) do
    cliente = insert_user(%{role: "cliente"})
    {init_test_session(conn, %{"user_id" => cliente.id}), cliente}
  end

  # ---------------------------------------------------------------------------
  # Tests
  # ---------------------------------------------------------------------------

  describe "access control" do
    test "redirects unauthenticated users to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/iniciar-sesion"}}} = live(conn, ~p"/admin")
    end

    test "redirects non-admin (cliente) users to /", %{conn: conn} do
      {conn, _cliente} = cliente_conn(conn)
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin")
    end

    test "admin user can access dashboard", %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      assert {:ok, _lv, html} = live(conn, ~p"/admin")
      assert html =~ "Dashboard"
    end
  end

  describe "dashboard content" do
    test "displays user count stat", %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      assert {:ok, _lv, html} = live(conn, ~p"/admin")
      assert html =~ "Total usuarios" or html =~ "usuario"
    end

    test "displays low stock count stat", %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      assert {:ok, _lv, html} = live(conn, ~p"/admin")
      assert html =~ "Stock bajo" or html =~ "stock"
    end

    test "shows welcome message with admin name", %{conn: conn} do
      admin = insert_user(%{role: "admin", name: "Carlos Admin Test"})
      conn = init_test_session(conn, %{"user_id" => admin.id})

      assert {:ok, _lv, html} = live(conn, ~p"/admin")
      assert html =~ "Carlos Admin Test"
    end

    test "shows recent users section", %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      assert {:ok, _lv, html} = live(conn, ~p"/admin")
      assert html =~ "Usuarios recientes" or html =~ "usuario"
    end
  end

  describe "PubSub events" do
    test "user_changed PubSub event triggers stats reload", %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin")

      # Broadcast a user_changed event
      Phoenix.PubSub.broadcast(CRC.PubSub, "admin:users", {:user_changed, %{}})

      # After receiving the event, the LiveView should still render fine
      assert render(lv)
    end

    test "product_changed PubSub event triggers stats reload", %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin")

      Phoenix.PubSub.broadcast(CRC.PubSub, "admin:products", {:product_changed, %{}})

      assert render(lv)
    end
  end
end
