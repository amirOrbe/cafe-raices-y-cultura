defmodule CRCWeb.Admin.CumpleanosLive do
  @moduledoc "Birthday overview for all active staff (admins + employees)."

  use CRCWeb, :live_view

  alias CRC.Accounts

  @impl true
  def mount(_params, _session, socket) do
    today = Date.utc_today()
    staff = Accounts.list_staff_with_birthdays()

    socket =
      socket
      |> assign(:page_title, "Cumpleaños del equipo")
      |> assign(:today, today)
      |> assign(:staff, staff)

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    today = assigns.today

    today_bdays = Enum.filter(assigns.staff, &(&1.days_until_birthday == 0))
    no_bdays = Enum.filter(assigns.staff, &is_nil(&1.days_until_birthday))

    # Group remaining staff (excluding today) by the calendar month of their next birthday
    month_groups =
      assigns.staff
      |> Enum.filter(&(not is_nil(&1.days_until_birthday) and &1.days_until_birthday > 0))
      |> Enum.map(fn user ->
        next_date = Date.add(today, user.days_until_birthday)
        Map.put(user, :next_birthday_date, next_date)
      end)
      |> Enum.group_by(fn user ->
        {user.next_birthday_date.year, user.next_birthday_date.month}
      end)
      |> Enum.sort_by(fn {{year, month}, _} -> {year, month} end)
      |> Enum.map(fn {{_year, month}, users} ->
        %{
          month: month,
          label: month_name(month),
          users: Enum.sort_by(users, & &1.next_birthday_date.day)
        }
      end)

    assigns =
      assigns
      |> assign(:today_bdays, today_bdays)
      |> assign(:month_groups, month_groups)
      |> assign(:no_bdays, no_bdays)

    ~H"""
    <div class="space-y-6">
      <%!-- Header --%>
      <div>
        <h1 class="text-2xl font-bold text-base-content">Cumpleaños del equipo</h1>
        <p class="text-sm text-base-content/50 mt-0.5">
          {format_date(@today)} · {length(@staff)} empleado{if length(@staff) != 1, do: "s"}
        </p>
      </div>

      <%!-- TODAY banner --%>
      <%= if @today_bdays != [] do %>
        <div class="bg-gradient-to-r from-primary/20 to-accent/20 border border-primary/30 rounded-2xl p-5">
          <div class="flex items-center gap-2 mb-3">
            <span class="text-2xl">🎂</span>
            <h2 class="font-bold text-base-content text-lg">
              ¡{if length(@today_bdays) == 1, do: "Hoy es el cumpleaños de", else: "Hoy cumplen años"}!
            </h2>
          </div>
          <div class="flex flex-wrap gap-3">
            <%= for user <- @today_bdays do %>
              <div class="flex items-center gap-3 bg-base-100/80 rounded-xl px-4 py-2.5 shadow-sm">
                <.avatar user={user} size="md" />
                <div>
                  <p class="font-semibold text-base-content">{user.name}</p>
                  <p class="text-xs text-base-content/50">
                    <.role_badge role={user.role} />
                    <%= if user.birthday do %>
                      · {age_label(user.birthday, @today)}
                    <% end %>
                  </p>
                </div>
                <span class="text-xl ml-1">🎉</span>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <%!-- Month groups --%>
      <%= if @month_groups == [] and @today_bdays == [] and @no_bdays == [] do %>
        <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm py-16 text-center">
          <.icon name="hero-cake" class="size-12 text-base-content/20 mx-auto mb-3" />
          <p class="text-base-content/50 text-sm">No hay empleados con fecha de nacimiento registrada.</p>
          <p class="text-base-content/40 text-xs mt-1">Agrégalas desde <a href="/admin/usuarios" class="link">Usuarios</a>.</p>
        </div>
      <% end %>

      <%= for group <- @month_groups do %>
        <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm overflow-hidden">
          <div class="px-5 py-3 border-b border-base-200 flex items-center justify-between">
            <div class="flex items-center gap-2">
              <.icon name="hero-calendar-days" class="size-4 text-base-content/40" />
              <h3 class="font-semibold text-sm text-base-content">{group.label}</h3>
            </div>
            <span class="badge badge-ghost badge-sm">{length(group.users)}</span>
          </div>
          <div class="divide-y divide-base-200">
            <%= for user <- group.users do %>
              <.user_row user={user} today={@today} />
            <% end %>
          </div>
        </div>
      <% end %>

      <%!-- No birthday set --%>
      <%= if @no_bdays != [] do %>
        <div class="bg-base-100 rounded-2xl border border-base-300 shadow-sm overflow-hidden">
          <div class="px-5 py-3 border-b border-base-200 flex items-center gap-2">
            <.icon name="hero-question-mark-circle" class="size-4 text-base-content/30" />
            <h3 class="font-semibold text-sm text-base-content/40">Sin fecha registrada</h3>
          </div>
          <div class="divide-y divide-base-200">
            <%= for user <- @no_bdays do %>
              <.user_row user={user} today={@today} />
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # User row component
  # ---------------------------------------------------------------------------

  attr :user, :map, required: true
  attr :today, :any, required: true

  defp user_row(assigns) do
    ~H"""
    <div class="flex items-center gap-3 px-5 py-3">
      <.avatar user={@user} size="sm" />
      <div class="flex-1 min-w-0">
        <p class="text-sm font-semibold text-base-content truncate">{@user.name}</p>
        <p class="text-xs text-base-content/50 mt-0.5">
          {role_label(@user.role)}
          <%= if @user.birthday do %>
            · {format_birthday(@user.birthday)}
          <% end %>
        </p>
      </div>
      <div class="shrink-0 text-right">
        <%= cond do %>
          <% @user.days_until_birthday == 0 -> %>
            <span class="badge badge-primary badge-sm font-semibold">¡Hoy! 🎂</span>
          <% @user.days_until_birthday in 1..7 -> %>
            <span class="badge badge-warning badge-sm">
              En {@user.days_until_birthday} día{if @user.days_until_birthday != 1, do: "s"}
            </span>
          <% @user.days_until_birthday in 8..30 -> %>
            <span class="badge badge-info badge-sm">
              En {@user.days_until_birthday} días
            </span>
          <% not is_nil(@user.days_until_birthday) -> %>
            <span class="text-xs text-base-content/40">
              En {@user.days_until_birthday} días
            </span>
          <% true -> %>
            <span class="text-xs text-base-content/30 italic">Sin fecha</span>
        <% end %>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Avatar component
  # ---------------------------------------------------------------------------

  attr :user, :map, required: true
  attr :size, :string, default: "sm"

  defp avatar(assigns) do
    ~H"""
    <%= if @user.avatar_url do %>
      <img
        src={@user.avatar_url}
        class={"rounded-full object-cover shrink-0 border border-base-300 #{avatar_size_class(@size)}"}
      />
    <% else %>
      <div class={"rounded-full shrink-0 flex items-center justify-center font-bold text-white #{avatar_size_class(@size)} #{avatar_bg(@user.id)}"}>
        {initials(@user.name)}
      </div>
    <% end %>
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp role_label("admin"), do: "Administrador"
  defp role_label("empleado"), do: "Empleado"
  defp role_label(r), do: r

  defp role_badge(assigns) do
    ~H"""
    <span class={role_badge_class(@role)}>{role_label(@role)}</span>
    """
  end

  defp role_badge_class("admin"), do: "text-primary font-semibold"
  defp role_badge_class(_), do: "text-base-content/60"

  defp initials(name) when is_binary(name) do
    name |> String.split() |> Enum.take(2) |> Enum.map(&String.first/1) |> Enum.join() |> String.upcase()
  end
  defp initials(_), do: "?"

  @avatar_colors ~w(bg-violet-500 bg-blue-500 bg-emerald-500 bg-orange-500 bg-pink-500 bg-teal-500 bg-rose-500 bg-indigo-500)
  defp avatar_bg(id), do: Enum.at(@avatar_colors, rem(id, length(@avatar_colors)))

  defp avatar_size_class("md"), do: "size-12"
  defp avatar_size_class(_), do: "size-9"

  defp format_birthday(%Date{} = d) do
    months = ~w(ene feb mar abr may jun jul ago sep oct nov dic)
    "#{d.day} de #{Enum.at(months, d.month - 1)}"
  end

  defp age_label(%Date{} = bday, %Date{} = today) do
    age = today.year - bday.year
    "#{age} años"
  end

  defp format_date(%Date{} = date) do
    days = ~w(lunes martes miércoles jueves viernes sábado domingo)
    months = ~w(enero febrero marzo abril mayo junio julio agosto septiembre octubre noviembre diciembre)
    day_name = Enum.at(days, Date.day_of_week(date) - 1)
    "#{String.capitalize(day_name)}, #{date.day} de #{Enum.at(months, date.month - 1)} #{date.year}"
  end

  @month_names ~w(Enero Febrero Marzo Abril Mayo Junio Julio Agosto Septiembre Octubre Noviembre Diciembre)
  defp month_name(month), do: Enum.at(@month_names, month - 1)
end
