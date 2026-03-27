defmodule CRCWeb.CoreComponentsTest do
  use ExUnit.Case, async: true

  # ---------------------------------------------------------------------------
  # Slot helpers
  # ---------------------------------------------------------------------------

  defp slot(name, attrs, content) do
    Map.merge(%{__slot__: name, inner_block: fn _, _ -> content end}, attrs)
  end

  defp inner_block(content) do
    [slot(:inner_block, %{}, content)]
  end

  # Execute the dynamic rendering of a component (needed for coverage of
  # HEEx template lines, which live inside the dynamic fn closure).
  defp exec(rendered) do
    rendered.dynamic.(nil)
    rendered
  end

  # ---------------------------------------------------------------------------
  # button/1
  # ---------------------------------------------------------------------------

  describe "button/1" do
    test "renders a link button when navigate is present" do
      assigns = %{
        __changed__: nil,
        rest: %{navigate: "/"},
        class: nil,
        variant: nil,
        inner_block: inner_block("Ir")
      }

      rendered = assigns |> CRCWeb.CoreComponents.button() |> exec()
      assert is_struct(rendered, Phoenix.LiveView.Rendered)
    end

    test "renders a regular button without navigate" do
      assigns = %{
        __changed__: nil,
        rest: %{},
        class: nil,
        variant: nil,
        inner_block: inner_block("Enviar")
      }

      rendered = assigns |> CRCWeb.CoreComponents.button() |> exec()
      assert is_struct(rendered, Phoenix.LiveView.Rendered)
    end

    test "renders button with explicit class" do
      assigns = %{
        __changed__: nil,
        rest: %{},
        class: "btn btn-primary",
        variant: "primary",
        inner_block: inner_block("Primary")
      }

      rendered = assigns |> CRCWeb.CoreComponents.button() |> exec()
      assert is_struct(rendered, Phoenix.LiveView.Rendered)
    end
  end

  # ---------------------------------------------------------------------------
  # input/1 — checkbox branch
  # ---------------------------------------------------------------------------

  describe "input/1 checkbox" do
    test "renders a checkbox input" do
      assigns = %{
        __changed__: nil,
        type: "checkbox",
        id: "agree",
        name: "agree",
        label: "Acepto los términos",
        value: false,
        checked: false,
        errors: [],
        class: nil,
        error_class: nil,
        multiple: false,
        rest: %{}
      }

      rendered = assigns |> CRCWeb.CoreComponents.input() |> exec()
      assert is_struct(rendered, Phoenix.LiveView.Rendered)
    end

    test "renders a checkbox with checked=true and errors" do
      assigns = %{
        __changed__: nil,
        type: "checkbox",
        id: "agree2",
        name: "agree2",
        label: "Acepto",
        value: true,
        checked: true,
        errors: ["no puede estar en blanco"],
        class: "checkbox-primary",
        error_class: "input-error",
        multiple: false,
        rest: %{}
      }

      rendered = assigns |> CRCWeb.CoreComponents.input() |> exec()
      assert is_struct(rendered, Phoenix.LiveView.Rendered)
    end
  end

  # ---------------------------------------------------------------------------
  # header/1
  # ---------------------------------------------------------------------------

  describe "header/1" do
    test "renders a header with title only" do
      assigns = %{
        __changed__: nil,
        inner_block: inner_block("Mi Título"),
        subtitle: [],
        actions: []
      }

      rendered = assigns |> CRCWeb.CoreComponents.header() |> exec()
      assert is_struct(rendered, Phoenix.LiveView.Rendered)
    end

    test "renders a header with subtitle and actions" do
      assigns = %{
        __changed__: nil,
        inner_block: inner_block("Título"),
        subtitle: [slot(:subtitle, %{}, "Subtítulo")],
        actions: [slot(:actions, %{}, "Acción")]
      }

      rendered = assigns |> CRCWeb.CoreComponents.header() |> exec()
      assert is_struct(rendered, Phoenix.LiveView.Rendered)
    end
  end

  # ---------------------------------------------------------------------------
  # table/1
  # ---------------------------------------------------------------------------

  describe "table/1" do
    test "renders a table with rows and columns" do
      assigns = %{
        __changed__: nil,
        id: "my-table",
        rows: [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}],
        row_id: nil,
        row_click: nil,
        row_item: &Function.identity/1,
        col: [
          %{__slot__: :col, label: "ID", inner_block: fn _, row -> "#{row.id}" end},
          %{__slot__: :col, label: "Nombre", inner_block: fn _, row -> row.name end}
        ],
        action: []
      }

      rendered = assigns |> CRCWeb.CoreComponents.table() |> exec()
      assert is_struct(rendered, Phoenix.LiveView.Rendered)
    end

    test "renders a table with actions column" do
      assigns = %{
        __changed__: nil,
        id: "action-table",
        rows: [%{id: 1, name: "Alice"}],
        row_id: fn row -> "row-#{row.id}" end,
        row_click: nil,
        row_item: &Function.identity/1,
        col: [
          %{__slot__: :col, label: "Nombre", inner_block: fn _, row -> row.name end}
        ],
        action: [
          %{__slot__: :action, inner_block: fn _, _row -> "Editar" end}
        ]
      }

      rendered = assigns |> CRCWeb.CoreComponents.table() |> exec()
      assert is_struct(rendered, Phoenix.LiveView.Rendered)
    end

    test "renders a table with empty rows" do
      assigns = %{
        __changed__: nil,
        id: "empty-table",
        rows: [],
        row_id: nil,
        row_click: nil,
        row_item: &Function.identity/1,
        col: [%{__slot__: :col, label: "Col", inner_block: fn _, _ -> "" end}],
        action: []
      }

      rendered = assigns |> CRCWeb.CoreComponents.table() |> exec()
      assert is_struct(rendered, Phoenix.LiveView.Rendered)
    end
  end

  # ---------------------------------------------------------------------------
  # list/1
  # ---------------------------------------------------------------------------

  describe "list/1" do
    test "renders a data list" do
      assigns = %{
        __changed__: nil,
        item: [
          %{__slot__: :item, title: "Nombre", inner_block: fn _, _ -> "Alice" end},
          %{__slot__: :item, title: "Email", inner_block: fn _, _ -> "alice@example.com" end}
        ]
      }

      rendered = assigns |> CRCWeb.CoreComponents.list() |> exec()
      assert is_struct(rendered, Phoenix.LiveView.Rendered)
    end
  end

  # ---------------------------------------------------------------------------
  # translate_error/1 — ngettext (count) branch
  # ---------------------------------------------------------------------------

  describe "translate_error/1" do
    test "translates an error with count (ngettext branch)" do
      result = CRCWeb.CoreComponents.translate_error({"must be at least %{count} characters", [count: 5]})
      assert is_binary(result)
    end

    test "translates an error without count (dgettext branch)" do
      result = CRCWeb.CoreComponents.translate_error({"can't be blank", []})
      assert is_binary(result)
    end
  end

  # ---------------------------------------------------------------------------
  # translate_errors/2
  # ---------------------------------------------------------------------------

  describe "translate_errors/2" do
    test "translates errors for a specific field" do
      errors = [name: {"can't be blank", [validation: :required]}]
      result = CRCWeb.CoreComponents.translate_errors(errors, :name)
      assert is_list(result)
    end
  end
end
