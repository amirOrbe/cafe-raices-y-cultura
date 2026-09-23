defmodule CRCWeb.Admin.NavTest do
  @moduledoc """
  Smoke test for the admin card-grid navigation
  (lib/crc_web/components/admin_components.ex, nav_sections/0 + nav_card/1)
  and the top bar's "Volver al panel" link (lib/crc_web/components/layouts.ex,
  admin/1). Guards against a typo during the nav regroup silently dropping a
  link.
  """
  use CRCWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import CRC.E2EFixtures

  # Every /admin/* route reachable directly from the /admin card grid (i.e.
  # excluding detail/orphan routes only reached via in-page buttons:
  # /admin/clientes/:id).
  @admin_routes ~w(
    /admin /admin/usuarios /admin/clientes /admin/lealtad
    /admin/platillos /admin/platillos/categorias /admin/paquetes
    /admin/inventario /admin/proveedores /admin/insumos
    /admin/insumos/categorias /admin/insumos/merma /admin/produccion
    /admin/mesas /admin/descuentos
    /admin/eventos /admin/colaboradores /admin/eventos/tipos
    /admin/finanzas /admin/ventas /admin/ventas/manual /admin/rendimiento
    /admin/horarios /admin/asistencia /admin/calendario /admin/cumpleanos
    /admin/configuracion
  )

  defp admin_conn(conn) do
    admin = create_admin()
    {init_test_session(conn, %{"user_id" => admin.id}), admin}
  end

  test "every admin route is reachable from the /admin card grid", %{conn: conn} do
    {conn, _admin} = admin_conn(conn)
    {:ok, _lv, html} = live(conn, ~p"/admin?tab=gestion")

    for path <- @admin_routes do
      assert html =~ ~s(href="#{path}"), "expected the card grid to link to #{path}"
    end

    # /bitacora is shown in the grid too, even though it isn't under /admin
    assert html =~ ~s(href="/bitacora")
  end

  test "top bar shows the logo on /admin and 'Volver al panel' elsewhere", %{conn: conn} do
    {conn, _admin} = admin_conn(conn)

    {:ok, _lv, home_html} = live(conn, ~p"/admin")
    assert home_html =~ "CRC Admin"
    refute home_html =~ "Volver al panel"

    {:ok, _lv, inner_html} = live(conn, ~p"/admin/lealtad")
    assert inner_html =~ "Volver al panel"
    assert inner_html =~ ~s(href="/admin")
  end

  test "a non-admin is redirected before the panel ever renders", %{conn: conn} do
    empleado = create_waiter()
    conn = init_test_session(conn, %{"user_id" => empleado.id})
    assert {:error, {:redirect, _}} = live(conn, ~p"/admin")
  end
end
