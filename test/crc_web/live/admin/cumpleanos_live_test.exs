defmodule CRCWeb.Admin.CumpleanosLiveTest do
  use CRCWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import CRC.E2EFixtures

  defp admin_conn(conn) do
    admin = create_admin()
    {init_test_session(conn, %{"user_id" => admin.id}), admin}
  end

  test "redirects a non-admin", %{conn: conn} do
    empleado = create_waiter()
    conn = init_test_session(conn, %{"user_id" => empleado.id})
    assert {:error, {:redirect, _}} = live(conn, ~p"/admin/cumpleanos")
  end

  test "switches to the customers tab and lists customer birthdays", %{conn: conn} do
    {conn, _admin} = admin_conn(conn)
    today = Date.utc_today()
    create_customer(%{name: "Clienta Cumple", birthday: Date.add(today, 3)})

    {:ok, lv, html} = live(conn, ~p"/admin/cumpleanos")
    refute html =~ "Clienta Cumple"

    html = lv |> element("button", "Clientes") |> render_click()
    assert html =~ "Clienta Cumple"
  end
end
