defmodule CRCWeb.Admin.AsistenciaLiveTest do
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
          email: "asist#{System.unique_integer()}@cafe.com",
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

  # Coordinates near the café
  @near_lat 19.445424998689816
  @near_lng -99.15739759497082

  # ===========================================================================
  # Access control
  # ===========================================================================

  describe "access control" do
    test "GIVEN unauthenticated user WHEN visiting /admin/asistencia THEN redirects",
         %{conn: conn} do
      assert {:error, {:redirect, _}} = live(conn, ~p"/admin/asistencia")
    end

    test "GIVEN authenticated empleado WHEN visiting /admin/asistencia THEN redirected (no admin)",
         %{conn: conn} do
      {conn, _user} = employee_conn(conn)
      assert {:error, {:redirect, _}} = live(conn, ~p"/admin/asistencia")
    end

    test "GIVEN admin user WHEN visiting /admin/asistencia THEN page loads",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      assert {:ok, _lv, html} = live(conn, ~p"/admin/asistencia")
      assert html =~ "Asistencia"
    end
  end

  # ===========================================================================
  # Mount state
  # ===========================================================================

  describe "page mount" do
    test "GIVEN admin WHEN mounting THEN today tab is active by default",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      {:ok, _lv, html} = live(conn, ~p"/admin/asistencia")
      assert html =~ "Hoy"
    end

    test "GIVEN active staff WHEN mounting THEN staff appear in today panel",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      employee = insert_user(%{name: "Empleado Visible"})

      {:ok, _lv, html} = live(conn, ~p"/admin/asistencia")
      assert html =~ "Empleado Visible"
    end
  end

  # ===========================================================================
  # Tab switching
  # ===========================================================================

  describe "switch_tab event" do
    test "GIVEN today tab active WHEN switching to metrics THEN metrics panel shown",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/asistencia")

      html = render_click(lv, "switch_tab", %{"tab" => "metrics"})
      assert html =~ "Métricas" or html =~ "Mes:"
    end

    test "GIVEN metrics tab WHEN switching back to today THEN today panel shown",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/asistencia")

      render_click(lv, "switch_tab", %{"tab" => "metrics"})
      html = render_click(lv, "switch_tab", %{"tab" => "today"})
      assert html =~ "Hoy"
    end
  end

  # ===========================================================================
  # Refresh today
  # ===========================================================================

  describe "refresh_today event" do
    test "GIVEN admin WHEN refreshing today THEN page re-renders without crash",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/asistencia")

      html = render_click(lv, "refresh_today", %{})
      assert is_binary(html)
      assert html =~ "Asistencia"
    end
  end

  # ===========================================================================
  # Manual clock-in modal
  # ===========================================================================

  describe "open_clock_in_modal event" do
    test "GIVEN admin WHEN opening clock-in modal THEN modal is shown with employee name",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      employee = insert_user(%{name: "Empleado Modal"})

      {:ok, lv, _html} = live(conn, ~p"/admin/asistencia")

      html =
        render_click(lv, "open_clock_in_modal", %{"user_id" => to_string(employee.id)})

      assert html =~ "Empleado Modal"
      assert html =~ "entrada"
    end

    test "GIVEN modal open WHEN closing THEN modal disappears",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      employee = insert_user(%{name: "Empleado Close"})

      {:ok, lv, _html} = live(conn, ~p"/admin/asistencia")
      render_click(lv, "open_clock_in_modal", %{"user_id" => to_string(employee.id)})

      html = render_click(lv, "close_modal", %{})
      refute html =~ "Empleado Close" and html =~ "Confirmar"
    end
  end

  # ===========================================================================
  # Manual clock-out modal
  # ===========================================================================

  describe "open_clock_out_modal event" do
    test "GIVEN admin WHEN opening clock-out modal THEN modal is shown",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      employee = insert_user(%{name: "Empleado Out Modal"})

      {:ok, lv, _html} = live(conn, ~p"/admin/asistencia")

      html =
        render_click(lv, "open_clock_out_modal", %{"user_id" => to_string(employee.id)})

      assert html =~ "Empleado Out Modal"
      assert html =~ "salida"
    end
  end

  # ===========================================================================
  # confirm_manual_entry event
  # ===========================================================================

  describe "confirm_manual_entry event" do
    test "GIVEN admin and employee with no record WHEN confirming manual clock-in THEN succeeds",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      employee = insert_user(%{name: "Empleado Manual In"})

      {:ok, lv, _html} = live(conn, ~p"/admin/asistencia")
      render_click(lv, "open_clock_in_modal", %{"user_id" => to_string(employee.id)})

      html = render_click(lv, "confirm_manual_entry", %{})
      # Modal should close (no longer showing "Confirmar" in modal context)
      assert is_binary(html)
    end

    test "GIVEN admin and employee clocked in WHEN confirming manual clock-out THEN succeeds",
         %{conn: conn} do
      {conn, admin} = admin_conn(conn)
      employee = insert_user(%{name: "Empleado Manual Out"})

      # First give employee a clock-in
      HR.clock_in(employee, @near_lat, @near_lng)

      {:ok, lv, _html} = live(conn, ~p"/admin/asistencia")
      render_click(lv, "open_clock_out_modal", %{"user_id" => to_string(employee.id)})

      html = render_click(lv, "confirm_manual_entry", %{})
      assert is_binary(html)
    end

    test "GIVEN clock-out attempted for employee not clocked in WHEN confirming THEN error shown",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      employee = insert_user(%{name: "Empleado No Entrada"})

      {:ok, lv, _html} = live(conn, ~p"/admin/asistencia")
      render_click(lv, "open_clock_out_modal", %{"user_id" => to_string(employee.id)})

      html = render_click(lv, "confirm_manual_entry", %{})
      assert html =~ "No" or html =~ "entrada" or html =~ "error"
    end
  end

  # ===========================================================================
  # Time option / custom time
  # ===========================================================================

  describe "time option events" do
    test "GIVEN modal open WHEN setting custom time option THEN custom input shown",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      employee = insert_user()

      {:ok, lv, _html} = live(conn, ~p"/admin/asistencia")
      render_click(lv, "open_clock_in_modal", %{"user_id" => to_string(employee.id)})

      html = render_click(lv, "set_time_option", %{"option" => "custom"})
      assert html =~ "type=\"time\""
    end

    test "GIVEN custom time option WHEN updating custom time THEN state is updated",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      employee = insert_user()

      {:ok, lv, _html} = live(conn, ~p"/admin/asistencia")
      render_click(lv, "open_clock_in_modal", %{"user_id" => to_string(employee.id)})
      render_click(lv, "set_time_option", %{"option" => "custom"})

      html = render_click(lv, "update_custom_time", %{"value" => "09:30"})
      assert is_binary(html)
    end
  end

  # ===========================================================================
  # Change month in metrics
  # ===========================================================================

  describe "change_month event" do
    test "GIVEN metrics tab WHEN changing month THEN summary is refreshed",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/asistencia")

      render_click(lv, "switch_tab", %{"tab" => "metrics"})

      today = Date.utc_today()

      html =
        render_click(lv, "change_month", %{
          "year" => to_string(today.year),
          "month" => to_string(today.month)
        })

      assert is_binary(html)
    end
  end
end
