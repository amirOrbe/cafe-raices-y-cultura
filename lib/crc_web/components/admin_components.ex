defmodule CRCWeb.AdminComponents do
  @moduledoc """
  Shared UI building blocks for the `/admin` panel.

  These components exist because every admin `LiveView` was hand-rolling the
  same Tailwind/daisyUI markup (a card, a stat card, a modal, a table header
  row, a period filter) with small, accidental variations — three different
  "stat card" paddings, for example. Centralizing them here means the visual
  language is tunable in one place, and migrating a page to use them is a
  mechanical find-and-replace rather than a redesign.

  Imported automatically wherever `CRCWeb.CoreComponents` is (see
  `CRCWeb.html_helpers/0`), so no per-file import is needed.
  """
  use Phoenix.Component

  import CRCWeb.CoreComponents, only: [icon: 1]

  @doc """
  A card/panel — the `"bg-base-100 rounded-2xl border border-base-300 shadow-sm"`
  wrapper repeated across every admin page.

  ## Examples

      <.panel class="p-5">
        ...
      </.panel>
  """
  attr :class, :any, default: nil
  attr :rest, :global

  slot :inner_block, required: true

  def panel(assigns) do
    ~H"""
    <div class={["bg-base-100 rounded-2xl border border-base-300 shadow-sm", @class]} {@rest}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  A single stat/metric card: icon-in-colored-circle + value + label, with an
  optional sublabel (e.g. "Margen 79.9%" under a gross-profit value).

  Unifies what used to be three near-identical private components
  (`dashboard_live.ex`'s `stat_card/1`, `ventas_live.ex`'s `stat_card/1`, and
  `finanzas_live.ex`'s `fin_card/1`).

  ## Examples

      <.stat_card label="Ingresos" value="$209,146.25" icon="hero-banknotes" variant={:success} />
      <.stat_card label="Ganancia bruta" value="$167,051.59" icon="hero-arrow-trending-up" sublabel="Margen 79.9%" />
  """
  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :icon, :string, required: true

  attr :variant, :atom,
    default: :primary,
    values: [:primary, :secondary, :accent, :success, :error, :warning, :info]

  attr :sublabel, :string, default: nil
  attr :class, :any, default: nil

  def stat_card(assigns) do
    ~H"""
    <.panel class={["p-3 sm:p-4 flex items-center gap-3", @class]}>
      <div class={["size-10 rounded-xl flex items-center justify-center shrink-0", bg_class(@variant)]}>
        <.icon name={@icon} class={"size-5 #{text_class(@variant)}"} />
      </div>
      <div class="min-w-0">
        <p class="text-lg sm:text-xl font-bold text-base-content leading-none truncate">{@value}</p>
        <p class="text-xs text-base-content/50 mt-0.5 leading-tight truncate">{@label}</p>
        <p :if={@sublabel} class="text-xs text-base-content/40 leading-tight truncate">{@sublabel}</p>
      </div>
    </.panel>
    """
  end

  @doc """
  A compact inline stat (icon + value + label, no card wrapper) — for dense
  summary rows where a full `stat_card/1` would be too heavy. Lifted from
  `dashboard_live.ex`'s `mini_stat/1`.

  ## Examples

      <.mini_stat label="Activos" value={10} icon="hero-check-circle" color="text-success" />
  """
  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :icon, :string, required: true
  attr :color, :string, required: true

  def mini_stat(assigns) do
    ~H"""
    <div class="flex items-center gap-2">
      <.icon name={@icon} class={"size-4 shrink-0 #{@color}"} />
      <div>
        <p class="text-base font-bold text-base-content leading-none">{@value}</p>
        <p class="text-xs text-base-content/40">{@label}</p>
      </div>
    </div>
    """
  end

  @doc """
  A thin wrapper around the `"badge badge-{xs|sm} badge-{variant}"` string
  repeated everywhere status/role indicators appear.

  ## Examples

      <.admin_badge variant={:success}>Activo</.admin_badge>
      <.admin_badge variant={:error} size="xs">Inactivo</.admin_badge>
  """
  attr :variant, :atom,
    default: :ghost,
    values: [:primary, :secondary, :accent, :success, :error, :warning, :info, :ghost, :outline]

  attr :size, :string, default: "sm", values: ~w(xs sm)
  attr :class, :any, default: nil

  slot :inner_block, required: true

  def admin_badge(assigns) do
    ~H"""
    <span class={["badge", "badge-#{@size}", "badge-#{@variant}", @class]}>
      {render_slot(@inner_block)}
    </span>
    """
  end

  @doc """
  Consolidates the modal root/overlay/panel/header markup repeated in every
  admin `*_live.ex` file. Rendered conditionally by the caller (e.g.
  `<%= if @form do %><.admin_modal ...><% end %>`) — closing is a server
  round-trip via `on_close`, matching the existing modal pattern across the
  admin panel (not a client-side `JS.hide`).

  ## Examples

      <.admin_modal id="user-modal" on_close="close_modal">
        <:title>Nuevo usuario</:title>
        <.form ...>...</.form>
      </.admin_modal>
  """
  attr :id, :string, required: true
  attr :size, :string, default: "md", values: ~w(sm md lg xl 2xl)
  attr :on_close, :string, required: true

  slot :title, required: true
  slot :inner_block, required: true

  def admin_modal(assigns) do
    ~H"""
    <div
      id={@id}
      class="fixed inset-0 z-50 flex items-center justify-center p-2 sm:p-4"
      phx-window-keydown={@on_close}
      phx-key="Escape"
    >
      <div class="absolute inset-0 bg-black/50 backdrop-blur-sm" phx-click={@on_close}></div>

      <div class={[
        "relative bg-base-100 rounded-2xl shadow-2xl w-full overflow-y-auto max-h-[90vh]",
        modal_max_width(@size)
      ]}>
        <div class="px-6 py-4 border-b border-base-300 flex items-center justify-between sticky top-0 bg-base-100 z-10">
          <h2 class="text-lg font-semibold text-base-content">{render_slot(@title)}</h2>
          <button class="btn btn-ghost btn-sm btn-circle" phx-click={@on_close}>
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>

        <div class="px-6 py-5">
          {render_slot(@inner_block)}
        </div>
      </div>
    </div>
    """
  end

  @doc """
  The `"bg-base-200 text-xs font-semibold text-base-content/60 uppercase
  tracking-wider"` header row shared by every admin desktop table. Columns
  are passed as a `:col` slot so callers keep full control of the raw
  `<table>`/`<tbody>` markup (and the mobile-card/desktop-table dual layout
  CLAUDE.md already requires).

  ## Examples

      <table class="table table-zebra table-fixed w-full">
        <.admin_table_head>
          <:col class="w-[30%]">Nombre</:col>
          <:col class="w-[20%] text-right">Acciones</:col>
        </.admin_table_head>
        <tbody>...</tbody>
      </table>
  """
  slot :col, required: true do
    attr :class, :string
  end

  def admin_table_head(assigns) do
    ~H"""
    <thead>
      <tr class="bg-base-200 text-xs font-semibold text-base-content/60 uppercase tracking-wider">
        <th :for={col <- @col} class={col[:class]}>{render_slot(col)}</th>
      </tr>
    </thead>
    """
  end

  @doc """
  The "Hoy / Semana / Mes / Año / Total + rango personalizado" filter block
  duplicated byte-for-byte across `finanzas_live.ex`, `ventas_live.ex`, and
  `rendimiento_live.ex`. Emits `"set_period"` (with a `"period"` param of
  `"today"|"week"|"month"|"year"|"all"`) and `"set_date_range"` (with `"date_from"`/
  `"date_to"` params) — callers keep their existing `handle_event` clauses
  for both, so adopting this component doesn't change any LiveView's event
  handling, only its markup.

  ## Examples

      <.period_filter period={@period} date_from={@date_from} date_to={@date_to} />
  """
  attr :period, :any, required: true
  attr :date_from, :string, default: ""
  attr :date_to, :string, default: ""
  attr :on_period, :string, default: "set_period"
  attr :on_range, :string, default: "set_date_range"

  def period_filter(assigns) do
    ~H"""
    <div class="flex flex-col sm:flex-row sm:flex-wrap sm:items-center gap-3">
      <div class="join flex-wrap">
        <button
          :for={
            {label, value} <- [
              {"Hoy", "today"},
              {"Esta semana", "week"},
              {"Este mes", "month"},
              {"Este año", "year"},
              {"Total", "all"}
            ]
          }
          class={[
            "btn btn-sm join-item",
            if(@period == String.to_atom(value), do: "btn-primary", else: "btn-ghost")
          ]}
          phx-click={@on_period}
          phx-value-period={value}
        >
          {label}
        </button>
      </div>

      <form phx-change={@on_range} class="flex flex-wrap items-center gap-2">
        <label class="text-xs text-base-content/50 uppercase tracking-wider whitespace-nowrap">
          Rango personalizado
        </label>
        <input
          type="date"
          name="date_from"
          value={@date_from}
          class="input input-bordered input-sm w-full sm:w-auto"
        />
        <span class="text-base-content/40">–</span>
        <input
          type="date"
          name="date_to"
          value={@date_to}
          class="input input-bordered input-sm w-full sm:w-auto"
        />
      </form>
    </div>
    """
  end

  @doc """
  A navigation card — icon + label — used to build the card grid on
  `/admin` that replaced the persistent sidebar. Grouped by `nav_sections/0`.

  ## Examples

      <.nav_card path="/admin/platillos" label="Platillos" icon="hero-clipboard-document-list" />
  """
  attr :path, :string, required: true
  attr :label, :string, required: true
  attr :icon, :string, required: true

  def nav_card(assigns) do
    ~H"""
    <.link navigate={@path} class="block">
      <.panel class="p-4 flex flex-col items-center gap-2 text-center hover:border-primary/40 hover:shadow-md transition-all">
        <div class="size-11 rounded-xl bg-primary/10 flex items-center justify-center">
          <.icon name={@icon} class="size-5 text-primary" />
        </div>
        <p class="text-sm font-medium text-base-content leading-tight">{@label}</p>
      </.panel>
    </.link>
    """
  end

  @doc """
  The full list of admin destinations, grouped by area — the data behind the
  `/admin` card grid (moved here from `CRCWeb.Layouts` once the sidebar it
  used to feed was replaced by that grid; `nav_card/1` is its renderer).
  """
  def nav_sections do
    [
      %{
        label: "Clientes",
        items: [
          %{path: "/admin/clientes", label: "Clientes", icon: "hero-identification"},
          %{path: "/admin/lealtad", label: "Lealtad", icon: "hero-ticket"}
        ]
      },
      %{
        label: "Carta y Menú",
        items: [
          %{path: "/admin/platillos", label: "Platillos", icon: "hero-clipboard-document-list"},
          %{
            path: "/admin/platillos/categorias",
            label: "Categorías de platillos",
            icon: "hero-squares-2x2"
          },
          %{path: "/admin/paquetes", label: "Paquetes", icon: "hero-gift"}
        ]
      },
      %{
        label: "Inventario",
        items: [
          %{
            path: "/admin/inventario",
            label: "Inventario (stock)",
            icon: "hero-clipboard-document-list"
          },
          %{path: "/admin/proveedores", label: "Proveedores", icon: "hero-truck"},
          %{path: "/admin/insumos", label: "Insumos", icon: "hero-archive-box"},
          %{
            path: "/admin/insumos/categorias",
            label: "Categorías de insumos",
            icon: "hero-tag"
          },
          %{path: "/admin/insumos/merma", label: "Merma", icon: "hero-trash"},
          %{path: "/admin/produccion", label: "Producción Interna", icon: "hero-beaker"}
        ]
      },
      %{
        label: "Operaciones del local",
        items: [
          %{path: "/admin/mesas", label: "Mesas", icon: "hero-table-cells"},
          %{path: "/admin/descuentos", label: "Descuentos", icon: "hero-tag"}
        ]
      },
      %{
        label: "Eventos y Colaboraciones",
        items: [
          %{path: "/admin/eventos", label: "Eventos", icon: "hero-calendar"},
          %{path: "/admin/colaboradores", label: "Colaboradores", icon: "hero-user-group"},
          %{path: "/admin/eventos/tipos", label: "Tipos de evento", icon: "hero-tag"}
        ]
      },
      %{
        label: "Reportes y Finanzas",
        items: [
          %{path: "/admin/finanzas", label: "Finanzas", icon: "hero-scale"},
          %{path: "/admin/ventas", label: "Ventas", icon: "hero-chart-bar"},
          %{path: "/admin/ventas/manual", label: "Venta manual", icon: "hero-plus-circle"},
          %{path: "/admin/rendimiento", label: "Rendimiento", icon: "hero-clock"}
        ]
      },
      %{
        label: "Personal",
        items: [
          %{path: "/admin/usuarios", label: "Usuarios", icon: "hero-users"},
          %{path: "/admin/horarios", label: "Horarios", icon: "hero-calendar-days"},
          %{path: "/admin/asistencia", label: "Asistencia", icon: "hero-finger-print"},
          %{
            path: "/admin/calendario",
            label: "Calendario de actividades",
            icon: "hero-calendar"
          },
          %{path: "/admin/cumpleanos", label: "Cumpleaños", icon: "hero-cake"}
        ]
      },
      %{
        label: "Sistema",
        items: [
          %{path: "/admin/configuracion", label: "Configuración", icon: "hero-cog-6-tooth"}
        ]
      }
    ]
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp modal_max_width("sm"), do: "max-w-sm"
  defp modal_max_width("md"), do: "max-w-md"
  defp modal_max_width("lg"), do: "max-w-lg"
  defp modal_max_width("xl"), do: "max-w-xl"
  defp modal_max_width("2xl"), do: "max-w-2xl"

  defp bg_class(:primary), do: "bg-primary/10"
  defp bg_class(:secondary), do: "bg-secondary/10"
  defp bg_class(:accent), do: "bg-accent/10"
  defp bg_class(:success), do: "bg-success/10"
  defp bg_class(:error), do: "bg-error/10"
  defp bg_class(:warning), do: "bg-warning/10"
  defp bg_class(:info), do: "bg-info/10"

  defp text_class(:primary), do: "text-primary"
  defp text_class(:secondary), do: "text-secondary"
  defp text_class(:accent), do: "text-accent"
  defp text_class(:success), do: "text-success"
  defp text_class(:error), do: "text-error"
  defp text_class(:warning), do: "text-warning"
  defp text_class(:info), do: "text-info"
end
