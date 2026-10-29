defmodule CRCWeb.Components.StationComponents do
  @moduledoc """
  Shared pieces of the barra and cocina screens. These run on tablets and
  phones, often in the hands of staff who only help for one event, so every
  piece names the exact buttons on screen and keeps touch targets ≥ 44px.
  """

  use Phoenix.Component

  import CRCWeb.CoreComponents, only: [icon: 1]

  @doc """
  The three-step "how this works" strip. Always visible (it is one line on a
  tablet): temporary staff rotate, so there is nothing to dismiss and forget.
  """
  attr :steps, :list,
    required: true,
    doc: "list of {before, button_name, after} — the button name is shown in bold"

  def how_to(assigns) do
    ~H"""
    <ol class="flex flex-col sm:flex-row sm:flex-wrap gap-x-6 gap-y-2 text-sm text-base-content/80">
      <%= for {{before, button, rest}, n} <- Enum.with_index(@steps, 1) do %>
        <li class="flex items-center gap-2">
          <span class="shrink-0 size-6 rounded-full bg-primary/15 text-primary text-xs font-bold flex items-center justify-center">
            {n}
          </span>
          <span>{before} <strong class="text-base-content">{button}</strong> {rest}</span>
        </li>
      <% end %>
    </ol>
    """
  end

  @doc """
  Tablets block audio until someone touches the page. This button says so,
  plays the alert once as a sample, and the SoundNotifier hook hides it on the
  first touch anywhere.
  """
  def sound_hint(assigns) do
    ~H"""
    <%!-- phx-update="ignore": re-renders must not undo the hook hiding it --%>
    <button
      id="sound-hint"
      type="button"
      phx-update="ignore"
      class="btn btn-sm btn-outline btn-primary gap-2 min-h-11"
    >
      <.icon name="hero-speaker-wave" class="size-4" /> Toca para activar el sonido
    </button>
    """
  end

  @doc """
  Minutes waited, readable at a glance: "4 min", "3 h", "2 d". Color carries
  urgency only — neutral under 7 min, warning from 7, error (pulsing) from 12.
  """
  attr :mins, :integer, default: nil

  def wait_time(assigns) do
    ~H"""
    <span
      :if={@mins}
      class={[
        "inline-flex items-center gap-1 text-sm font-semibold tabular-nums whitespace-nowrap",
        cond do
          @mins >= 12 -> "text-error motion-safe:animate-pulse"
          @mins >= 7 -> "text-warning"
          true -> "text-base-content/70"
        end
      ]}
      title="Tiempo esperando"
    >
      <.icon name="hero-clock" class="size-4" /> {format_wait(@mins)}
    </span>
    """
  end

  @doc false
  def format_wait(mins) when mins < 60, do: "#{max(mins, 0)} min"
  def format_wait(mins) when mins < 1440, do: "#{div(mins, 60)} h"
  def format_wait(mins), do: "#{div(mins, 1440)} d"

  @doc "Segmented toggle between the per-comanda and per-item views."
  attr :view_mode, :atom, required: true
  attr :grouped_label, :string, required: true

  def view_toggle(assigns) do
    ~H"""
    <div class="grid grid-cols-2 gap-1 bg-base-300/60 rounded-xl p-1 w-full sm:w-auto">
      <button
        class={[
          "btn btn-sm min-h-11 gap-1.5 border-0",
          if(@view_mode == :by_order, do: "btn-primary", else: "btn-ghost")
        ]}
        phx-click="set_view_mode"
        phx-value-mode="by_order"
        aria-pressed={to_string(@view_mode == :by_order)}
      >
        <.icon name="hero-squares-2x2" class="size-4" /> Por comanda
      </button>
      <button
        class={[
          "btn btn-sm min-h-11 gap-1.5 border-0",
          if(@view_mode == :grouped, do: "btn-primary", else: "btn-ghost")
        ]}
        phx-click="set_view_mode"
        phx-value-mode="grouped"
        aria-pressed={to_string(@view_mode == :grouped)}
      >
        <.icon name="hero-queue-list" class="size-4" /> {@grouped_label}
      </button>
    </div>
    """
  end

  @doc "Per-item ready button, sized for fingers."
  attr :id, :integer, required: true

  def ready_button(assigns) do
    ~H"""
    <button
      class="btn btn-sm btn-outline btn-success min-h-11 px-4 shrink-0 gap-1"
      phx-click="mark_item_ready"
      phx-value-id={@id}
    >
      <.icon name="hero-check" class="size-4" /> Listo
    </button>
    """
  end

  @doc """
  Variants, exclusions, who it is for, and notes — the details staff must not
  miss. Exclusions and notes get color because they change what gets made.
  """
  attr :item, :map, required: true
  attr :order, :map, required: true
  attr :show_person, :boolean, default: true

  def item_details(assigns) do
    assigns =
      assign(
        assigns,
        :variants,
        Enum.filter(assigns.order.order_items, fn oi ->
          not is_nil(oi.variant_id) and oi.for_menu_item_id == assigns.item.menu_item_id
        end)
      )

    ~H"""
    <div :if={@variants != []} class="flex flex-wrap items-center gap-1 mt-1">
      <span :for={vi <- @variants} class="badge badge-sm badge-primary">{vi.variant.name}</span>
    </div>
    <div :if={@item.exclusions != []} class="flex flex-wrap items-center gap-1 mt-1">
      <span class="text-sm font-bold text-error shrink-0">Sin:</span>
      <span :for={excl <- @item.exclusions} class="badge badge-sm badge-error">
        {excl.product.name}
      </span>
    </div>
    <p
      :if={@show_person && @item.for_person && @item.for_person != ""}
      class="flex items-center gap-1 mt-1 text-sm text-base-content/70"
    >
      <.icon name="hero-user" class="size-3.5 shrink-0" /> {@item.for_person}
    </p>
    <p
      :if={@item.notes && @item.notes != ""}
      class="flex items-start gap-1 mt-1 bg-warning/15 rounded-md px-2 py-1 text-sm font-semibold text-warning-content"
    >
      <.icon name="hero-pencil-square" class="size-4 shrink-0 mt-0.5" /> {@item.notes}
    </p>
    """
  end
end
