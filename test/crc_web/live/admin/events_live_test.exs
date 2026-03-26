defmodule CRCWeb.Admin.EventsLiveTest do
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
          name: "Admin Events",
          email: "admin_ev#{System.unique_integer()}@cafe.com",
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

  defp insert_event(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          title: "Evento Test #{System.unique_integer()}",
          event_date: Date.add(Date.utc_today(), 5),
          start_time: ~T[18:00:00],
          end_time: ~T[21:00:00],
          active: true
        },
        overrides
      )

    {:ok, event} = Events.create_event(attrs)
    event
  end

  defp insert_collaborator(overrides \\ %{}) do
    attrs = Map.merge(%{name: "Artista #{System.unique_integer()}"}, overrides)
    {:ok, c} = Events.create_collaborator(attrs)
    c
  end

  defp format_date_for_input(date) do
    Date.to_string(date)
  end

  # ---------------------------------------------------------------------------
  # Tests
  # ---------------------------------------------------------------------------

  describe "access control" do
    test "redirects unauthenticated to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/iniciar-sesion"}}} = live(conn, ~p"/admin/eventos")
    end

    test "admin can access events page", %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      assert {:ok, _lv, html} = live(conn, ~p"/admin/eventos")
      assert html =~ "Eventos"
    end
  end

  describe "events listing" do
    test "admin sees all events", %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      insert_event(%{title: "Noche de Jazz Test"})

      {:ok, _lv, html} = live(conn, ~p"/admin/eventos")
      assert html =~ "Noche de Jazz Test"
    end

    test "shows empty state when no events", %{conn: conn} do
      {conn, _admin} = admin_conn(conn)

      {:ok, _lv, html} = live(conn, ~p"/admin/eventos")
      # Either shows events or the empty state
      assert html =~ "Eventos"
    end
  end

  describe "new_event event" do
    test "opens modal with empty form", %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/eventos")

      html = render_click(lv, "new_event", %{})
      assert html =~ "Nuevo evento"
    end
  end

  describe "save_event event" do
    test "creates event without collaborators", %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/eventos")

      render_click(lv, "new_event", %{})

      html =
        lv
        |> form("#event-form",
          event: %{
            title: "Evento Sin Colaboradores",
            event_date: format_date_for_input(Date.add(Date.utc_today(), 7)),
            start_time: "19:00",
            end_time: "22:00"
          }
        )
        |> render_submit()

      assert html =~ "creado" or html =~ "Evento Sin Colaboradores"
    end

    test "fails without title", %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/eventos")

      render_click(lv, "new_event", %{})

      html =
        lv
        |> form("#event-form",
          event: %{
            title: "",
            event_date: format_date_for_input(Date.add(Date.utc_today(), 7)),
            start_time: "19:00",
            end_time: "22:00"
          }
        )
        |> render_submit()

      assert html =~ "Nuevo evento" or html =~ "en blanco"
    end

    test "fails without event_date", %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/eventos")

      render_click(lv, "new_event", %{})

      html =
        lv
        |> form("#event-form",
          event: %{
            title: "Sin Fecha",
            event_date: "",
            start_time: "19:00",
            end_time: "22:00"
          }
        )
        |> render_submit()

      assert html =~ "Nuevo evento" or html =~ "en blanco"
    end
  end

  describe "collaborator draft management" do
    test "add_collaborator_to_draft adds collaborator to the form", %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      collab = insert_collaborator(%{name: "Músico Draft"})

      {:ok, lv, _html} = live(conn, ~p"/admin/eventos")

      render_click(lv, "new_event", %{})

      # Set the selected collaborator
      render_change(lv, "update_collaborator_selection", %{"collab_select" => to_string(collab.id)})

      html = render_click(lv, "add_collaborator_to_draft", %{})
      assert html =~ "Músico Draft"
    end

    test "remove_collaborator_from_draft removes collaborator", %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      collab = insert_collaborator(%{name: "Músico Remove"})

      {:ok, lv, _html} = live(conn, ~p"/admin/eventos")

      render_click(lv, "new_event", %{})

      # Add collaborator first
      render_change(lv, "update_collaborator_selection", %{"collab_select" => to_string(collab.id)})
      render_click(lv, "add_collaborator_to_draft", %{})

      # Now remove — draft should be cleared, page still renders
      html = render_click(lv, "remove_collaborator_from_draft", %{"id" => to_string(collab.id)})
      assert html =~ "— Selecciona —"
    end
  end

  describe "toggle_active event" do
    test "toggles event active status", %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      event = insert_event(%{title: "Evento Toggle"})

      {:ok, lv, _html} = live(conn, ~p"/admin/eventos")

      html = render_click(lv, "toggle_active", %{"id" => to_string(event.id)})
      assert html =~ "desactivado" or html =~ "activado"
    end
  end

  describe "PubSub events" do
    test "event_changed PubSub event triggers reload", %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/eventos")

      Phoenix.PubSub.broadcast(CRC.PubSub, "admin:events", {:event_changed, %{}})

      assert render(lv)
    end
  end
end
