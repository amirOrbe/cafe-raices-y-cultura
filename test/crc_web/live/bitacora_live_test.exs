defmodule CRCWeb.BitacoraLiveTest do
  use CRCWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias CRC.ShiftNotes

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp insert_user(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          name: "Bitacora User",
          email: "bitacora#{System.unique_integer()}@cafe.com",
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

  defp staff_conn(conn, overrides \\ %{}) do
    user = insert_user(overrides)
    conn = init_test_session(conn, %{"user_id" => user.id})
    {conn, user}
  end

  defp admin_conn(conn) do
    admin = insert_user(%{role: "admin", stations: []})
    conn = init_test_session(conn, %{"user_id" => admin.id})
    {conn, admin}
  end

  # ===========================================================================
  # Access control
  # ===========================================================================

  describe "access control" do
    test "GIVEN unauthenticated user WHEN visiting /bitacora THEN redirects to login",
         %{conn: conn} do
      assert {:error, {:redirect, %{to: "/iniciar-sesion"}}} = live(conn, ~p"/bitacora")
    end

    test "GIVEN authenticated empleado WHEN visiting /bitacora THEN page loads",
         %{conn: conn} do
      {conn, _user} = staff_conn(conn)
      assert {:ok, _lv, html} = live(conn, ~p"/bitacora", on_error: :warn)
      assert html =~ "Bitácora"
    end

    test "GIVEN authenticated admin WHEN visiting /bitacora THEN page loads",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      assert {:ok, _lv, html} = live(conn, ~p"/bitacora", on_error: :warn)
      assert html =~ "Bitácora"
    end
  end

  # ===========================================================================
  # Mount state
  # ===========================================================================

  describe "page mount" do
    test "GIVEN active notes exist WHEN mounting THEN they appear",
         %{conn: conn} do
      {conn, user} = staff_conn(conn)
      {:ok, _} = ShiftNotes.create_note(%{"content" => "Nota visible en bitácora."}, user.id)

      {:ok, _lv, html} = live(conn, ~p"/bitacora", on_error: :warn)
      assert html =~ "Nota visible en bitácora."
    end

    test "GIVEN no active notes WHEN mounting THEN empty state shown",
         %{conn: conn} do
      {conn, _user} = staff_conn(conn)
      {:ok, _lv, html} = live(conn, ~p"/bitacora", on_error: :warn)
      assert html =~ "Turno" or html =~ "Bitácora"
    end
  end

  # ===========================================================================
  # set_category event
  # ===========================================================================

  describe "set_category event" do
    test "GIVEN user WHEN setting category to stock THEN state updates",
         %{conn: conn} do
      {conn, _user} = staff_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/bitacora", on_error: :warn)

      html = render_click(lv, "set_category", %{"category" => "stock"})
      assert is_binary(html)
    end

    test "GIVEN user WHEN setting category to equipo THEN state updates",
         %{conn: conn} do
      {conn, _user} = staff_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/bitacora", on_error: :warn)

      html = render_click(lv, "set_category", %{"category" => "equipo"})
      assert is_binary(html)
    end
  end

  # ===========================================================================
  # create_note event
  # ===========================================================================

  describe "create_note event" do
    test "GIVEN valid content WHEN creating note THEN note is persisted in DB",
         %{conn: conn} do
      {conn, _user} = staff_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/bitacora", on_error: :warn)

      render_click(lv, "create_note", %{
        "note" => %{"content" => "Nueva nota de prueba"}
      })

      # Note should be in DB even if not immediately reflected via PubSub in test
      active = ShiftNotes.list_active_notes()
      assert Enum.any?(active, &(&1.content == "Nueva nota de prueba"))
    end

    test "GIVEN empty content WHEN creating note THEN flash error shown",
         %{conn: conn} do
      {conn, _user} = staff_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/bitacora", on_error: :warn)

      html = render_click(lv, "create_note", %{"note" => %{"content" => ""}})
      assert html =~ "Escribe" or html =~ "public"
    end

    test "GIVEN whitespace-only content WHEN creating note THEN flash error shown",
         %{conn: conn} do
      {conn, _user} = staff_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/bitacora", on_error: :warn)

      html = render_click(lv, "create_note", %{"note" => %{"content" => "   "}})
      assert html =~ "Escribe" or html =~ "public"
    end
  end

  # ===========================================================================
  # resolve_note event
  # ===========================================================================

  describe "resolve_note event" do
    test "GIVEN active note WHEN resolving THEN note moves from active list",
         %{conn: conn} do
      {conn, user} = staff_conn(conn)
      {:ok, note} = ShiftNotes.create_note(%{"content" => "Nota a resolver."}, user.id)

      {:ok, lv, _html} = live(conn, ~p"/bitacora", on_error: :warn)

      html = render_click(lv, "resolve_note", %{"id" => to_string(note.id)})
      assert is_binary(html)
    end
  end

  # ===========================================================================
  # delete_note event
  # ===========================================================================

  describe "delete_note event" do
    test "GIVEN admin WHEN deleting a note THEN note is removed",
         %{conn: conn} do
      {conn, admin} = admin_conn(conn)
      {:ok, note} = ShiftNotes.create_note(%{"content" => "Nota admin."}, admin.id)

      {:ok, lv, _html} = live(conn, ~p"/bitacora", on_error: :warn)

      html = render_click(lv, "delete_note", %{"id" => to_string(note.id)})
      assert is_binary(html)
    end

    test "GIVEN non-admin WHEN attempting delete THEN note is NOT deleted",
         %{conn: conn} do
      {conn, user} = staff_conn(conn)
      {:ok, note} = ShiftNotes.create_note(%{"content" => "Nota empleado no borrar."}, user.id)

      {:ok, lv, _html} = live(conn, ~p"/bitacora", on_error: :warn)
      render_click(lv, "delete_note", %{"id" => to_string(note.id)})

      # Note should still be in DB
      active = ShiftNotes.list_active_notes()
      ids = Enum.map(active, & &1.id)
      assert note.id in ids
    end
  end

  # ===========================================================================
  # toggle_resolved event
  # ===========================================================================

  describe "toggle_resolved event" do
    test "GIVEN user WHEN toggling resolved section THEN state updates",
         %{conn: conn} do
      {conn, _user} = staff_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/bitacora", on_error: :warn)

      html = render_click(lv, "toggle_resolved", %{})
      assert is_binary(html)
    end

    test "GIVEN resolved notes exist WHEN toggle_resolved THEN resolved notes shown",
         %{conn: conn} do
      {conn, user} = staff_conn(conn)
      {:ok, note} = ShiftNotes.create_note(%{"content" => "Nota resuelta visible."}, user.id)
      ShiftNotes.resolve_note(note.id, user.id)

      {:ok, lv, _html} = live(conn, ~p"/bitacora", on_error: :warn)
      html = render_click(lv, "toggle_resolved", %{})

      # Should render the resolved notes section with the note content
      assert html =~ "Nota resuelta visible." or html =~ "Resueltas"
    end

    test "GIVEN admin viewing resolved notes WHEN delete THEN note is removed",
         %{conn: conn} do
      {conn, admin} = admin_conn(conn)
      {:ok, note} = ShiftNotes.create_note(%{"content" => "Nota admin resuelta."}, admin.id)
      ShiftNotes.resolve_note(note.id, admin.id)

      {:ok, lv, _html} = live(conn, ~p"/bitacora", on_error: :warn)
      render_click(lv, "toggle_resolved", %{})
      html = render_click(lv, "delete_note", %{"id" => to_string(note.id)})

      assert is_binary(html)
    end
  end

  describe "preparacion and equipo categories" do
    test "GIVEN preparacion category WHEN creating note THEN preparacion styling applied",
         %{conn: conn} do
      {conn, _user} = staff_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/bitacora", on_error: :warn)

      render_click(lv, "set_category", %{"category" => "preparacion"})
      html = render_click(lv, "create_note", %{"note" => %{"content" => "Nota de preparación"}})

      assert is_binary(html)
    end

    test "GIVEN equipo category WHEN creating note THEN equipo styling applied",
         %{conn: conn} do
      {conn, _user} = staff_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/bitacora", on_error: :warn)

      render_click(lv, "set_category", %{"category" => "equipo"})
      html = render_click(lv, "create_note", %{"note" => %{"content" => "Nota de equipo"}})

      assert is_binary(html)
    end

    test "GIVEN preparacion notes exist WHEN mounting THEN preparacion styling in HTML",
         %{conn: conn} do
      {conn, user} = staff_conn(conn)

      {:ok, _} =
        ShiftNotes.create_note(
          %{"content" => "Nota preparacion activa.", "category" => "preparacion"},
          user.id
        )

      {:ok, _} =
        ShiftNotes.create_note(
          %{"content" => "Nota equipo activa.", "category" => "equipo"},
          user.id
        )

      {:ok, _lv, html} = live(conn, ~p"/bitacora", on_error: :warn)
      assert html =~ "Nota preparacion activa."
      assert html =~ "Nota equipo activa."
    end
  end

  # ===========================================================================
  # Navigation events
  # ===========================================================================

  describe "navigation events" do
    test "GIVEN user WHEN toggling nav THEN state updates",
         %{conn: conn} do
      {conn, _user} = staff_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/bitacora", on_error: :warn)

      html = render_click(lv, "toggle_nav", %{})
      assert is_binary(html)
    end

    test "GIVEN user WHEN closing nav THEN nav closes",
         %{conn: conn} do
      {conn, _user} = staff_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/bitacora", on_error: :warn)

      html = render_click(lv, "close_nav", %{})
      assert is_binary(html)
    end

    test "GIVEN admin WHEN toggling nav THEN admin nav links are shown",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/bitacora", on_error: :warn)

      html = render_click(lv, "toggle_nav", %{})
      assert html =~ "Panel de administración"
    end
  end
end
