defmodule CRCWeb.PageControllerTest do
  use CRCWeb.ConnCase

  test "GET / returns the home page with cafe name", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Café Raíces y Cultura"
  end
end
