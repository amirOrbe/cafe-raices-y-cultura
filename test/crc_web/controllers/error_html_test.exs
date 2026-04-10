defmodule CRCWeb.ErrorHTMLTest do
  use CRCWeb.ConnCase, async: true

  import Phoenix.Template, only: [render_to_string: 4]

  test "renders 404.html" do
    assert render_to_string(CRCWeb.ErrorHTML, "404", "html", []) =~ "Página no encontrada"
  end

  test "renders 500.html" do
    assert render_to_string(CRCWeb.ErrorHTML, "500", "html", []) =~ "Error interno"
  end
end
