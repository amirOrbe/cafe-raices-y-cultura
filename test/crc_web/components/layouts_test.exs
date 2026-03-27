defmodule CRCWeb.LayoutsTest do
  use ExUnit.Case, async: true

  defp inner_block(content) do
    [%{__slot__: :inner_block, inner_block: fn _, _ -> content end}]
  end

  defp exec(rendered) do
    rendered.dynamic.(nil)
    rendered
  end

  # ---------------------------------------------------------------------------
  # app/1  (scaffold layout — not used in CRC templates)
  # ---------------------------------------------------------------------------

  describe "Layouts.app/1" do
    test "renders the app scaffold layout" do
      assigns = %{
        __changed__: nil,
        flash: %{},
        current_scope: nil,
        inner_block: inner_block("Hola mundo")
      }

      rendered = assigns |> CRCWeb.Layouts.app() |> exec()
      assert is_struct(rendered, Phoenix.LiveView.Rendered)
    end
  end

  # ---------------------------------------------------------------------------
  # theme_toggle/1  (scaffold — not used in CRC templates)
  # ---------------------------------------------------------------------------

  describe "Layouts.theme_toggle/1" do
    test "renders the theme toggle" do
      assigns = %{__changed__: nil}

      rendered = assigns |> CRCWeb.Layouts.theme_toggle() |> exec()
      assert is_struct(rendered, Phoenix.LiveView.Rendered)
    end
  end
end
