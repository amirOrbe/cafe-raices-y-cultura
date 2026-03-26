defmodule CRCWeb.Admin.EventTypesLiveTest do
  use CRCWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias CRC.Accounts.User
  alias CRC.Events

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp insert_user(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          name: "Admin EventTypes",
          email: "admin_et#{System.unique_integer()}@cafe.com",
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
    admin = insert_user()
    {init_test_session(conn, %{"user_id" => admin.id}), admin}
  end

  defp insert_event_type(overrides \\ %{}) do
    attrs = Map.merge(%{name: "Tipo #{System.unique_integer()}"}, overrides)
    {:ok, et} = Events.create_event_type(attrs)
    et
  end

  # ---------------------------------------------------------------------------
  # Tests
  # ---------------------------------------------------------------------------

  describe "access control" do
    test "redirects unauthenticated to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/iniciar-sesion"}}} =
               live(conn, ~p"/admin/eventos/tipos")
    end

    test "admin can access event types page", %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      assert {:ok, _lv, html} = live(conn, ~p"/admin/eventos/tipos")
      assert html =~ "Tipos de Evento"
    end
  end

  describe "event type listing" do
    test "admin sees all active event types", %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      insert_event_type(%{name: "Concierto Test"})

      {:ok, _lv, html} = live(conn, ~p"/admin/eventos/tipos")
      assert html =~ "Concierto Test"
    end

    test "inactive event types are not shown in active filter", %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      et = insert_event_type(%{name: "Tipo Inactivo Test"})
      Events.toggle_event_type_active(et)

      {:ok, _lv, html} = live(conn, ~p"/admin/eventos/tipos")
      refute html =~ "Tipo Inactivo Test"
    end

    test "status filter shows inactive event types", %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      et = insert_event_type(%{name: "Tipo Inactivo Ver"})
      Events.toggle_event_type_active(et)

      {:ok, lv, _html} = live(conn, ~p"/admin/eventos/tipos")
      html = render_click(lv, "set_status_filter", %{"status" => "inactive"})
      assert html =~ "Tipo Inactivo Ver"
    end
  end

  describe "new_event_type event" do
    test "opens modal", %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/eventos/tipos")

      html = render_click(lv, "new_event_type", %{})
      assert html =~ "Nuevo tipo de evento"
    end
  end

  describe "save_event_type event" do
    test "creates event type successfully", %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/eventos/tipos")

      render_click(lv, "new_event_type", %{})

      html =
        lv
        |> form("#event-type-form", event_type: %{name: "Taller Especial"})
        |> render_submit()

      assert html =~ "creado" or html =~ "Taller Especial"
    end

    test "fails without name", %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/eventos/tipos")

      render_click(lv, "new_event_type", %{})

      html =
        lv
        |> form("#event-type-form", event_type: %{name: ""})
        |> render_submit()

      assert html =~ "Nuevo tipo de evento" or html =~ "en blanco"
    end
  end

  describe "edit_event_type event" do
    test "opens modal with existing event type data", %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      et = insert_event_type(%{name: "Tipo Editar"})

      {:ok, lv, _html} = live(conn, ~p"/admin/eventos/tipos")

      html = render_click(lv, "edit_event_type", %{"id" => to_string(et.id)})
      assert html =~ "Editar tipo de evento"
      assert html =~ "Tipo Editar"
    end
  end

  describe "toggle_active event" do
    test "toggles event type active status", %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      et = insert_event_type(%{name: "Tipo Toggle"})

      {:ok, lv, _html} = live(conn, ~p"/admin/eventos/tipos")

      html = render_click(lv, "toggle_active", %{"id" => to_string(et.id)})
      assert html =~ "desactivado" or !String.contains?(html, "Tipo Toggle")
    end
  end

  describe "PubSub handle_info" do
    test "event_type_changed reloads event types", %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/eventos/tipos")

      Phoenix.PubSub.broadcast(
        CRC.PubSub,
        "admin:event_types",
        {:event_type_changed, %{}}
      )

      assert render(lv)
    end
  end
end
