defmodule CRCWeb.Admin.NavTest do
  @moduledoc """
  Smoke test for the admin sidebar (lib/crc_web/components/layouts.ex,
  nav_sections/0 + nav_link/1). Guards against a typo during the nav
  regroup silently dropping a link, and confirms active-page highlighting
  works.
  """
  use CRCWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import CRC.E2EFixtures

  # Every /admin/* route that's reachable directly from the sidebar (i.e.
  # excluding detail/orphan routes only reached via in-page buttons:
  # /admin/insumos/merma, /admin/ventas/manual, /admin/clientes/:id).
  @admin_routes ~w(
    /admin /admin/usuarios /admin/clientes /admin/lealtad
    /admin/platillos /admin/platillos/categorias /admin/paquetes
    /admin/inventario /admin/proveedores /admin/insumos
    /admin/insumos/categorias /admin/produccion
    /admin/mesas /admin/descuentos
    /admin/eventos /admin/colaboradores /admin/eventos/tipos
    /admin/finanzas /admin/ventas /admin/rendimiento
    /admin/horarios /admin/asistencia /admin/calendario /admin/cumpleanos
    /admin/configuracion
  )

  defp admin_conn(conn) do
    admin = create_admin()
    {init_test_session(conn, %{"user_id" => admin.id}), admin}
  end

  test "every admin route is reachable from the sidebar", %{conn: conn} do
    {conn, _admin} = admin_conn(conn)
    {:ok, _lv, html} = live(conn, ~p"/admin")

    for path <- @admin_routes do
      assert html =~ ~s(href="#{path}"), "expected the sidebar to link to #{path}"
    end

    # /bitacora is shown in the sidebar too, even though it isn't under /admin
    assert html =~ ~s(href="/bitacora")
  end

  test "highlights the current page in the sidebar", %{conn: conn} do
    {conn, _admin} = admin_conn(conn)
    {:ok, _lv, html} = live(conn, ~p"/admin/lealtad")

    assert opening_tag_after(html, ~s(href="/admin/lealtad")) =~ ~s(aria-current="page")
    refute opening_tag_after(html, ~s(href="/admin/clientes")) =~ ~s(aria-current="page")
  end

  # Everything from just after `marker` up to the next `>` — i.e. the rest of
  # that <a ...> opening tag, regardless of attribute order.
  defp opening_tag_after(html, marker) do
    [_, rest] = String.split(html, marker, parts: 2)
    rest |> String.split(">", parts: 2) |> List.first()
  end

  test "a non-admin is redirected before the sidebar ever renders", %{conn: conn} do
    empleado = create_waiter()
    conn = init_test_session(conn, %{"user_id" => empleado.id})
    assert {:error, {:redirect, _}} = live(conn, ~p"/admin")
  end
end
