defmodule CRCWeb.SitemapControllerTest do
  use CRCWeb.ConnCase, async: true

  test "GET /sitemap.xml returns XML content", %{conn: conn} do
    conn = get(conn, "/sitemap.xml")
    assert response_content_type(conn, :xml) =~ "xml"
    body = response(conn, 200)
    assert body =~ "urlset"
    assert body =~ "<loc>"
  end
end
