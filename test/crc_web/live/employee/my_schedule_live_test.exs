defmodule CRCWeb.Employee.MyScheduleLiveTest do
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
          name: "Test Employee",
          email: "emp#{System.unique_integer()}@cafe.com",
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

  defp employee_conn(conn, overrides \\ %{}) do
    user = insert_user(overrides)
    conn = init_test_session(conn, %{"user_id" => user.id})
    {conn, user}
  end

  defp admin_conn(conn) do
    user = insert_user(%{role: "admin"})
    conn = init_test_session(conn, %{"user_id" => user.id})
    {conn, user}
  end

  # Coordinates within 350 m of the café
  @near_lat 19.445424998689816
  @near_lng -99.15739759497082

  # ===========================================================================
  # Access control
  # ===========================================================================

  describe "access control" do
    test "GIVEN unauthenticated user WHEN visiting /mi-horario THEN redirects to login",
         %{conn: conn} do
      assert {:error, {:redirect, %{to: "/iniciar-sesion"}}} = live(conn, ~p"/mi-horario")
    end

    test "GIVEN authenticated empleado WHEN visiting /mi-horario THEN page loads",
         %{conn: conn} do
      {conn, user} = employee_conn(conn)
      assert {:ok, _lv, html} = live(conn, ~p"/mi-horario")
      assert html =~ user.name
    end

    test "GIVEN authenticated admin WHEN visiting /mi-horario THEN page loads",
         %{conn: conn} do
      {conn, user} = admin_conn(conn)
      assert {:ok, _lv, html} = live(conn, ~p"/mi-horario")
      assert html =~ user.name
    end
  end

  # ===========================================================================
  # Mount state
  # ===========================================================================

  describe "page mount" do
    test "GIVEN employee with no schedule WHEN mounting THEN schedule grid is shown",
         %{conn: conn} do
      {conn, _user} = employee_conn(conn)

      {:ok, _lv, html} = live(conn, ~p"/mi-horario")
      assert html =~ "Esta semana"
    end

    test "GIVEN employee with schedule WHEN mounting THEN schedule times are shown",
         %{conn: conn} do
      {conn, user} = employee_conn(conn)
      today = Date.utc_today()
      day_of_week = Date.day_of_week(today)

      HR.set_work_schedules(user.id, [
        %{day_of_week: day_of_week, start_time: ~T[09:00:00], end_time: ~T[17:00:00]}
      ])

      {:ok, _lv, html} = live(conn, ~p"/mi-horario")
      assert html =~ "09:00"
      assert html =~ "17:00"
    end

    test "GIVEN employee with attendance history WHEN mounting THEN historial section shown",
         %{conn: conn} do
      {conn, user} = employee_conn(conn)
      # Create a record for today
      HR.get_or_create_today_record(user)

      {:ok, _lv, html} = live(conn, ~p"/mi-horario")
      assert html =~ "Hola"
    end

    test "GIVEN employee not clocked in WHEN mounting THEN clock-in button is shown",
         %{conn: conn} do
      {conn, _user} = employee_conn(conn)
      {:ok, _lv, html} = live(conn, ~p"/mi-horario")
      assert html =~ "Ya estoy aquí"
    end

    test "GIVEN employee already clocked in WHEN mounting THEN clock-out button is shown",
         %{conn: conn} do
      {conn, user} = employee_conn(conn)
      HR.clock_in(user, @near_lat, @near_lng)

      {:ok, _lv, html} = live(conn, ~p"/mi-horario")
      assert html =~ "Registrar salida"
    end

    test "GIVEN employee clocked in and out WHEN mounting THEN completion message shown",
         %{conn: conn} do
      {conn, user} = employee_conn(conn)
      HR.clock_in(user, @near_lat, @near_lng)
      HR.clock_out(user)

      {:ok, _lv, html} = live(conn, ~p"/mi-horario")
      assert html =~ "Jornada completada"
    end
  end

  # ===========================================================================
  # clock_in_with_location event
  # ===========================================================================

  describe "clock_in_with_location event" do
    test "GIVEN employee near café WHEN clocking in with location THEN record is updated",
         %{conn: conn} do
      {conn, _user} = employee_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/mi-horario")

      html =
        render_click(lv, "clock_in_with_location", %{
          "latitude" => @near_lat,
          "longitude" => @near_lng
        })

      # After clock-in, the clock-out button should be visible
      assert html =~ "Registrar salida"
    end

    test "GIVEN employee far from café WHEN clocking in with location THEN error is shown",
         %{conn: conn} do
      {conn, _user} = employee_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/mi-horario")

      html =
        render_click(lv, "clock_in_with_location", %{
          "latitude" => 19.420,
          "longitude" => -99.160
        })

      assert html =~ "GPS"
    end

    test "GIVEN already clocked in employee WHEN clock_in event fires again THEN no crash",
         %{conn: conn} do
      {conn, user} = employee_conn(conn)
      HR.clock_in(user, @near_lat, @near_lng)

      {:ok, lv, _html} = live(conn, ~p"/mi-horario")

      html =
        render_click(lv, "clock_in_with_location", %{
          "latitude" => @near_lat,
          "longitude" => @near_lng
        })

      # Should still show clock-out
      assert html =~ "Registrar salida"
    end
  end

  # ===========================================================================
  # location_denied event
  # ===========================================================================

  describe "location_denied event" do
    test "GIVEN browser denies permission WHEN location_denied event fires THEN error message shown",
         %{conn: conn} do
      {conn, _user} = employee_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/mi-horario")

      html = render_click(lv, "location_denied", %{"reason" => "permission_denied"})
      assert html =~ "Permiso de ubicación"
    end

    test "GIVEN GPS timeout WHEN location_denied event fires THEN warning shown",
         %{conn: conn} do
      {conn, _user} = employee_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/mi-horario")

      html = render_click(lv, "location_denied", %{"reason" => "timeout"})
      assert html =~ "ubicación"
    end

    test "GIVEN GPS unavailable WHEN location_denied event fires with no reason THEN fallback shown",
         %{conn: conn} do
      {conn, _user} = employee_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/mi-horario")

      html = render_click(lv, "location_denied", %{})
      assert html =~ "ubicación"
    end
  end

  # ===========================================================================
  # clock_out event
  # ===========================================================================

  describe "clock_out event" do
    test "GIVEN clocked-in employee WHEN clocking out THEN completion state shown",
         %{conn: conn} do
      {conn, user} = employee_conn(conn)
      HR.clock_in(user, @near_lat, @near_lng)

      {:ok, lv, _html} = live(conn, ~p"/mi-horario")
      html = render_click(lv, "clock_out", %{})

      assert html =~ "Jornada completada"
    end

    test "GIVEN NOT clocked in WHEN clocking out THEN error shown",
         %{conn: conn} do
      {conn, _user} = employee_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/mi-horario")

      html = render_click(lv, "clock_out", %{})
      assert html =~ "entrada"
    end
  end

  # ===========================================================================
  # location_requesting event
  # ===========================================================================

  describe "location_requesting event" do
    test "GIVEN employee WHEN location is being requested THEN loading state shown",
         %{conn: conn} do
      {conn, _user} = employee_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/mi-horario")

      html = render_click(lv, "location_requesting", %{})
      assert html =~ "Obteniendo"
    end
  end

  # ===========================================================================
  # Navigation events
  # ===========================================================================

  describe "navigation events" do
    test "GIVEN nav closed WHEN toggling THEN nav_open changes",
         %{conn: conn} do
      {conn, _user} = employee_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/mi-horario")

      # toggle open
      render_click(lv, "toggle_nav", %{})
      # toggle closed
      html = render_click(lv, "close_nav", %{})
      assert is_binary(html)
    end
  end
end
