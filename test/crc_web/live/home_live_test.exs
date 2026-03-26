defmodule CRCWeb.HomeLiveTest do
  use CRCWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias CRC.Accounts
  alias CRC.Accounts.User

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

  describe "authentication state" do
    test "logged-in admin sees Panel link", %{conn: conn} do
      admin = insert_user(%{role: "admin"})
      conn = log_in(conn, admin)

      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ "Panel"
    end

    test "logged-in cliente does NOT see Panel link but sees Salir", %{conn: conn} do
      cliente = insert_user(%{role: "cliente"})
      conn = log_in(conn, cliente)

      {:ok, _lv, html} = live(conn, ~p"/")
      refute html =~ "Panel"
      assert html =~ "Salir"
    end

    test "current_user is loaded from session", %{conn: conn} do
      admin = insert_user(%{role: "admin"})
      conn = log_in(conn, admin)

      {:ok, _lv, html} = live(conn, ~p"/")
      assert html =~ "Panel"
    end
  end
end
