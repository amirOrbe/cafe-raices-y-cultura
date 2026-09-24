defmodule CRCWeb.Admin.ReportControllerTest do
  use CRCWeb.ConnCase, async: true

  import CRC.E2EFixtures

  defp admin_conn(conn) do
    admin = create_admin()
    init_test_session(conn, %{"user_id" => admin.id})
  end

  describe "authentication" do
    test "redirects unauthenticated user", %{conn: conn} do
      conn = get(conn, "/admin/reportes/finanzas.csv")
      assert redirected_to(conn) =~ "/iniciar-sesion"
    end

    test "redirects non-admin", %{conn: conn} do
      empleado = create_waiter()
      conn = init_test_session(conn, %{"user_id" => empleado.id})
      conn = get(conn, "/admin/reportes/finanzas.csv")
      assert redirected_to(conn) == "/"
    end
  end

  describe "GET /admin/reportes/finanzas.csv" do
    test "returns a CSV download for an admin", %{conn: conn} do
      conn = conn |> admin_conn() |> get("/admin/reportes/finanzas.csv")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["text/csv"]
      assert [disposition] = get_resp_header(conn, "content-disposition")
      assert disposition =~ "attachment"
      assert disposition =~ "finanzas_"
      assert conn.resp_body =~ "Ingresos"
    end

    test "accepts a period param", %{conn: conn} do
      conn = conn |> admin_conn() |> get("/admin/reportes/finanzas.csv?period=week")
      assert conn.status == 200
      assert conn.resp_body =~ "Ingresos"
    end

    test "accepts a custom date range", %{conn: conn} do
      conn =
        conn
        |> admin_conn()
        |> get(
          "/admin/reportes/finanzas.csv?period=range&date_from=2026-01-01&date_to=2026-01-31"
        )

      assert conn.status == 200
      assert conn.resp_body =~ "Ingresos"
    end

    test "falls back to :all on an invalid range", %{conn: conn} do
      conn =
        conn
        |> admin_conn()
        |> get("/admin/reportes/finanzas.csv?period=range&date_from=bad&date_to=bad")

      assert conn.status == 200
      assert conn.resp_body =~ "Ingresos"
    end
  end

  describe "GET /admin/reportes/desperdicio.csv" do
    test "returns a CSV download for an admin", %{conn: conn} do
      conn = conn |> admin_conn() |> get("/admin/reportes/desperdicio.csv")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["text/csv"]
      assert conn.resp_body =~ "Platillo"
    end
  end

  describe "GET /admin/reportes/ventas.csv" do
    test "returns a CSV download for an admin", %{conn: conn} do
      conn = conn |> admin_conn() |> get("/admin/reportes/ventas.csv")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["text/csv"]
      assert conn.resp_body =~ "Mesero"
    end
  end
end
