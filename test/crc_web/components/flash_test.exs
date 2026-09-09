defmodule CRCWeb.FlashTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias CRCWeb.CoreComponents

  describe "flash/1 auto-dismiss hook" do
    test "info/error toasts get the AutoDismissFlash hook" do
      html =
        render_component(&CoreComponents.flash/1, kind: :info, flash: %{"info" => "Guardado"})

      assert html =~ ~s(phx-hook="AutoDismissFlash")
      assert html =~ "Guardado"
    end

    test "the persistent connection-status flash does NOT auto-dismiss" do
      html =
        render_component(&CoreComponents.flash/1, id: "client-error", kind: :error, flash: %{}) do
          "Intentando reconectar"
        end

      refute html =~ "AutoDismissFlash"
    end
  end
end
