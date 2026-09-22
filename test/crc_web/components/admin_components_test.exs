defmodule CRCWeb.AdminComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import CRCWeb.AdminComponents

  describe "panel/1" do
    test "renders the shared card wrapper class and inner content" do
      html = render_component(&panel/1, %{inner_block: [%{inner_block: fn _, _ -> "hola" end}]})
      assert html =~ "bg-base-100"
      assert html =~ "rounded-2xl"
      assert html =~ "hola"
    end

    test "merges a caller class onto the wrapper" do
      html =
        render_component(&panel/1, %{
          class: "p-5",
          inner_block: [%{inner_block: fn _, _ -> "x" end}]
        })

      assert html =~ "p-5"
    end
  end

  describe "stat_card/1" do
    test "renders label, value, icon and variant color classes" do
      html =
        render_component(&stat_card/1, %{
          label: "Ingresos",
          value: "$100.00",
          icon: "hero-banknotes",
          variant: :success
        })

      assert html =~ "Ingresos"
      assert html =~ "$100.00"
      assert html =~ "hero-banknotes"
      assert html =~ "bg-success/10"
      assert html =~ "text-success"
    end

    test "shows a sublabel when given" do
      html =
        render_component(&stat_card/1, %{
          label: "Ganancia bruta",
          value: "$167,051.59",
          icon: "hero-arrow-trending-up",
          sublabel: "Margen 79.9%"
        })

      assert html =~ "Margen 79.9%"
    end

    test "renders no sublabel markup when not given" do
      html =
        render_component(&stat_card/1, %{
          label: "Comandas",
          value: 12,
          icon: "hero-clipboard"
        })

      assert html =~ "Comandas"
      refute html =~ "text-base-content/40 leading-tight"
    end
  end

  describe "mini_stat/1" do
    test "renders label, value and color class" do
      html =
        render_component(&mini_stat/1, %{
          label: "Activos",
          value: 10,
          icon: "hero-check-circle",
          color: "text-success"
        })

      assert html =~ "Activos"
      assert html =~ "10"
      assert html =~ "text-success"
    end
  end

  describe "admin_badge/1" do
    test "builds the badge-{size}-{variant} class combo" do
      html =
        render_component(&admin_badge/1, %{
          variant: :success,
          size: "sm",
          inner_block: [%{inner_block: fn _, _ -> "Activo" end}]
        })

      assert html =~ "badge-sm"
      assert html =~ "badge-success"
      assert html =~ "Activo"
    end

    test "defaults to badge-ghost badge-sm" do
      html =
        render_component(&admin_badge/1, %{inner_block: [%{inner_block: fn _, _ -> "X" end}]})

      assert html =~ "badge-ghost"
      assert html =~ "badge-sm"
    end
  end

  describe "admin_modal/1" do
    test "renders the title slot, close handler, and inner content" do
      html =
        render_component(&admin_modal/1, %{
          id: "test-modal",
          on_close: "close_modal",
          title: [%{inner_block: fn _, _ -> "Nuevo cliente" end}],
          inner_block: [%{inner_block: fn _, _ -> "cuerpo del modal" end}]
        })

      assert html =~ "Nuevo cliente"
      assert html =~ "cuerpo del modal"
      assert html =~ ~s(phx-window-keydown="close_modal")
      assert html =~ "max-w-md"
    end

    test "size attr controls the max-width class" do
      html =
        render_component(&admin_modal/1, %{
          id: "test-modal-lg",
          size: "lg",
          on_close: "close_modal",
          title: [%{inner_block: fn _, _ -> "Título" end}],
          inner_block: [%{inner_block: fn _, _ -> "x" end}]
        })

      assert html =~ "max-w-lg"
    end
  end

  describe "admin_table_head/1" do
    test "renders one <th> per :col slot with its class" do
      html =
        render_component(&admin_table_head/1, %{
          col: [
            %{inner_block: fn _, _ -> "Nombre" end, class: "w-[30%]"},
            %{inner_block: fn _, _ -> "Acciones" end, class: "w-[20%] text-right"}
          ]
        })

      assert html =~ "Nombre"
      assert html =~ "Acciones"
      assert html =~ "w-[30%]"
      assert html =~ "bg-base-200"
      assert html =~ "uppercase"
    end
  end

  describe "period_filter/1" do
    test "highlights the active period button" do
      html = render_component(&period_filter/1, %{period: :week})

      assert html =~ "Esta semana"
      assert html =~ "Hoy"
      assert html =~ "Este mes"
      assert html =~ "Total"
      assert html =~ ~s(phx-value-period="week")
    end

    test "renders the custom date range inputs with given values" do
      html =
        render_component(&period_filter/1, %{
          period: :all,
          date_from: "2026-01-01",
          date_to: "2026-01-31"
        })

      assert html =~ "2026-01-01"
      assert html =~ "2026-01-31"
      assert html =~ ~s(phx-change="set_date_range")
    end
  end
end
