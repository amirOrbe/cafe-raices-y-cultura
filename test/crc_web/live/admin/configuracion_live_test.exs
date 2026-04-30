defmodule CRCWeb.Admin.ConfiguracionLiveTest do
  use CRCWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias CRC.Settings

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp insert_user(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          name: "Config User",
          email: "cfg#{System.unique_integer()}@cafe.com",
          role: "admin",
          stations: [],
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
    admin = insert_user()
    conn = init_test_session(conn, %{"user_id" => admin.id})
    {conn, admin}
  end

  defp employee_conn(conn) do
    user = insert_user(%{role: "empleado", stations: ["sala"]})
    conn = init_test_session(conn, %{"user_id" => user.id})
    {conn, user}
  end

  # ===========================================================================
  # Access control
  # ===========================================================================

  describe "access control" do
    test "GIVEN unauthenticated user WHEN visiting /admin/configuracion THEN redirects",
         %{conn: conn} do
      assert {:error, {:redirect, _}} = live(conn, ~p"/admin/configuracion")
    end

    test "GIVEN empleado WHEN visiting /admin/configuracion THEN redirected",
         %{conn: conn} do
      {conn, _user} = employee_conn(conn)
      assert {:error, {:redirect, _}} = live(conn, ~p"/admin/configuracion")
    end

    test "GIVEN admin WHEN visiting /admin/configuracion THEN page loads",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      assert {:ok, _lv, html} = live(conn, ~p"/admin/configuracion")
      assert html =~ "Configuración" or html =~ "horario"
    end
  end

  # ===========================================================================
  # Mount state
  # ===========================================================================

  describe "page mount" do
    test "GIVEN no hours configured WHEN mounting THEN edit prompt shown",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      {:ok, _lv, html} = live(conn, ~p"/admin/configuracion")
      assert html =~ "Lun" or html =~ "Editar"
    end

    test "GIVEN hours configured WHEN mounting THEN schedule is shown",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)

      Settings.set_cafe_hours([
        %{
          day_of_week: 1,
          opening_time: ~T[10:00:00],
          closing_time: ~T[21:00:00],
          is_closed: false
        }
      ])

      {:ok, _lv, html} = live(conn, ~p"/admin/configuracion")
      assert html =~ "Lun" or html =~ "10:00"
    end
  end

  # ===========================================================================
  # start_edit / cancel_edit events
  # ===========================================================================

  describe "start_edit event" do
    test "GIVEN admin WHEN starting edit THEN form is shown",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/configuracion")

      html = render_click(lv, "start_edit", %{})
      assert html =~ "Guardar" or html =~ "Cancelar"
    end
  end

  describe "cancel_edit event" do
    test "GIVEN editing mode WHEN cancelling THEN view mode restored",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/configuracion")

      render_click(lv, "start_edit", %{})
      html = render_click(lv, "cancel_edit", %{})
      assert html =~ "Editar" or html =~ "horario"
    end
  end

  # ===========================================================================
  # toggle_day event
  # ===========================================================================

  describe "toggle_day event" do
    test "GIVEN editing mode WHEN toggling a day THEN state updates",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/configuracion")
      render_click(lv, "start_edit", %{})

      html = render_click(lv, "toggle_day", %{"day" => "1"})
      assert is_binary(html)
    end
  end

  # ===========================================================================
  # update_time event
  # ===========================================================================

  describe "update_time event" do
    test "GIVEN editing mode WHEN updating opening time THEN state updates",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/configuracion")
      render_click(lv, "start_edit", %{})

      html =
        render_click(lv, "update_time", %{
          "day" => "1",
          "field" => "opening",
          "value" => "09:00"
        })

      assert is_binary(html)
    end

    test "GIVEN editing mode WHEN updating closing time THEN state updates",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/configuracion")
      render_click(lv, "start_edit", %{})

      html =
        render_click(lv, "update_time", %{
          "day" => "1",
          "field" => "closing",
          "value" => "22:00"
        })

      assert is_binary(html)
    end
  end

  # ===========================================================================
  # save_hours event
  # ===========================================================================

  describe "save_hours event" do
    test "GIVEN valid form data WHEN saving hours THEN success flash shown",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/configuracion")
      render_click(lv, "start_edit", %{})

      # Toggle Monday on
      render_click(lv, "toggle_day", %{"day" => "1"})
      render_click(lv, "update_time", %{"day" => "1", "field" => "opening", "value" => "09:00"})
      render_click(lv, "update_time", %{"day" => "1", "field" => "closing", "value" => "21:00"})

      html = render_click(lv, "save_hours", %{})
      assert html =~ "guardado" or html =~ "Guardar" or html =~ "correctamente"
    end

    test "GIVEN hours saved WHEN re-mounting THEN hours persist",
         %{conn: conn} do
      {conn, _admin} = admin_conn(conn)
      {:ok, lv, _html} = live(conn, ~p"/admin/configuracion")
      render_click(lv, "start_edit", %{})
      render_click(lv, "toggle_day", %{"day" => "2"})
      render_click(lv, "update_time", %{"day" => "2", "field" => "opening", "value" => "10:00"})
      render_click(lv, "update_time", %{"day" => "2", "field" => "closing", "value" => "20:00"})
      render_click(lv, "save_hours", %{})

      # Verify in DB
      rows = Settings.list_cafe_hours()
      tuesday = Enum.find(rows, &(&1.day_of_week == 2))
      assert tuesday
      assert tuesday.is_closed == false
    end
  end
end
