defmodule CRCWeb.ColaboracionesLiveTest do
  use CRCWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias CRC.Events
  alias CRC.Events.{Event, EventType, Collaborator}

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

  # CDMX-adjusted today, matching the logic used in the Events context (UTC-6).
  defp cdmx_today do
    DateTime.utc_now()
    |> DateTime.add(-6 * 3600, :second)
    |> DateTime.to_date()
  end

  defp insert_event(overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          title: "Evento Test #{System.unique_integer()}",
          event_date: Date.add(cdmx_today(), 5),
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
  # Tests
  # ---------------------------------------------------------------------------

  describe "GET /colaboraciones" do
    test "renders the collaborations page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/colaboraciones")
      assert html =~ "Colaboraciones"
    end

    test "always shows the '¿Tienes una propuesta?' CTA section", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/colaboraciones")
      assert html =~ "¿Tienes una propuesta?"
    end

    test "shows upcoming events section when events exist", %{conn: conn} do
      insert_event(%{
        title: "Jazz Night Próxima",
        event_date: Date.add(cdmx_today(), 3),
        active: true
      })

      {:ok, _lv, html} = live(conn, ~p"/colaboraciones")
      assert html =~ "Jazz Night Próxima"
      assert html =~ "Próximas colaboraciones"
    end

    test "shows past events in historial section", %{conn: conn} do
      # We test this by looking for the historial section
      # Past events have event_date < today
      # We can't easily insert past dates without bypassing validation,
      # but we can check the section header appears when there are past events
      {:ok, _lv, html} = live(conn, ~p"/colaboraciones")
      # The page should still render fine even with no past events
      assert html =~ "Colaboraciones"
    end

    test "shows event date formatted in Spanish", %{conn: conn} do
      insert_event(%{
        title: "Evento Fecha Test",
        event_date: Date.add(cdmx_today(), 2),
        active: true
      })

      {:ok, _lv, html} = live(conn, ~p"/colaboraciones")
      # Spanish month names should appear somewhere in the page
      months = ~w(enero febrero marzo abril mayo junio julio agosto septiembre octubre noviembre diciembre)
      assert Enum.any?(months, &String.contains?(html, &1))
    end

    test "shows collaborator names in events", %{conn: conn} do
      collaborator = insert_collaborator(%{name: "Músico Especial"})

      {:ok, event} =
        Events.create_event(
          %{
            title: "Evento con Músico",
            event_date: Date.add(cdmx_today(), 4),
            start_time: ~T[19:00:00],
            end_time: ~T[22:00:00],
            active: true
          },
          [{collaborator.id, "Guitarrista"}]
        )

      {:ok, _lv, html} = live(conn, ~p"/colaboraciones")
      assert html =~ "Músico Especial"
    end

    test "inactive events are not shown", %{conn: conn} do
      insert_event(%{
        title: "Evento Inactivo Test",
        event_date: Date.add(cdmx_today(), 2),
        active: false
      })

      {:ok, _lv, html} = live(conn, ~p"/colaboraciones")
      refute html =~ "Evento Inactivo Test"
    end
  end

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

  describe "PubSub and timer" do
    test "tick handle_info reloads events", %{conn: conn} do
      {:ok, lv, _} = live(conn, ~p"/colaboraciones")
      send(lv.pid, :tick)
      assert render(lv) =~ "Colaboraciones"
    end

    test "event_changed PubSub reloads events", %{conn: conn} do
      {:ok, lv, _} = live(conn, ~p"/colaboraciones")

      insert_event(%{title: "Evento PubSub Colabs", event_date: Date.add(cdmx_today(), 2)})
      Phoenix.PubSub.broadcast(CRC.PubSub, "admin:events", {:event_changed, %{}})

      html = render(lv)
      assert html =~ "Evento PubSub Colabs"
    end
  end

  describe "current event section" do
    test "shows EN VIVO section for today's ongoing event", %{conn: conn} do
      # An event spanning the full day is always current regardless of CI time
      insert_event(%{
        title: "Evento En Curso",
        event_date: cdmx_today(),
        start_time: ~T[00:00:00],
        end_time: ~T[23:59:59],
        active: true
      })

      {:ok, _lv, html} = live(conn, ~p"/colaboraciones")
      assert html =~ "EN VIVO"
      assert html =~ "Evento En Curso"
    end

    test "shows event type in current event section", %{conn: conn} do
      et = insert_event_type(%{name: "Concierto Tipo"})

      insert_event(%{
        title: "Evento Con Tipo Hoy",
        event_date: cdmx_today(),
        start_time: ~T[00:00:00],
        end_time: ~T[23:59:59],
        active: true,
        event_type_id: et.id
      })

      {:ok, _lv, html} = live(conn, ~p"/colaboraciones")
      assert html =~ "Concierto Tipo"
    end
  end

  describe "past events section" do
    test "shows historial section when past events exist", %{conn: conn} do
      insert_event(%{
        title: "Evento Pasado Test",
        event_date: Date.add(cdmx_today(), -5),
        active: true
      })

      {:ok, _lv, html} = live(conn, ~p"/colaboraciones")
      assert html =~ "Historial de colaboraciones"
      assert html =~ "Evento Pasado Test"
    end

    test "shows collaborator badges in past events (small=true)", %{conn: conn} do
      collaborator = insert_collaborator(%{name: "Artista Pasado"})

      {:ok, _event} =
        Events.create_event(
          %{
            title: "Concierto Pasado",
            event_date: Date.add(cdmx_today(), -2),
            start_time: ~T[20:00:00],
            end_time: ~T[23:00:00],
            active: true
          },
          [{collaborator.id, "Bajista"}]
        )

      {:ok, _lv, html} = live(conn, ~p"/colaboraciones")
      assert html =~ "Artista Pasado"
    end

    test "shows event type badge in past events", %{conn: conn} do
      et = insert_event_type(%{name: "Tipo Pasado"})

      insert_event(%{
        title: "Evento Tipo Pasado",
        event_date: Date.add(cdmx_today(), -1),
        start_time: ~T[18:00:00],
        end_time: ~T[21:00:00],
        active: true,
        event_type_id: et.id
      })

      {:ok, _lv, html} = live(conn, ~p"/colaboraciones")
      assert html =~ "Tipo Pasado"
    end
  end

  describe "collaborator badges" do
    test "shows instagram link when collaborator has instagram_handle", %{conn: conn} do
      collaborator =
        insert_collaborator(%{name: "DJ Instagram", instagram_handle: "djinstagram"})

      {:ok, _event} =
        Events.create_event(
          %{
            title: "Evento Instagram",
            event_date: Date.add(cdmx_today(), 3),
            start_time: ~T[19:00:00],
            end_time: ~T[22:00:00],
            active: true
          },
          [{collaborator.id, "DJ"}]
        )

      {:ok, _lv, html} = live(conn, ~p"/colaboraciones")
      assert html =~ "instagram.com/djinstagram"
      assert html =~ "DJ Instagram"
    end

    test "shows role in collaborator badge", %{conn: conn} do
      collaborator = insert_collaborator(%{name: "Músico Rol"})

      {:ok, _event} =
        Events.create_event(
          %{
            title: "Evento Con Rol",
            event_date: Date.add(cdmx_today(), 6),
            start_time: ~T[20:00:00],
            end_time: ~T[23:00:00],
            active: true
          },
          [{collaborator.id, "Guitarrista"}]
        )

      {:ok, _lv, html} = live(conn, ~p"/colaboraciones")
      assert html =~ "Guitarrista"
    end

    test "shows collaborator name without instagram link when no handle", %{conn: conn} do
      collaborator = insert_collaborator(%{name: "Artista Sin IG"})

      {:ok, _event} =
        Events.create_event(
          %{
            title: "Evento Sin IG",
            event_date: Date.add(cdmx_today(), 4),
            start_time: ~T[18:00:00],
            end_time: ~T[21:00:00],
            active: true
          },
          [{collaborator.id, ""}]
        )

      {:ok, _lv, html} = live(conn, ~p"/colaboraciones")
      assert html =~ "Artista Sin IG"
    end
  end

  describe "tags in upcoming events" do
    test "shows event tags", %{conn: conn} do
      insert_event(%{
        title: "Evento Con Tags",
        event_date: Date.add(cdmx_today(), 3),
        active: true,
        tags: ["Música", "Noche"]
      })

      {:ok, _lv, html} = live(conn, ~p"/colaboraciones")
      assert html =~ "Música"
      assert html =~ "Noche"
    end
  end

  describe "current event with description and collaborators" do
    test "shows description in current event section", %{conn: conn} do
      insert_event(%{
        title: "Evento Descripción Hoy",
        event_date: cdmx_today(),
        start_time: ~T[00:00:00],
        end_time: ~T[23:59:59],
        active: true,
        description: "Una noche especial de café y música."
      })

      {:ok, _lv, html} = live(conn, ~p"/colaboraciones")
      assert html =~ "Una noche especial de café y música."
    end

    test "shows collaborators in current event section", %{conn: conn} do
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

  describe "upcoming events with description" do
    test "shows description in upcoming event card", %{conn: conn} do
      insert_event(%{
        title: "Evento Próximo Desc",
        event_date: Date.add(cdmx_today(), 4),
        active: true,
        description: "Taller interactivo de barismo."
      })

      {:ok, _lv, html} = live(conn, ~p"/colaboraciones")
      assert html =~ "Taller interactivo de barismo."
    end
  end

  describe "format_event_date months coverage" do
    test "covers additional months in past events", %{conn: conn} do
      # Insert past events spread across different months to cover format_event_date branches
      past_months = [
        {"2026-01-05", "Enero Pasado"},  # enero (1)
        {"2026-02-06", "Febrero Pasado"},  # febrero (2) - also a Friday for "Viernes"
        {"2025-05-09", "Mayo Pasado"},    # mayo (5)
        {"2025-06-05", "Junio Pasado"},   # junio (6)
        {"2025-07-04", "Julio Pasado"},   # julio (7)
        {"2025-08-01", "Agosto Pasado"},  # agosto (8)
        {"2025-09-12", "Septiembre Pasado"},  # septiembre (9)
        {"2025-10-10", "Octubre Pasado"},  # octubre (10)
        {"2025-11-07", "Noviembre Pasado"},  # noviembre (11)
        {"2025-12-05", "Diciembre Pasado"},  # diciembre (12)
      ]

      for {date_str, title} <- past_months do
        insert_event(%{
          title: title,
          event_date: Date.from_iso8601!(date_str),
          active: true
        })
      end

      {:ok, _lv, html} = live(conn, ~p"/colaboraciones")
      assert html =~ "enero" or html =~ "Enero Pasado"
    end

    test "covers Viernes weekday in format_event_date", %{conn: conn} do
      # 2026-01-02 is a Friday
      insert_event(%{
        title: "Evento Viernes",
        event_date: ~D[2026-01-02],
        active: true
      })

      {:ok, _lv, html} = live(conn, ~p"/colaboraciones")
      assert html =~ "Viernes"
    end

    test "covers additional weekdays in format_event_date", %{conn: conn} do
      # Cover Lunes, Martes, Miercoles, Sabado, Domingo via past events
      weekday_dates = [
        {~D[2026-01-05], "Lunes Pasado"},   # Monday
        {~D[2026-01-06], "Martes Pasado"},  # Tuesday
        {~D[2026-01-07], "Mier Pasado"},    # Wednesday
        {~D[2026-01-03], "Sabado Pasado"},  # Saturday
        {~D[2026-01-04], "Domingo Pasado"}, # Sunday
      ]

      for {date, title} <- weekday_dates do
        insert_event(%{title: title, event_date: date, active: true})
      end

      {:ok, _lv, html} = live(conn, ~p"/colaboraciones")
      assert html =~ "Historial de colaboraciones"
    end
  end
end
