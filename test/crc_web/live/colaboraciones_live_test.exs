defmodule CRCWeb.ColaboracionesLiveTest do
  use CRCWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias CRC.Events

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp insert_event_type(overrides \\ %{}) do
    attrs = Map.merge(%{name: "Concierto #{System.unique_integer()}"}, overrides)
    {:ok, et} = Events.create_event_type(attrs)
    et
  end

  defp insert_collaborator(overrides \\ %{}) do
    attrs = Map.merge(%{name: "Artista #{System.unique_integer()}"}, overrides)
    {:ok, c} = Events.create_collaborator(attrs)
    c
  end

  # Returns today in CDMX time (UTC-6), matching the LiveView logic.
  defp cdmx_today do
    DateTime.utc_now()
    |> DateTime.add(-6 * 3600, :second)
    |> DateTime.to_date()
  end

  # Returns a date that is guaranteed to be in the current month and in the
  # future. Falls back to tomorrow if near end of month.
  defp upcoming_date_this_month do
    today = cdmx_today()
    days_in_month = Date.days_in_month(today)
    offset = if today.day + 3 <= days_in_month, do: 3, else: 1
    Date.add(today, offset)
  end

  defp insert_event(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          title: "Evento Test #{System.unique_integer()}",
          event_date: upcoming_date_this_month(),
          start_time: ~T[18:00:00],
          end_time: ~T[21:00:00],
          active: true
        },
        overrides
      )

    {:ok, event} = Events.create_event(attrs)
    event
  end

  # ---------------------------------------------------------------------------
  # Basic rendering
  # ---------------------------------------------------------------------------

  describe "GET /colaboraciones" do
    test "renders the collaborations page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/colaboraciones")
      assert html =~ "Colaboraciones"
    end

    test "always shows the CTA section", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/colaboraciones")
      assert html =~ "¿Tienes una propuesta?"
    end

    test "shows current month name in calendar navigation", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/colaboraciones")
      months = ~w(Enero Febrero Marzo Abril Mayo Junio Julio Agosto Septiembre Octubre Noviembre Diciembre)
      assert Enum.any?(months, &String.contains?(html, &1))
    end

    test "event title appears in calendar pill for current-month events", %{conn: conn} do
      insert_event(%{title: "Jazz Night Calendario"})

      {:ok, _lv, html} = live(conn, ~p"/colaboraciones")
      assert html =~ "Jazz Night Calendario"
    end

    test "inactive events are not shown", %{conn: conn} do
      insert_event(%{title: "Evento Inactivo Test", active: false})

      {:ok, _lv, html} = live(conn, ~p"/colaboraciones")
      refute html =~ "Evento Inactivo Test"
    end

    test "shows empty-month message when navigated to a month with no events", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/colaboraciones")

      for _ <- 1..24, do: render_click(lv, "next_month", %{})

      assert render(lv) =~ "Sin eventos para este mes"
    end
  end

  # ---------------------------------------------------------------------------
  # Calendar day detail panel
  # ---------------------------------------------------------------------------

  describe "day detail panel" do
    test "clicking a day with an event reveals full event details", %{conn: conn} do
      event = insert_event(%{
        title: "Concierto De Jazz",
        description: "Una noche de jazz en vivo."
      })

      {:ok, lv, _html} = live(conn, ~p"/colaboraciones")
      render_click(lv, "select_day", %{"date" => Date.to_iso8601(event.event_date)})
      html = render(lv)

      assert html =~ "Concierto De Jazz"
      assert html =~ "Una noche de jazz en vivo."
    end

    test "clicking the same day again closes the detail panel", %{conn: conn} do
      event = insert_event(%{
        title: "Evento Toggle",
        description: "Descripción única togglable."
      })

      {:ok, lv, _html} = live(conn, ~p"/colaboraciones")
      date_str = Date.to_iso8601(event.event_date)

      render_click(lv, "select_day", %{"date" => date_str})
      assert render(lv) =~ "Descripción única togglable."

      render_click(lv, "select_day", %{"date" => date_str})
      refute render(lv) =~ "Descripción única togglable."
    end

    test "shows event tags in detail panel", %{conn: conn} do
      event = insert_event(%{
        title: "Evento Con Tags",
        tags: ["Música", "Noche"]
      })

      {:ok, lv, _html} = live(conn, ~p"/colaboraciones")
      render_click(lv, "select_day", %{"date" => Date.to_iso8601(event.event_date)})
      html = render(lv)

      assert html =~ "Música"
      assert html =~ "Noche"
    end

    test "shows event type badge in detail panel", %{conn: conn} do
      et = insert_event_type(%{name: "Festival Acústico"})
      event = insert_event(%{title: "Evento Con Tipo", event_type_id: et.id})

      {:ok, lv, _html} = live(conn, ~p"/colaboraciones")
      render_click(lv, "select_day", %{"date" => Date.to_iso8601(event.event_date)})
      assert render(lv) =~ "Festival Acústico"
    end

    test "shows formatted full date with Spanish month in detail panel", %{conn: conn} do
      event = insert_event(%{title: "Evento Fecha Detalle"})

      {:ok, lv, _html} = live(conn, ~p"/colaboraciones")
      render_click(lv, "select_day", %{"date" => Date.to_iso8601(event.event_date)})
      html = render(lv)

      months = ~w(enero febrero marzo abril mayo junio julio agosto septiembre octubre noviembre diciembre)
      assert Enum.any?(months, &String.contains?(html, &1))
    end

    test "shows past badge for past-month events after navigating", %{conn: conn} do
      today = cdmx_today()
      {prev_year, prev_month} = if today.month == 1, do: {today.year - 1, 12}, else: {today.year, today.month - 1}
      past_date = Date.new!(prev_year, prev_month, 10)

      insert_event(%{title: "Evento Pasado Mes", event_date: past_date, active: true})

      {:ok, lv, _html} = live(conn, ~p"/colaboraciones")
      render_click(lv, "prev_month", %{})
      render_click(lv, "select_day", %{"date" => Date.to_iso8601(past_date)})
      html = render(lv)

      assert html =~ "Evento Pasado Mes"
      assert html =~ "Pasado"
    end
  end

  # ---------------------------------------------------------------------------
  # Collaborator badges
  # ---------------------------------------------------------------------------

  describe "collaborator badges in detail panel" do
    test "shows collaborator name and role", %{conn: conn} do
      collaborator = insert_collaborator(%{name: "Músico Especial"})

      {:ok, event} =
        Events.create_event(
          %{
            title: "Evento Con Músico",
            event_date: upcoming_date_this_month(),
            start_time: ~T[19:00:00],
            end_time: ~T[22:00:00],
            active: true
          },
          [{collaborator.id, "Guitarrista"}]
        )

      {:ok, lv, _html} = live(conn, ~p"/colaboraciones")
      render_click(lv, "select_day", %{"date" => Date.to_iso8601(event.event_date)})
      html = render(lv)

      assert html =~ "Músico Especial"
      assert html =~ "Guitarrista"
    end

    test "shows instagram link when collaborator has a handle", %{conn: conn} do
      collaborator = insert_collaborator(%{name: "Dj Instagram", instagram_handle: "djinstagram"})

      {:ok, event} =
        Events.create_event(
          %{
            title: "Evento Instagram",
            event_date: upcoming_date_this_month(),
            start_time: ~T[19:00:00],
            end_time: ~T[22:00:00],
            active: true
          },
          [{collaborator.id, "DJ"}]
        )

      {:ok, lv, _html} = live(conn, ~p"/colaboraciones")
      render_click(lv, "select_day", %{"date" => Date.to_iso8601(event.event_date)})
      html = render(lv)

      assert html =~ "instagram.com/djinstagram"
      assert html =~ "Dj Instagram"
    end

    test "shows collaborator name without link when no instagram handle", %{conn: conn} do
      collaborator = insert_collaborator(%{name: "Artista Sin Instagram"})

      {:ok, event} =
        Events.create_event(
          %{
            title: "Evento Sin Instagram",
            event_date: upcoming_date_this_month(),
            start_time: ~T[18:00:00],
            end_time: ~T[21:00:00],
            active: true
          },
          [{collaborator.id, ""}]
        )

      {:ok, lv, _html} = live(conn, ~p"/colaboraciones")
      render_click(lv, "select_day", %{"date" => Date.to_iso8601(event.event_date)})
      assert render(lv) =~ "Artista Sin Instagram"
    end
  end

  # ---------------------------------------------------------------------------
  # Month navigation
  # ---------------------------------------------------------------------------

  describe "month navigation" do
    test "prev_month navigates to previous month", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/colaboraciones")
      render_click(lv, "prev_month", %{})
      assert render(lv) =~ "Colaboraciones"
    end

    test "next_month navigates to next month", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/colaboraciones")
      render_click(lv, "next_month", %{})
      assert render(lv) =~ "Colaboraciones"
    end

    test "changing month clears the selected day panel", %{conn: conn} do
      event = insert_event(%{
        title: "Evento Para Limpiar",
        description: "Descripción que desaparece al navegar."
      })

      {:ok, lv, _html} = live(conn, ~p"/colaboraciones")
      render_click(lv, "select_day", %{"date" => Date.to_iso8601(event.event_date)})
      assert render(lv) =~ "Descripción que desaparece al navegar."

      render_click(lv, "next_month", %{})
      refute render(lv) =~ "Descripción que desaparece al navegar."
    end

    test "crossing year boundary backwards renders December of previous year", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/colaboraciones")
      today = cdmx_today()
      # Going back `today.month` times from the current month lands on December
      for _ <- 1..today.month, do: render_click(lv, "prev_month", %{})
      assert render(lv) =~ "Diciembre"
    end

    test "crossing year boundary forward renders January of next year", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/colaboraciones")
      today = cdmx_today()
      months_forward = 13 - today.month
      for _ <- 1..months_forward, do: render_click(lv, "next_month", %{})
      assert render(lv) =~ "Enero"
    end
  end

  # ---------------------------------------------------------------------------
  # Nav events
  # ---------------------------------------------------------------------------

  describe "nav events" do
    test "toggle_nav works", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/colaboraciones")
      render_click(lv, "toggle_nav", %{})
      render_click(lv, "toggle_nav", %{})
      assert render(lv)
    end

    test "close_nav works", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/colaboraciones")
      render_click(lv, "toggle_nav", %{})
      render_click(lv, "close_nav", %{})
      assert render(lv)
    end
  end

  # ---------------------------------------------------------------------------
  # PubSub and timer
  # ---------------------------------------------------------------------------

  describe "PubSub and timer" do
    test "tick reloads events", %{conn: conn} do
      {:ok, lv, _} = live(conn, ~p"/colaboraciones")
      send(lv.pid, :tick)
      assert render(lv) =~ "Colaboraciones"
    end

    test "event_changed PubSub reloads the calendar", %{conn: conn} do
      {:ok, lv, _} = live(conn, ~p"/colaboraciones")

      insert_event(%{title: "Evento Refresco Colabs"})
      Phoenix.PubSub.broadcast(CRC.PubSub, "admin:events", {:event_changed, %{}})

      assert render(lv) =~ "Evento Refresco Colabs"
    end
  end

  # ---------------------------------------------------------------------------
  # EN VIVO section
  # ---------------------------------------------------------------------------

  describe "current event section" do
    test "shows EN VIVO banner for today's ongoing event", %{conn: conn} do
      insert_event(%{
        title: "Evento En Curso",
        event_date: cdmx_today(),
        start_time: ~T[00:00:00],
        end_time: ~T[23:59:59]
      })

      {:ok, _lv, html} = live(conn, ~p"/colaboraciones")
      assert html =~ "EN VIVO"
      assert html =~ "Evento En Curso"
    end

    test "shows event type in EN VIVO section", %{conn: conn} do
      et = insert_event_type(%{name: "Concierto Tipo"})

      insert_event(%{
        title: "Evento Con Tipo Hoy",
        event_date: cdmx_today(),
        start_time: ~T[00:00:00],
        end_time: ~T[23:59:59],
        event_type_id: et.id
      })

      {:ok, _lv, html} = live(conn, ~p"/colaboraciones")
      assert html =~ "Concierto Tipo"
    end

    test "shows description in EN VIVO section", %{conn: conn} do
      insert_event(%{
        title: "Evento Descripción Hoy",
        event_date: cdmx_today(),
        start_time: ~T[00:00:00],
        end_time: ~T[23:59:59],
        description: "Una noche especial de café y música."
      })

      {:ok, _lv, html} = live(conn, ~p"/colaboraciones")
      assert html =~ "Una noche especial de café y música."
    end

    test "shows collaborators in EN VIVO section", %{conn: conn} do
      collaborator = insert_collaborator(%{name: "Artista Hoy", instagram_handle: "artistahoy"})

      {:ok, _event} =
        Events.create_event(
          %{
            title: "Evento Colabs Hoy",
            event_date: cdmx_today(),
            start_time: ~T[00:00:00],
            end_time: ~T[23:59:59],
            active: true
          },
          [{collaborator.id, "Vocalista"}]
        )

      {:ok, _lv, html} = live(conn, ~p"/colaboraciones")
      assert html =~ "Artista Hoy"
    end
  end
end
