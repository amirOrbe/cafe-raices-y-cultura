defmodule CRCWeb.SitemapXML do
  @moduledoc "Renders the XML sitemap for search engines."

  use CRCWeb, :html

  embed_templates "sitemap_xml/*"
end
