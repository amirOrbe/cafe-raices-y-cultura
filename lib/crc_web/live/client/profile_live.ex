defmodule CRCWeb.Client.ProfileLive do
  use CRCWeb, :live_view

  alias CRC.Accounts
  alias CRC.Accounts.User
  alias CRCWeb.Components.SiteComponents

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
       editing: false,
       nav_open: false
     )}
  end

  @impl true
  def handle_event("edit", _params, socket) do
    {:noreply, assign(socket, editing: true)}
  end

  def handle_event("toggle_nav", _params, socket) do
    {:noreply, assign(socket, :nav_open, !socket.assigns.nav_open)}
  end

  def handle_event("close_nav", _params, socket) do
    {:noreply, assign(socket, :nav_open, false)}
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
    <div class="min-h-screen flex flex-col bg-base-200">
      <SiteComponents.site_navbar
        nav_open={@nav_open}
        current_page={:perfil}
        current_user={@current_user}
      />

      <main class="flex-1 w-full max-w-2xl mx-auto px-4 py-8 space-y-5">
        <%!-- Identity card --%>
        <div class="card bg-base-100 shadow-sm">
          <div class="card-body flex-row items-center gap-5">
            <div class="w-16 h-16 rounded-full bg-primary text-primary-content flex items-center justify-center text-2xl font-bold shrink-0">
              {String.first(@current_user.name || "?") |> String.upcase()}
            </div>
            <div class="min-w-0">
              <p class="text-xl font-bold text-base-content truncate">{@current_user.name}</p>
              <p class="text-sm text-base-content/60 truncate">{@current_user.email}</p>
              <span
                :if={@current_user.confirmed_at}
                class="badge badge-success badge-sm mt-1 gap-1"
              >
                <.icon name="hero-check-badge" class="size-3" /> Verificado
              </span>
            </div>
          </div>
        </div>

        <%!-- QR + Loyalty side by side on md+ --%>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-5">
          <%!-- QR card --%>
          <div class="card bg-base-100 shadow-sm">
            <div class="card-body items-center text-center">
              <h2 class="card-title text-primary text-base">Mi código QR</h2>
              <div class="my-2">
                {Phoenix.HTML.raw(render_qr(@current_user.qr_token))}
              </div>
              <p class="text-xs text-base-content/50">
                Muéstralo en caja para acumular visitas
              </p>
            </div>
          </div>

          <%!-- Loyalty card --%>
          <div class="card bg-base-100 shadow-sm">
            <div class="card-body">
              <h2 class="card-title text-primary text-base">Tarjeta de lealtad</h2>
              <div class="grid grid-cols-5 gap-2 my-2">
                <div
                  :for={i <- 1..10}
                  class={[
                    "aspect-square rounded-full flex items-center justify-center text-lg",
                    stamp_filled?(@visit_count, i) && "bg-accent/20 text-accent",
                    !stamp_filled?(@visit_count, i) &&
                      "border-2 border-dashed border-base-300 text-base-content/20"
                  ]}
                >
                  <span :if={stamp_filled?(@visit_count, i)}>☕</span>
                </div>
              </div>
              <p class="text-sm text-base-content/60">
                Visitas totales:
                <span class="font-bold text-primary text-lg ml-1">{@visit_count}</span>
              </p>
              <p class="text-xs text-base-content/40">Cada 10 visitas completas = recompensa</p>
            </div>
          </div>
        </div>

        <%!-- Personal data --%>
        <div class="card bg-base-100 shadow-sm">
          <div class="card-body">
            <div class="flex items-center justify-between">
              <h2 class="card-title text-primary text-base">Datos personales</h2>
              <button
                :if={!@editing}
                type="button"
                phx-click="edit"
                class="btn btn-outline btn-primary btn-sm"
              >
                Editar
              </button>
            </div>

            <div :if={!@editing} class="grid grid-cols-1 sm:grid-cols-2 gap-4 mt-2">
              <div>
                <p class="text-xs text-base-content/50 uppercase tracking-wide">Nombre</p>
                <p class="font-medium mt-0.5">{@current_user.name}</p>
              </div>
              <div>
                <p class="text-xs text-base-content/50 uppercase tracking-wide">Correo</p>
                <p class="font-medium mt-0.5 truncate">{@current_user.email}</p>
              </div>
              <div>
                <p class="text-xs text-base-content/50 uppercase tracking-wide">Teléfono</p>
                <p class="font-medium mt-0.5">{@current_user.phone || "—"}</p>
              </div>
              <div>
                <p class="text-xs text-base-content/50 uppercase tracking-wide">Cumpleaños</p>
                <p class="font-medium mt-0.5">{@current_user.birthday || "—"}</p>
              </div>
            </div>

            <.form
              :if={@editing}
              for={@form}
              phx-change="validate"
              phx-submit="save"
              class="grid grid-cols-1 sm:grid-cols-2 gap-4 mt-2"
            >
              <div class="sm:col-span-2">
                <.input field={@form[:name]} type="text" label="Nombre completo" />
              </div>
              <.input
                field={@form[:phone]}
                type="tel"
                label="Teléfono"
                placeholder="+52 55 0000 0000"
              />
              <.input field={@form[:birthday]} type="date" label="Fecha de nacimiento" />
              <div class="sm:col-span-2 flex gap-2 pt-1">
                <button type="submit" class="btn btn-primary flex-1">Guardar</button>
                <button type="button" phx-click="cancel_edit" class="btn btn-ghost flex-1">
                  Cancelar
                </button>
              </div>
            </.form>
          </div>
        </div>

        <%!-- Quick actions --%>
        <div class="card bg-base-100 shadow-sm">
          <div class="card-body">
            <h2 class="card-title text-primary text-base">Acciones rápidas</h2>
            <div class="flex flex-wrap gap-3 mt-1">
              <.link navigate="/cliente/pedidos" class="btn btn-outline btn-sm">
                <.icon name="hero-shopping-bag" class="size-4" /> Mis pedidos
              </.link>
              <.link navigate="/menu" class="btn btn-outline btn-sm">
                <.icon name="hero-book-open" class="size-4" /> Ver menú
              </.link>
            </div>
          </div>
        </div>
      </main>

      <SiteComponents.site_footer />
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
