defmodule CRCWeb.PageController do
  use CRCWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
