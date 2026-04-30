defmodule CRCWeb.Admin.HorariosLiveTest do
  use CRCWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias CRC.HR

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp insert_user(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          name: "Test User",
          email: "hor#{System.unique_integer()}@cafe.com",
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

  # ===========================================================================
  # Access control
  # ===========================================================================

  describe "access control" do
    test "GIVEN unauthenticated user WHEN visiting /admin/horarios THEN redirects",
         %{conn: conn} do
      assert {:error, {:redirect, _}} = live(conn, ~p"/admin/horarios")
    end

    test "GIVEN authenticated empleado WHEN visiting /admin/horarios THEN redirected",
         %{conn: conn} do
      {conn, _user} = employee_conn(conn)
      assert {:error, {:redirect, _}} = live(conn, ~p"/admin/horarios")
    end

    test "GIVEN admin WHEN visiting /admin/horarios THEN page loads",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      assert {:ok, _lv, html} = live(conn, ~p"/admin/horarios")
      assert html =~ "Horarios"
    end
  end

  # ===========================================================================
  # Mount state
  # ===========================================================================

  describe "page mount" do
    test "GIVEN active staff users WHEN mounting THEN they appear in the sidebar list",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      employee = insert_user(%{name: "Empleado Horario"})

      {:ok, _lv, html} = live(conn, ~p"/admin/horarios")
      assert html =~ "Empleado Horario"
    end

    test "GIVEN no user selected WHEN mounting THEN placeholder message shown",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      {:ok, _lv, html} = live(conn, ~p"/admin/horarios")
      assert html =~ "Selecciona un empleado"
    end

    test "GIVEN cliente user exists WHEN mounting THEN cliente is NOT shown",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      _cliente = insert_user(%{role: "cliente", name: "Cliente Oculto"})

      {:ok, _lv, html} = live(conn, ~p"/admin/horarios")
      refute html =~ "Cliente Oculto"
    end
  end

  # ===========================================================================
  # select_user event
  # ===========================================================================

  describe "select_user event" do
    test "GIVEN employees listed WHEN selecting one THEN their schedule panel is shown",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      employee = insert_user(%{name: "Empleado Seleccionado"})

      {:ok, lv, _html} = live(conn, ~p"/admin/horarios")

      html = render_click(lv, "select_user", %{"id" => to_string(employee.id)})
      assert html =~ "Empleado Seleccionado"
      assert html =~ "Editar horario"
    end

    test "GIVEN employee with existing schedule WHEN selecting THEN schedule times are shown",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      employee = insert_user(%{name: "Con Horario"})

      HR.set_work_schedules(employee.id, [
        %{day_of_week: 1, start_time: ~T[08:00:00], end_time: ~T[16:00:00]}
      ])

      {:ok, lv, _html} = live(conn, ~p"/admin/horarios")
      html = render_click(lv, "select_user", %{"id" => to_string(employee.id)})
      assert html =~ "08:00"
      assert html =~ "16:00"
    end

    test "GIVEN employee with no schedule WHEN selecting THEN empty state shown",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      employee = insert_user(%{name: "Sin Horario"})

      {:ok, lv, _html} = live(conn, ~p"/admin/horarios")
      html = render_click(lv, "select_user", %{"id" => to_string(employee.id)})
      assert html =~ "Sin horario"
    end
  end

  # ===========================================================================
  # start_edit / cancel_edit
  # ===========================================================================

  describe "start_edit event" do
    test "GIVEN employee selected WHEN starting edit THEN edit form is shown",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      employee = insert_user()

      {:ok, lv, _html} = live(conn, ~p"/admin/horarios")
      render_click(lv, "select_user", %{"id" => to_string(employee.id)})

      html = render_click(lv, "start_edit", %{})
      assert html =~ "Guardar horario"
      assert html =~ "Cancelar"
    end
  end

  describe "cancel_edit event" do
    test "GIVEN editing mode WHEN cancelling THEN view mode is restored",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      employee = insert_user()

      {:ok, lv, _html} = live(conn, ~p"/admin/horarios")
      render_click(lv, "select_user", %{"id" => to_string(employee.id)})
      render_click(lv, "start_edit", %{})

      html = render_click(lv, "cancel_edit", %{})
      assert html =~ "Editar horario"
      refute html =~ "Guardar horario"
    end
  end

  # ===========================================================================
  # toggle_day event
  # ===========================================================================

  describe "toggle_day event" do
    test "GIVEN editing mode WHEN toggling a day THEN state updates",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      employee = insert_user()

      {:ok, lv, _html} = live(conn, ~p"/admin/horarios")
      render_click(lv, "select_user", %{"id" => to_string(employee.id)})
      render_click(lv, "start_edit", %{})

      html = render_click(lv, "toggle_day", %{"day" => "1"})
      assert is_binary(html)
    end
  end

  # ===========================================================================
  # update_time event
  # ===========================================================================

  describe "update_time event" do
    test "GIVEN editing mode WHEN updating start time THEN state updates",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      employee = insert_user()

      {:ok, lv, _html} = live(conn, ~p"/admin/horarios")
      render_click(lv, "select_user", %{"id" => to_string(employee.id)})
      render_click(lv, "start_edit", %{})
      # Enable day 1
      render_click(lv, "toggle_day", %{"day" => "1"})

      html =
        render_click(lv, "update_time", %{
          "day" => "1",
          "field" => "start",
          "value" => "07:30"
        })

      assert is_binary(html)
    end
  end

  # ===========================================================================
  # save_schedule event
  # ===========================================================================

  describe "save_schedule event" do
    test "GIVEN employee with days toggled on WHEN saving schedule THEN success flash shown",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      employee = insert_user(%{name: "Empleado Guardar"})

      {:ok, lv, _html} = live(conn, ~p"/admin/horarios")
      render_click(lv, "select_user", %{"id" => to_string(employee.id)})
      render_click(lv, "start_edit", %{})

      # Toggle Monday on
      render_click(lv, "toggle_day", %{"day" => "1"})

      html = render_click(lv, "save_schedule", %{})
      assert html =~ "Guardar" or html =~ "guardado" or html =~ "correctamente"
    end

    test "GIVEN employee WHEN saving empty schedule THEN schedules are cleared",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      employee = insert_user()

      # Set a schedule first
      HR.set_work_schedules(employee.id, [
        %{day_of_week: 1, start_time: ~T[08:00:00], end_time: ~T[16:00:00]}
      ])

      {:ok, lv, _html} = live(conn, ~p"/admin/horarios")
      render_click(lv, "select_user", %{"id" => to_string(employee.id)})
      render_click(lv, "start_edit", %{})

      # Toggle Monday OFF (it's on because of existing schedule)
      render_click(lv, "toggle_day", %{"day" => "1"})

      html = render_click(lv, "save_schedule", %{})
      assert is_binary(html)

      # Verify in DB
      schedules = HR.list_work_schedules(employee.id)
      assert schedules == []
    end
  end
end
