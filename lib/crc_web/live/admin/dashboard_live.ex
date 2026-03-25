defmodule CRCWeb.Admin.DashboardLive do
  @moduledoc "Main administration dashboard."

  use CRCWeb, :live_view

  alias CRC.Accounts
  alias CRC.Inventory

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(CRC.PubSub, "admin:users")
      Phoenix.PubSub.subscribe(CRC.PubSub, "admin:products")
    end

    socket =
      socket
      |> assign(:page_title, "Dashboard · Admin")
      |> load_stats()

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # PubSub
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({event, _payload}, socket) when event in [:user_changed, :product_changed] do
    {:noreply, load_stats(socket)}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp load_stats(socket) do
    users = Accounts.list_users()
    low_stock = length(Inventory.list_low_stock_products())

    stats = %{
      total: length(users),
      admins: Enum.count(users, &(&1.role == "admin")),
      employees: Enum.count(users, &(&1.role == "empleado")),
      active: Enum.count(users, & &1.is_active),
      inactive: Enum.count(users, &(!&1.is_active)),
      low_stock: low_stock
    }

    recent =
      users
      |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
      |> Enum.take(5)

    socket
    |> assign(:stats, stats)
    |> assign(:recent, recent)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <%!-- Header --%>
      <div>
        <h1 class="text-2xl font-bold text-base-content">Dashboard</h1>
        <p class="text-base-content/60 mt-1 text-sm">Bienvenido, {@current_user.name}</p>
      </div>

      <%!-- Stats cards --%>
      <div class="grid grid-cols-2 lg:grid-cols-3 xl:grid-cols-6 gap-4">
        <.stat_card label="Total usuarios" value={@stats.total} icon="hero-users" variant={:primary} />
        <.stat_card label="Admins" value={@stats.admins} icon="hero-shield-check" variant={:secondary} />
        <.stat_card label="Empleados" value={@stats.employees} icon="hero-briefcase" variant={:accent} />
        <.stat_card label="Activos" value={@stats.active} icon="hero-check-circle" variant={:success} />
        <.stat_card label="Inactivos" value={@stats.inactive} icon="hero-x-circle" variant={:error} />
        <.stat_card label="Stock bajo" value={@stats.low_stock} icon="hero-exclamation-triangle" variant={:warning} />
      </div>

      <%!-- Recent users --%>
      <div class="bg-base-100 rounded-2xl shadow-sm border border-base-300 overflow-hidden">
        <div class="px-6 py-4 border-b border-base-300 flex items-center justify-between">
          <h2 class="font-semibold text-base-content">Usuarios recientes</h2>
          <a href="/admin/usuarios" class="btn btn-sm btn-ghost text-primary">Ver todos</a>
        </div>
        <div class="divide-y divide-base-200">
          <%= for user <- @recent do %>
            <div class="px-6 py-4 flex items-center justify-between gap-4">
              <div class="flex items-center gap-3 min-w-0">
                <div class="size-9 rounded-full bg-primary/10 flex items-center justify-center flex-shrink-0">
                  <span class="text-primary font-semibold text-sm">
                    {String.first(user.name) |> String.upcase()}
                  </span>
                </div>
                <div class="min-w-0">
                  <p class="text-sm font-medium text-base-content truncate">{user.name}</p>
                  <p class="text-xs text-base-content/50 truncate">{user.email}</p>
                </div>
              </div>
              <div class="flex items-center gap-2 flex-shrink-0">
                <.role_badge role={user.role} />
                <.status_badge is_active={user.is_active} />
              </div>
            </div>
          <% end %>
          <%= if @recent == [] do %>
            <div class="px-6 py-8 text-center text-base-content/40 text-sm">
              No hay usuarios registrados aún.
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Private components
  # ---------------------------------------------------------------------------

  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :icon, :string, required: true
  attr :variant, :atom, required: true

  defp stat_card(%{variant: :primary} = assigns) do
    ~H"""
    <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm p-5 flex items-center gap-4">
      <div class="size-12 rounded-xl bg-primary/10 flex items-center justify-center flex-shrink-0">
        <.icon name={@icon} class="size-6 text-primary" />
      </div>
      <div>
        <p class="text-2xl font-bold text-base-content">{@value}</p>
        <p class="text-xs text-base-content/50 mt-0.5">{@label}</p>
      </div>
    </div>
    """
  end

  defp stat_card(%{variant: :secondary} = assigns) do
    ~H"""
    <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm p-5 flex items-center gap-4">
      <div class="size-12 rounded-xl bg-secondary/10 flex items-center justify-center flex-shrink-0">
        <.icon name={@icon} class="size-6 text-secondary" />
      </div>
      <div>
        <p class="text-2xl font-bold text-base-content">{@value}</p>
        <p class="text-xs text-base-content/50 mt-0.5">{@label}</p>
      </div>
    </div>
    """
  end

  defp stat_card(%{variant: :accent} = assigns) do
    ~H"""
    <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm p-5 flex items-center gap-4">
      <div class="size-12 rounded-xl bg-accent/10 flex items-center justify-center flex-shrink-0">
        <.icon name={@icon} class="size-6 text-accent" />
      </div>
      <div>
        <p class="text-2xl font-bold text-base-content">{@value}</p>
        <p class="text-xs text-base-content/50 mt-0.5">{@label}</p>
      </div>
    </div>
    """
  end

  defp stat_card(%{variant: :success} = assigns) do
    ~H"""
    <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm p-5 flex items-center gap-4">
      <div class="size-12 rounded-xl bg-success/10 flex items-center justify-center flex-shrink-0">
        <.icon name={@icon} class="size-6 text-success" />
      </div>
      <div>
        <p class="text-2xl font-bold text-base-content">{@value}</p>
        <p class="text-xs text-base-content/50 mt-0.5">{@label}</p>
      </div>
    </div>
    """
  end

  defp stat_card(%{variant: :error} = assigns) do
    ~H"""
    <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm p-5 flex items-center gap-4">
      <div class="size-12 rounded-xl bg-error/10 flex items-center justify-center flex-shrink-0">
        <.icon name={@icon} class="size-6 text-error" />
      </div>
      <div>
        <p class="text-2xl font-bold text-base-content">{@value}</p>
        <p class="text-xs text-base-content/50 mt-0.5">{@label}</p>
      </div>
    </div>
    """
  end

  defp stat_card(%{variant: :warning} = assigns) do
    ~H"""
    <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm p-5 flex items-center gap-4">
      <div class="size-12 rounded-xl bg-warning/10 flex items-center justify-center flex-shrink-0">
        <.icon name={@icon} class="size-6 text-warning" />
      </div>
      <div>
        <p class="text-2xl font-bold text-base-content">{@value}</p>
        <p class="text-xs text-base-content/50 mt-0.5">{@label}</p>
      </div>
    </div>
    """
  end

  defp role_badge(assigns) do
    {text, cls} =
      case assigns.role do
        "admin" -> {"Admin", "badge-primary"}
        "empleado" -> {"Empleado", "badge-secondary"}
        _ -> {"Cliente", "badge-ghost"}
      end

    assigns = assign(assigns, text: text, cls: cls)

    ~H"""
    <span class={["badge badge-sm", @cls]}>{@text}</span>
    """
  end

  defp status_badge(assigns) do
    ~H"""
    <%= if @is_active do %>
      <span class="badge badge-sm badge-success">Activo</span>
    <% else %>
      <span class="badge badge-sm badge-error">Inactivo</span>
    <% end %>
    """
  end
end
