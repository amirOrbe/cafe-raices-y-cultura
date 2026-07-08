defmodule CRCWeb.Client.ProfileLive do
  use CRCWeb, :live_view

  alias CRC.Accounts
  alias CRC.Accounts.User

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    changeset = User.client_profile_changeset(user, %{})
    visit_count = CRC.Loyalty.count_visits(user.id)

    {:ok,
     assign(socket,
       form: to_form(changeset, as: "user"),
       visit_count: visit_count,
       page_title: "Mi perfil",
       editing: false
     )}
  end

  @impl true
  def handle_event("edit", _params, socket) do
    {:noreply, assign(socket, editing: true)}
  end

  def handle_event("cancel_edit", _params, socket) do
    changeset = User.client_profile_changeset(socket.assigns.current_user, %{})
    {:noreply, assign(socket, editing: false, form: to_form(changeset, as: "user"))}
  end

  def handle_event("validate", %{"user" => params}, socket) do
    changeset =
      socket.assigns.current_user
      |> User.client_profile_changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset, as: "user"))}
  end

  def handle_event("save", %{"user" => params}, socket) do
    case Accounts.update_client_profile(socket.assigns.current_user, params) do
      {:ok, user} ->
        changeset = User.client_profile_changeset(user, %{})

        {:noreply,
         socket
         |> assign(
           current_user: user,
           editing: false,
           form: to_form(changeset, as: "user")
         )
         |> put_flash(:info, "Perfil actualizado")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: "user"))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-md mx-auto px-4 py-6">
      <div class="flex items-center justify-between mb-4">
        <h1 class="text-2xl font-bold text-primary">Mi perfil</h1>
        <.link
          href="/cerrar-sesion"
          method="delete"
          class="btn btn-ghost btn-sm text-secondary"
        >
          <.icon name="hero-arrow-right-on-rectangle" class="size-5" /> Cerrar sesión
        </.link>
      </div>

      <div class="card bg-base-100 shadow-sm rounded-2xl p-6 mb-4">
        <div class="flex items-center gap-4">
          <div class="w-16 h-16 rounded-full bg-primary text-primary-content flex items-center justify-center text-2xl font-bold shrink-0">
            {String.first(@current_user.name || "?") |> String.upcase()}
          </div>
          <div class="min-w-0">
            <p class="text-lg font-semibold truncate">{@current_user.name}</p>
            <p class="text-sm text-base-content/70 truncate">{@current_user.email}</p>
            <span
              :if={@current_user.confirmed_at}
              class="badge badge-success badge-sm mt-1 gap-1"
            >
              <.icon name="hero-check-badge" class="size-4" /> Cliente verificado
            </span>
          </div>
        </div>
      </div>

      <div class="card bg-base-100 shadow-sm rounded-2xl p-6 mb-4">
        <h2 class="text-lg font-semibold text-primary mb-4">Mi código QR</h2>
        <div class="flex justify-center">
          {Phoenix.HTML.raw(render_qr(@current_user.qr_token))}
        </div>
        <p class="text-xs text-center text-base-content/60 mt-3">
          Muestra este código en caja para acumular visitas
        </p>
      </div>

      <div class="card bg-base-100 shadow-sm rounded-2xl p-6 mb-4">
        <h2 class="text-lg font-semibold text-primary mb-4">Tarjeta de lealtad</h2>
        <div class="grid grid-cols-5 gap-2">
          <div
            :for={i <- 1..10}
            class={[
              "aspect-square rounded-full flex items-center justify-center text-xl",
              stamp_filled?(@visit_count, i) && "bg-accent/20 text-accent",
              !stamp_filled?(@visit_count, i) && "border-2 border-dashed border-base-300 text-base-content/30"
            ]}
          >
            <span :if={stamp_filled?(@visit_count, i)}>☕</span>
          </div>
        </div>
        <p class="text-sm text-base-content/70 mt-4">
          Visitas totales: <span class="font-semibold text-primary">{@visit_count}</span>
        </p>
      </div>

      <div class="card bg-base-100 shadow-sm rounded-2xl p-6 mb-4">
        <div class="flex items-center justify-between mb-4">
          <h2 class="text-lg font-semibold text-primary">Datos personales</h2>
          <button
            :if={!@editing}
            type="button"
            phx-click="edit"
            class="btn btn-outline btn-primary btn-sm"
          >
            Editar perfil
          </button>
        </div>

        <div :if={!@editing} class="space-y-3">
          <div>
            <p class="text-xs text-base-content/60">Nombre</p>
            <p class="font-medium">{@current_user.name}</p>
          </div>
          <div>
            <p class="text-xs text-base-content/60">Teléfono</p>
            <p class="font-medium">{@current_user.phone || "—"}</p>
          </div>
          <div>
            <p class="text-xs text-base-content/60">Fecha de nacimiento</p>
            <p class="font-medium">{@current_user.birthday || "—"}</p>
          </div>
        </div>

        <.form
          :if={@editing}
          for={@form}
          phx-change="validate"
          phx-submit="save"
          class="space-y-2"
        >
          <.input field={@form[:name]} type="text" label="Nombre" />
          <.input
            field={@form[:phone]}
            type="tel"
            label="Teléfono"
            placeholder="+52 55 0000 0000"
          />
          <.input field={@form[:birthday]} type="date" label="Fecha de nacimiento" />

          <div class="flex gap-2 pt-2">
            <button type="submit" class="btn btn-primary flex-1">Guardar</button>
            <button
              type="button"
              phx-click="cancel_edit"
              class="btn btn-ghost flex-1"
            >
              Cancelar
            </button>
          </div>
        </.form>
      </div>

      <nav class="flex justify-around text-sm mt-6">
        <.link navigate="/" class="text-primary font-medium">Inicio</.link>
        <.link navigate="/menu" class="text-primary font-medium">Menú</.link>
        <.link navigate="/cliente/pedidos" class="text-primary font-medium">Mis pedidos</.link>
      </nav>
    </div>
    """
  end

  defp stamp_filled?(visit_count, index) do
    rem(visit_count, 10) >= index or (visit_count > 0 and rem(visit_count, 10) == 0)
  end

  defp render_qr(qr_token) do
    url = "https://caferaicescultura.cafe/c/#{qr_token}"

    url
    |> EQRCode.encode()
    |> EQRCode.svg(width: 200)
  end
end
