defmodule CRCWeb.Admin.LealtadLive do
  @moduledoc "Configuración del programa de lealtad: niveles por visitas + beneficio de cumpleaños."

  use CRCWeb, :live_view

  alias CRC.Catalog
  alias CRC.CRM
  alias CRC.CRM.LoyaltyReward

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Lealtad · Admin")
      |> assign(:menu_item_options, menu_item_options())
      |> assign(:modal, nil)
      |> assign(:form, nil)
      |> load_data()

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # Visit tiers
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("new_tier", _params, socket) do
    changeset = CRM.change_reward(%LoyaltyReward{kind: "visits", repeatable: true, active: true})

    {:noreply, socket |> assign(:modal, :new) |> assign(:form, to_form(changeset, id: "tier"))}
  end

  def handle_event("edit_tier", %{"id" => id}, socket) do
    tier = CRM.get_reward!(String.to_integer(id))

    {:noreply,
     socket
     |> assign(:modal, {:edit, tier})
     |> assign(:form, to_form(CRM.change_reward(tier), id: "tier"))}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, modal: nil, form: nil)}
  end

  def handle_event("validate_tier", %{"loyalty_reward" => params}, socket) do
    changeset =
      %LoyaltyReward{kind: "visits"}
      |> CRM.change_reward(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, id: "tier"))}
  end

  def handle_event("save_tier", %{"loyalty_reward" => params}, socket) do
    params = Map.put(params, "kind", "visits")

    result =
      case socket.assigns.modal do
        :new -> CRM.create_reward(params)
        {:edit, tier} -> CRM.update_reward(tier, params)
      end

    case result do
      {:ok, _} ->
        label = if socket.assigns.modal == :new, do: "creado", else: "actualizado"

        {:noreply,
         socket
         |> put_flash(:info, "Nivel #{label} correctamente.")
         |> assign(modal: nil, form: nil)
         |> load_data()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, id: "tier"))}
    end
  end

  def handle_event("toggle_tier", %{"id" => id}, socket) do
    tier = CRM.get_reward!(String.to_integer(id))

    case CRM.update_reward(tier, %{active: !tier.active}) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Nivel actualizado.") |> load_data()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "No se pudo actualizar el nivel.")}
    end
  end

  def handle_event("delete_tier", %{"id" => id}, socket) do
    tier = CRM.get_reward!(String.to_integer(id))

    case CRM.delete_reward(tier) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Nivel eliminado.") |> load_data()}

      {:error, _} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "No se pudo eliminar: hay recompensas otorgadas con este nivel. Desactívalo en su lugar."
         )}
    end
  end

  # ---------------------------------------------------------------------------
  # Birthday config
  # ---------------------------------------------------------------------------

  def handle_event("validate_birthday", %{"loyalty_reward" => params}, socket) do
    changeset =
      socket.assigns.birthday_record
      |> CRM.change_reward(Map.put(params, "kind", "birthday"))
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :birthday_form, to_form(changeset, id: "birthday"))}
  end

  def handle_event("save_birthday", %{"loyalty_reward" => params}, socket) do
    params = Map.put(params, "kind", "birthday")
    record = socket.assigns.birthday_record

    result =
      if record.id, do: CRM.update_reward(record, params), else: CRM.create_reward(params)

    case result do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Beneficio de cumpleaños guardado.")
         |> load_data()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :birthday_form, to_form(changeset, id: "birthday"))}
    end
  end

  # ---------------------------------------------------------------------------
  # Data
  # ---------------------------------------------------------------------------

  defp load_data(socket) do
    tiers = CRM.list_reward_tiers(kind: "visits")
    birthday = CRM.get_birthday_reward() || %LoyaltyReward{kind: "birthday", active: false}

    socket
    |> assign(:tiers, tiers)
    |> assign(:birthday_record, birthday)
    |> assign(:birthday_form, to_form(CRM.change_reward(birthday), id: "birthday"))
  end

  defp menu_item_options do
    [{"— Sin platillo asociado —", ""}] ++
      Enum.map(Catalog.list_menu_items(), &{&1.name, &1.id})
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-8 max-w-4xl">
      <div>
        <h1 class="text-2xl font-bold text-base-content">Lealtad</h1>
        <p class="text-sm text-base-content/50 mt-0.5">
          Define cuántas visitas dan un beneficio y qué se regala. Al cerrar una comanda
          asociada a un cliente se cuenta una visita.
        </p>
      </div>

      <%!-- ── Niveles por visitas ─────────────────────────────────────────── --%>
      <section class="space-y-3">
        <div class="flex items-center justify-between flex-wrap gap-3">
          <h2 class="text-lg font-semibold text-base-content">Niveles por visitas</h2>
          <button id="btn-new-tier" class="btn btn-primary btn-sm gap-2" phx-click="new_tier">
            <.icon name="hero-plus" class="size-4" /> Nuevo nivel
          </button>
        </div>

        <%= if @tiers == [] do %>
          <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm py-12 text-center">
            <.icon name="hero-ticket" class="size-9 text-base-content/20 mx-auto mb-2" />
            <p class="text-base-content/50 text-sm">
              Aún no hay niveles. Crea uno, por ejemplo "6 visitas → Café gratis".
            </p>
          </div>
        <% else %>
          <div class="md:hidden flex flex-col gap-2">
            <%= for t <- @tiers do %>
              <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm p-3">
                <div class="flex items-start gap-3">
                  <div class="flex flex-col items-center justify-center w-12 h-12 rounded-xl bg-primary/10 shrink-0">
                    <span class="font-bold text-primary text-base leading-none">
                      {t.visits_required}
                    </span>
                    <span class="text-[10px] text-primary/70">visitas</span>
                  </div>
                  <div class="flex-1 min-w-0">
                    <div class="flex items-center gap-2 flex-wrap">
                      <p class="font-semibold text-sm text-base-content truncate">{t.name}</p>
                      <.active_badge active={t.active} />
                    </div>
                    <p class="text-xs text-base-content/60 mt-0.5">🎁 {t.benefit}</p>
                    <p class="text-[11px] text-base-content/40 mt-0.5">
                      {if t.repeatable,
                        do: "Se repite cada #{t.visits_required} visitas",
                        else: "Una sola vez"}
                    </p>
                  </div>
                  <div class="flex flex-col gap-1 shrink-0">
                    <.row_actions id={t.id} active={t.active} target="tier" scope="m" />
                  </div>
                </div>
              </div>
            <% end %>
          </div>

          <div class="hidden md:block bg-base-100 rounded-2xl border border-base-300 shadow-sm overflow-hidden">
            <table class="table table-zebra table-fixed w-full">
              <thead>
                <tr class="bg-base-200 text-xs font-semibold text-base-content/60 uppercase tracking-wider">
                  <th class="w-[14%] text-center">Visitas</th>
                  <th class="w-[24%]">Nombre</th>
                  <th class="w-[28%]">Beneficio</th>
                  <th class="w-[18%]">Repetición</th>
                  <th class="w-[16%] text-right">Acciones</th>
                </tr>
              </thead>
              <tbody>
                <%= for t <- @tiers do %>
                  <tr class="hover:bg-base-200/50 transition-colors">
                    <td class="text-center">
                      <span class="badge badge-primary badge-sm">{t.visits_required}</span>
                    </td>
                    <td class="font-medium text-sm text-base-content">
                      {t.name}
                      <.active_badge :if={not t.active} active={t.active} />
                    </td>
                    <td class="text-sm text-base-content/70">🎁 {t.benefit}</td>
                    <td class="text-sm text-base-content/60">
                      {if t.repeatable, do: "Cada #{t.visits_required} visitas", else: "Una sola vez"}
                    </td>
                    <td>
                      <div class="flex items-center justify-end gap-1">
                        <.row_actions id={t.id} active={t.active} target="tier" scope="d" />
                      </div>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        <% end %>
      </section>

      <%!-- ── Beneficio de cumpleaños ─────────────────────────────────────── --%>
      <section class="space-y-3">
        <h2 class="text-lg font-semibold text-base-content">Beneficio de cumpleaños</h2>
        <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm p-5">
          <.form
            id="birthday-form"
            for={@birthday_form}
            phx-change="validate_birthday"
            phx-submit="save_birthday"
            class="space-y-4"
          >
            <label class="flex items-center gap-3 cursor-pointer">
              <input type="hidden" name="loyalty_reward[active]" value="false" />
              <input
                type="checkbox"
                name="loyalty_reward[active]"
                value="true"
                checked={Phoenix.HTML.Form.normalize_value("checkbox", @birthday_form[:active].value)}
                class="checkbox checkbox-primary"
              />
              <span class="text-sm font-medium text-base-content">
                Activar beneficio de cumpleaños
              </span>
            </label>

            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <.input
                field={@birthday_form[:name]}
                type="text"
                label="Nombre"
                placeholder="Cumpleaños"
              />
              <.input
                field={@birthday_form[:benefit]}
                type="text"
                label="Beneficio"
                placeholder="Ej. Rebanada de pastel gratis"
              />
              <.input
                field={@birthday_form[:benefit_menu_item_id]}
                type="select"
                label="Platillo de cortesía (opcional)"
                options={@menu_item_options}
              />
              <.input
                field={@birthday_form[:birthday_window_days]}
                type="number"
                label="Días de margen"
                min="0"
                max="30"
              />
            </div>
            <p class="text-xs text-base-content/40">
              Con 0 días el beneficio solo aparece el día exacto del cumpleaños. Con margen,
              el personal lo puede dar los días siguientes.
            </p>

            <div class="flex justify-end">
              <button type="submit" class="btn btn-primary">Guardar</button>
            </div>
          </.form>
        </div>
      </section>
    </div>

    <%= if @modal != nil do %>
      <.tier_modal form={@form} modal={@modal} menu_item_options={@menu_item_options} />
    <% end %>
    """
  end

  # ---------------------------------------------------------------------------
  # Components
  # ---------------------------------------------------------------------------

  attr :id, :integer, required: true
  attr :active, :boolean, required: true
  attr :target, :string, required: true
  attr :scope, :string, default: "d"

  defp row_actions(assigns) do
    ~H"""
    <button
      id={"btn-edit-#{@target}-#{@scope}-#{@id}"}
      class="btn btn-ghost btn-xs btn-circle"
      phx-click={"edit_#{@target}"}
      phx-value-id={@id}
      title="Editar"
    >
      <.icon name="hero-pencil" class="size-4" />
    </button>
    <button
      class={[
        "btn btn-ghost btn-xs btn-circle",
        if(@active, do: "text-warning", else: "text-success")
      ]}
      phx-click={"toggle_#{@target}"}
      phx-value-id={@id}
      title={if @active, do: "Desactivar", else: "Activar"}
    >
      <.icon name={if @active, do: "hero-eye-slash", else: "hero-eye"} class="size-4" />
    </button>
    <button
      class="btn btn-ghost btn-xs btn-circle text-error"
      phx-click={"delete_#{@target}"}
      phx-value-id={@id}
      title="Eliminar"
      data-confirm="¿Eliminar este nivel? Las recompensas ya otorgadas no se ven afectadas."
    >
      <.icon name="hero-trash" class="size-4" />
    </button>
    """
  end

  defp active_badge(assigns) do
    ~H"""
    <%= if @active do %>
      <span class="badge badge-xs badge-success shrink-0">Activo</span>
    <% else %>
      <span class="badge badge-xs badge-error shrink-0">Inactivo</span>
    <% end %>
    """
  end

  attr :form, :map, required: true
  attr :modal, :any, required: true
  attr :menu_item_options, :list, required: true

  defp tier_modal(assigns) do
    title = if assigns.modal == :new, do: "Nuevo nivel", else: "Editar nivel"
    assigns = assign(assigns, :title, title)

    ~H"""
    <div
      id="tier-modal"
      class="fixed inset-0 z-50 flex items-center justify-center p-4"
      phx-window-keydown="close_modal"
      phx-key="Escape"
    >
      <div class="absolute inset-0 bg-black/50 backdrop-blur-sm" phx-click="close_modal"></div>

      <div class="relative bg-base-100 rounded-2xl shadow-2xl w-full max-w-md overflow-y-auto max-h-[90vh]">
        <div class="px-6 py-4 border-b border-base-300 flex items-center justify-between">
          <h2 class="text-lg font-semibold text-base-content">{@title}</h2>
          <button class="btn btn-ghost btn-sm btn-circle" phx-click="close_modal">
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>

        <div class="px-6 py-5">
          <.form
            id="tier-form"
            for={@form}
            phx-change="validate_tier"
            phx-submit="save_tier"
            class="space-y-4"
          >
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <.input
                field={@form[:visits_required]}
                type="number"
                label="Visitas requeridas"
                min="1"
                placeholder="6"
              />
              <.input
                field={@form[:name]}
                type="text"
                label="Nombre"
                placeholder="Tarjeta de lealtad"
              />
            </div>
            <.input
              field={@form[:benefit]}
              type="text"
              label="Beneficio"
              placeholder="Ej. Café gratis"
            />
            <.input
              field={@form[:benefit_menu_item_id]}
              type="select"
              label="Platillo de cortesía (opcional)"
              options={@menu_item_options}
            />
            <p class="text-xs text-base-content/40 -mt-2">
              Si eliges un platillo, al aplicar la recompensa se agrega esa línea a $0 en la comanda.
            </p>

            <label class="flex items-center gap-3 cursor-pointer">
              <input type="hidden" name="loyalty_reward[repeatable]" value="false" />
              <input
                type="checkbox"
                name="loyalty_reward[repeatable]"
                value="true"
                checked={Phoenix.HTML.Form.normalize_value("checkbox", @form[:repeatable].value)}
                class="checkbox checkbox-primary"
              />
              <span class="text-sm text-base-content">
                Se repite (tarjeta perforada — se vuelve a ganar cada bloque)
              </span>
            </label>

            <label class="flex items-center gap-3 cursor-pointer">
              <input type="hidden" name="loyalty_reward[active]" value="false" />
              <input
                type="checkbox"
                name="loyalty_reward[active]"
                value="true"
                checked={Phoenix.HTML.Form.normalize_value("checkbox", @form[:active].value)}
                class="checkbox checkbox-primary"
              />
              <span class="text-sm text-base-content">Activo</span>
            </label>

            <div class="flex justify-end gap-3 pt-2">
              <button type="button" class="btn btn-ghost" phx-click="close_modal">Cancelar</button>
              <button type="submit" class="btn btn-primary">
                {if @modal == :new, do: "Crear nivel", else: "Guardar cambios"}
              </button>
            </div>
          </.form>
        </div>
      </div>
    </div>
    """
  end
end
