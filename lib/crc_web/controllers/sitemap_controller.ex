defmodule CRCWeb.SitemapController do
  use CRCWeb, :controller

  @pages [
    %{loc: "/", priority: "1.0", changefreq: "weekly"},
    %{loc: "/menu", priority: "0.8", changefreq: "weekly"},
    %{loc: "/colaboraciones", priority: "0.7", changefreq: "monthly"}
  ]

  def index(conn, _params) do
    conn
    |> put_resp_content_type("application/xml")
    |> render(:index, pages: @pages, host: CRCWeb.Endpoint.url())
  end
end
