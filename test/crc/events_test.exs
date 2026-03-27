defmodule CRC.EventsTest do
  use CRC.DataCase, async: true

  alias CRC.Events
  alias CRC.Events.{Collaborator, Event, EventCollaborator, EventType}

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp event_type_attrs(overrides \\ %{}) do
    Map.merge(%{name: "Concierto"}, overrides)
  end

  defp collaborator_attrs(overrides \\ %{}) do
    Map.merge(
      %{name: "María García", bio: "Poeta y músico", instagram_handle: "mariagarcia"},
      overrides
    )
  end

  # Builds event attrs with a future date by default (tomorrow) so tests
  # are independent of the current CDMX time.
  defp event_attrs(overrides \\ %{}) do
    tomorrow = Date.utc_today() |> Date.add(1)

    Map.merge(
      %{
        title: "Noche de Jazz",
        description: "Velada musical en el café",
        event_date: tomorrow,
        start_time: ~T[19:00:00],
        end_time: ~T[22:00:00]
      },
      overrides
    )
  end

  defp insert_event_type(overrides \\ %{}) do
    {:ok, et} = Events.create_event_type(event_type_attrs(overrides))
    et
  end

  defp insert_collaborator(overrides \\ %{}) do
    {:ok, c} = Events.create_collaborator(collaborator_attrs(overrides))
    c
  end

  defp insert_event(attrs_overrides \\ %{}, collaborators \\ []) do
    {:ok, event} = Events.create_event(event_attrs(attrs_overrides), collaborators)
    event
  end

  # Returns today's date in CDMX timezone (UTC-6), matching the logic used
  # in Events context functions. This avoids test failures around UTC midnight.
  defp cdmx_today do
    DateTime.utc_now()
    |> DateTime.add(-6 * 3600, :second)
    |> DateTime.to_date()
  end

  # ===========================================================================
  # EVENT TYPES
  # ===========================================================================

  describe "EventType.changeset/2" do
    test "valid with required fields" do
      changeset = EventType.changeset(%EventType{}, event_type_attrs())
      assert changeset.valid?
    end

    test "invalid without name" do
      changeset = EventType.changeset(%EventType{}, %{name: nil})
      refute changeset.valid?
      assert changeset.errors[:name]
    end

    test "invalid with name shorter than 2 characters" do
      changeset = EventType.changeset(%EventType{}, %{name: "A"})
      refute changeset.valid?
      assert changeset.errors[:name]
    end

    test "invalid with name longer than 100 characters" do
      long_name = String.duplicate("x", 101)
      changeset = EventType.changeset(%EventType{}, %{name: long_name})
      refute changeset.valid?
      assert changeset.errors[:name]
    end

    test "valid with 2-character name" do
      changeset = EventType.changeset(%EventType{}, %{name: "DJ"})
      assert changeset.valid?
    end
  end

  describe "create_event_type/1" do
    test "creates an event type with valid attrs" do
      assert {:ok, %EventType{name: "Concierto"}} = Events.create_event_type(event_type_attrs())
    end

    test "new event type is active by default" do
      {:ok, et} = Events.create_event_type(event_type_attrs())
      assert et.active == true
    end

    test "returns error changeset with invalid attrs" do
      assert {:error, %Ecto.Changeset{}} = Events.create_event_type(%{name: nil})
    end
  end

  describe "list_event_types/0" do
    test "returns all event types ordered by name" do
      insert_event_type(%{name: "Taller"})
      insert_event_type(%{name: "Concierto"})
      insert_event_type(%{name: "Lectura"})

      names = Events.list_event_types() |> Enum.map(& &1.name)
      assert names == Enum.sort(names)
    end

    test "includes both active and inactive event types" do
      {:ok, et} = Events.create_event_type(event_type_attrs())
      Events.toggle_event_type_active(et)

      assert length(Events.list_event_types()) == 1
    end
  end

  describe "list_active_event_types/0" do
    test "returns only active event types" do
      {:ok, active} = Events.create_event_type(event_type_attrs(%{name: "Activo"}))
      {:ok, inactive} = Events.create_event_type(event_type_attrs(%{name: "Inactivo"}))
      Events.toggle_event_type_active(inactive)

      result = Events.list_active_event_types()
      ids = Enum.map(result, & &1.id)

      assert active.id in ids
      refute inactive.id in ids
    end

    test "returns event types ordered by name" do
      insert_event_type(%{name: "Taller"})
      insert_event_type(%{name: "Jam Session"})

      names = Events.list_active_event_types() |> Enum.map(& &1.name)
      assert names == Enum.sort(names)
    end
  end

  describe "update_event_type/2" do
    test "updates event type name" do
      et = insert_event_type()
      assert {:ok, updated} = Events.update_event_type(et, %{name: "Jam Session"})
      assert updated.name == "Jam Session"
    end

    test "returns error changeset with invalid attrs" do
      et = insert_event_type()
      assert {:error, %Ecto.Changeset{}} = Events.update_event_type(et, %{name: nil})
    end
  end

  describe "toggle_event_type_active/1" do
    test "deactivates an active event type" do
      et = insert_event_type()
      assert et.active == true

      {:ok, toggled} = Events.toggle_event_type_active(et)
      assert toggled.active == false
    end

    test "reactivates an inactive event type" do
      et = insert_event_type()
      {:ok, inactive} = Events.toggle_event_type_active(et)
      {:ok, reactivated} = Events.toggle_event_type_active(inactive)
      assert reactivated.active == true
    end
  end

  describe "get_event_type!/1" do
    test "returns event type by id" do
      et = insert_event_type()
      assert Events.get_event_type!(et.id).id == et.id
    end

    test "raises if not found" do
      assert_raise Ecto.NoResultsError, fn -> Events.get_event_type!(0) end
    end
  end

  describe "change_event_type/2" do
    test "returns an empty changeset" do
      assert %Ecto.Changeset{} = Events.change_event_type(%EventType{})
    end
  end

  # ===========================================================================
  # COLLABORATORS
  # ===========================================================================

  describe "Collaborator.changeset/2" do
    test "valid with all required fields" do
      changeset = Collaborator.changeset(%Collaborator{}, collaborator_attrs())
      assert changeset.valid?
    end

    test "valid with only name" do
      changeset = Collaborator.changeset(%Collaborator{}, %{name: "Solo Nombre"})
      assert changeset.valid?
    end

    test "invalid without name" do
      changeset = Collaborator.changeset(%Collaborator{}, %{name: nil})
      refute changeset.valid?
      assert changeset.errors[:name]
    end

    test "invalid with name shorter than 2 characters" do
      changeset = Collaborator.changeset(%Collaborator{}, %{name: "A"})
      refute changeset.valid?
      assert changeset.errors[:name]
    end

    test "invalid instagram_handle with spaces" do
      changeset = Collaborator.changeset(%Collaborator{}, collaborator_attrs(%{instagram_handle: "bad handle"}))
      refute changeset.valid?
      assert changeset.errors[:instagram_handle]
    end

    test "invalid instagram_handle with special characters" do
      changeset = Collaborator.changeset(%Collaborator{}, collaborator_attrs(%{instagram_handle: "bad!handle"}))
      refute changeset.valid?
      assert changeset.errors[:instagram_handle]
    end

    test "valid instagram_handle with letters, numbers, dots and underscores" do
      changeset = Collaborator.changeset(%Collaborator{}, collaborator_attrs(%{instagram_handle: "user.name_123"}))
      assert changeset.valid?
    end

    test "instagram_handle is optional" do
      changeset = Collaborator.changeset(%Collaborator{}, collaborator_attrs(%{instagram_handle: nil}))
      assert changeset.valid?
    end
  end

  describe "create_collaborator/1" do
    test "creates a collaborator with valid attrs" do
      assert {:ok, %Collaborator{name: "María García"}} =
               Events.create_collaborator(collaborator_attrs())
    end

    test "new collaborator is active by default" do
      {:ok, c} = Events.create_collaborator(collaborator_attrs())
      assert c.active == true
    end

    test "returns error changeset with invalid attrs" do
      assert {:error, %Ecto.Changeset{}} = Events.create_collaborator(%{name: nil})
    end
  end

  describe "list_collaborators/0" do
    test "returns all collaborators ordered by name" do
      insert_collaborator(%{name: "Zara Luna"})
      insert_collaborator(%{name: "Ana Paz"})

      names = Events.list_collaborators() |> Enum.map(& &1.name)
      assert names == Enum.sort(names)
    end

    test "includes both active and inactive collaborators" do
      {:ok, c} = Events.create_collaborator(collaborator_attrs())
      Events.toggle_collaborator_active(c)

      assert length(Events.list_collaborators()) == 1
    end
  end

  describe "list_active_collaborators/0" do
    test "returns only active collaborators" do
      {:ok, active} = Events.create_collaborator(collaborator_attrs(%{name: "Activo"}))
      {:ok, inactive} = Events.create_collaborator(collaborator_attrs(%{name: "Inactivo"}))
      Events.toggle_collaborator_active(inactive)

      result = Events.list_active_collaborators()
      ids = Enum.map(result, & &1.id)

      assert active.id in ids
      refute inactive.id in ids
    end
  end

  describe "update_collaborator/2" do
    test "updates collaborator fields" do
      c = insert_collaborator()
      assert {:ok, updated} = Events.update_collaborator(c, %{name: "Juan Pérez"})
      assert updated.name == "Juan Pérez"
    end

    test "returns error changeset with invalid attrs" do
      c = insert_collaborator()
      assert {:error, %Ecto.Changeset{}} = Events.update_collaborator(c, %{name: nil})
    end
  end

  describe "toggle_collaborator_active/1" do
    test "deactivates an active collaborator" do
      c = insert_collaborator()
      {:ok, toggled} = Events.toggle_collaborator_active(c)
      assert toggled.active == false
    end

    test "reactivates an inactive collaborator" do
      c = insert_collaborator()
      {:ok, inactive} = Events.toggle_collaborator_active(c)
      {:ok, reactivated} = Events.toggle_collaborator_active(inactive)
      assert reactivated.active == true
    end
  end

  describe "get_collaborator!/1" do
    test "returns collaborator by id" do
      c = insert_collaborator()
      assert Events.get_collaborator!(c.id).id == c.id
    end

    test "raises if not found" do
      assert_raise Ecto.NoResultsError, fn -> Events.get_collaborator!(0) end
    end
  end

  describe "change_collaborator/2" do
    test "returns an empty changeset" do
      assert %Ecto.Changeset{} = Events.change_collaborator(%Collaborator{})
    end
  end

  # ===========================================================================
  # EVENTS
  # ===========================================================================

  describe "Event.changeset/2" do
    test "valid with all required fields" do
      changeset = Event.changeset(%Event{}, event_attrs())
      assert changeset.valid?
    end

    test "invalid without title" do
      changeset = Event.changeset(%Event{}, event_attrs(%{title: nil}))
      refute changeset.valid?
      assert changeset.errors[:title]
    end

    test "invalid without event_date" do
      changeset = Event.changeset(%Event{}, event_attrs(%{event_date: nil}))
      refute changeset.valid?
      assert changeset.errors[:event_date]
    end

    test "invalid without start_time" do
      changeset = Event.changeset(%Event{}, event_attrs(%{start_time: nil}))
      refute changeset.valid?
      assert changeset.errors[:start_time]
    end

    test "invalid without end_time" do
      changeset = Event.changeset(%Event{}, event_attrs(%{end_time: nil}))
      refute changeset.valid?
      assert changeset.errors[:end_time]
    end

    test "invalid when end_time equals start_time" do
      changeset = Event.changeset(%Event{}, event_attrs(%{start_time: ~T[19:00:00], end_time: ~T[19:00:00]}))
      refute changeset.valid?
      assert changeset.errors[:end_time]
    end

    test "invalid when end_time is before start_time" do
      changeset = Event.changeset(%Event{}, event_attrs(%{start_time: ~T[21:00:00], end_time: ~T[19:00:00]}))
      refute changeset.valid?
      assert changeset.errors[:end_time]
    end

    test "valid when end_time is after start_time" do
      changeset = Event.changeset(%Event{}, event_attrs(%{start_time: ~T[18:00:00], end_time: ~T[22:00:00]}))
      assert changeset.valid?
    end

    test "description is optional" do
      changeset = Event.changeset(%Event{}, event_attrs(%{description: nil}))
      assert changeset.valid?
    end

    test "event_type_id is optional" do
      changeset = Event.changeset(%Event{}, event_attrs(%{event_type_id: nil}))
      assert changeset.valid?
    end

    test "tags is optional — event is valid without tags" do
      changeset = Event.changeset(%Event{}, event_attrs(%{tags: nil}))
      assert changeset.valid?
    end

    test "invalid with title shorter than 2 characters" do
      changeset = Event.changeset(%Event{}, event_attrs(%{title: "A"}))
      refute changeset.valid?
      assert changeset.errors[:title]
    end
  end

  describe "create_event/2" do
    test "creates an event with valid attrs" do
      assert {:ok, %Event{title: "Noche de Jazz"}} = Events.create_event(event_attrs())
    end

    test "new event is active by default" do
      {:ok, event} = Events.create_event(event_attrs())
      assert event.active == true
    end

    test "returns error changeset with invalid attrs" do
      assert {:error, %Ecto.Changeset{}} = Events.create_event(%{title: nil})
    end

    test "creates event linked to an event type" do
      et = insert_event_type()
      {:ok, event} = Events.create_event(event_attrs(%{event_type_id: et.id}))
      assert event.event_type.id == et.id
    end

    test "creates event with collaborators" do
      c1 = insert_collaborator(%{name: "Ana"})
      c2 = insert_collaborator(%{name: "Bob"})

      {:ok, event} =
        Events.create_event(event_attrs(), [{c1.id, "Músico principal"}, {c2.id, "Invitado"}])

      collaborator_ids = Enum.map(event.event_collaborators, & &1.collaborator_id)
      assert c1.id in collaborator_ids
      assert c2.id in collaborator_ids
    end

    test "creates event with collaborator roles stored correctly" do
      c = insert_collaborator()

      {:ok, event} = Events.create_event(event_attrs(), [{c.id, "DJ de la noche"}])

      ec = Enum.find(event.event_collaborators, &(&1.collaborator_id == c.id))
      assert ec.role_in_event == "DJ de la noche"
    end

    test "creates event with tags" do
      {:ok, event} = Events.create_event(event_attrs(%{tags: ["música", "jazz", "nocturno"]}))
      assert event.tags == ["música", "jazz", "nocturno"]
    end
  end

  describe "list_events/0" do
    test "returns all events ordered by date descending" do
      yesterday = Date.utc_today() |> Date.add(-1)
      next_week = Date.utc_today() |> Date.add(7)

      insert_event(%{event_date: yesterday, title: "Evento pasado"})
      insert_event(%{event_date: next_week, title: "Evento futuro"})

      [first | _] = Events.list_events()
      assert first.title == "Evento futuro"
    end

    test "includes both active and inactive events" do
      {:ok, event} = Events.create_event(event_attrs())
      Events.toggle_event_active(event)

      assert length(Events.list_events()) == 1
    end

    test "preloads event_type on each event" do
      et = insert_event_type()
      insert_event(%{event_type_id: et.id})

      [event | _] = Events.list_events()
      assert %EventType{} = event.event_type
    end

    test "preloads event_collaborators with collaborators" do
      c = insert_collaborator()
      insert_event(%{}, [{c.id, "Artista"}])

      [event | _] = Events.list_events()
      [ec | _] = event.event_collaborators
      assert %Collaborator{} = ec.collaborator
    end
  end

  describe "list_upcoming_events/0" do
    test "returns active events within the next 15 days" do
      tomorrow = Date.utc_today() |> Date.add(1)
      in_10_days = Date.utc_today() |> Date.add(10)

      {:ok, e1} = Events.create_event(event_attrs(%{event_date: tomorrow, title: "Mañana"}))
      {:ok, e2} = Events.create_event(event_attrs(%{event_date: in_10_days, title: "En 10 días"}))

      ids = Events.list_upcoming_events() |> Enum.map(& &1.id)
      assert e1.id in ids
      assert e2.id in ids
    end

    test "excludes events beyond 15 days" do
      in_20_days = Date.utc_today() |> Date.add(20)
      {:ok, far} = Events.create_event(event_attrs(%{event_date: in_20_days, title: "Lejano"}))

      ids = Events.list_upcoming_events() |> Enum.map(& &1.id)
      refute far.id in ids
    end

    test "excludes past events" do
      yesterday = cdmx_today() |> Date.add(-1)
      {:ok, past} = Events.create_event(event_attrs(%{event_date: yesterday, title: "Pasado"}))

      ids = Events.list_upcoming_events() |> Enum.map(& &1.id)
      refute past.id in ids
    end

    test "excludes inactive events even if within 15 days" do
      tomorrow = Date.utc_today() |> Date.add(1)
      {:ok, event} = Events.create_event(event_attrs(%{event_date: tomorrow}))
      Events.toggle_event_active(event)

      ids = Events.list_upcoming_events() |> Enum.map(& &1.id)
      refute event.id in ids
    end

    test "returns events ordered by date and start_time ascending" do
      in_5 = Date.utc_today() |> Date.add(5)
      in_3 = Date.utc_today() |> Date.add(3)

      {:ok, later} = Events.create_event(event_attrs(%{event_date: in_5, title: "Más tarde", start_time: ~T[20:00:00], end_time: ~T[22:00:00]}))
      {:ok, sooner} = Events.create_event(event_attrs(%{event_date: in_3, title: "Antes", start_time: ~T[18:00:00], end_time: ~T[20:00:00]}))

      [first | _] = Events.list_upcoming_events()
      assert first.id == sooner.id
      _ = later
    end
  end

  describe "list_past_events/0" do
    test "returns events from past dates" do
      yesterday = cdmx_today() |> Date.add(-1)
      {:ok, past} = Events.create_event(event_attrs(%{event_date: yesterday, title: "Pasado"}))

      ids = Events.list_past_events() |> Enum.map(& &1.id)
      assert past.id in ids
    end

    test "excludes future events" do
      tomorrow = Date.utc_today() |> Date.add(1)
      {:ok, future} = Events.create_event(event_attrs(%{event_date: tomorrow, title: "Futuro"}))

      ids = Events.list_past_events() |> Enum.map(& &1.id)
      refute future.id in ids
    end

    test "excludes inactive events" do
      yesterday = cdmx_today() |> Date.add(-1)
      {:ok, event} = Events.create_event(event_attrs(%{event_date: yesterday}))
      Events.toggle_event_active(event)

      ids = Events.list_past_events() |> Enum.map(& &1.id)
      refute event.id in ids
    end

    test "returns most recent events first" do
      two_days_ago = cdmx_today() |> Date.add(-2)
      five_days_ago = cdmx_today() |> Date.add(-5)

      {:ok, recent} = Events.create_event(event_attrs(%{event_date: two_days_ago, title: "Reciente"}))
      {:ok, older} = Events.create_event(event_attrs(%{event_date: five_days_ago, title: "Antiguo"}))

      [first | _] = Events.list_past_events()
      assert first.id == recent.id
      _ = older
    end

    test "limits to 20 results" do
      yesterday = cdmx_today() |> Date.add(-1)

      for i <- 1..25 do
        Events.create_event(event_attrs(%{event_date: yesterday, title: "Evento #{i}"}))
      end

      assert length(Events.list_past_events()) == 20
    end
  end

  describe "get_current_event/0" do
    test "returns nil when no event is happening right now" do
      # Future event — not started yet
      tomorrow = Date.utc_today() |> Date.add(1)
      insert_event(%{event_date: tomorrow})

      assert Events.get_current_event() == nil
    end

    test "returns nil when all events are inactive" do
      yesterday = Date.utc_today() |> Date.add(-1)
      {:ok, event} = Events.create_event(event_attrs(%{event_date: yesterday}))
      Events.toggle_event_active(event)

      assert Events.get_current_event() == nil
    end
  end

  describe "update_event/3" do
    test "updates event fields" do
      event = insert_event()
      assert {:ok, updated} = Events.update_event(event, %{title: "Tarde de Bossa Nova"})
      assert updated.title == "Tarde de Bossa Nova"
    end

    test "returns error changeset with invalid attrs" do
      event = insert_event()
      assert {:error, %Ecto.Changeset{}} = Events.update_event(event, %{title: nil})
    end

    test "replaces collaborators on update" do
      c1 = insert_collaborator(%{name: "Ana"})
      c2 = insert_collaborator(%{name: "Bob"})

      event = insert_event(%{}, [{c1.id, "Artista"}])

      # Replace c1 with c2
      {:ok, updated} = Events.update_event(event, %{title: event.title}, [{c2.id, "Nuevo artista"}])

      collaborator_ids = Enum.map(updated.event_collaborators, & &1.collaborator_id)
      refute c1.id in collaborator_ids
      assert c2.id in collaborator_ids
    end

    test "removes all collaborators when updated with empty list" do
      c = insert_collaborator()
      event = insert_event(%{}, [{c.id, "Artista"}])

      {:ok, updated} = Events.update_event(event, %{title: event.title}, [])
      assert updated.event_collaborators == []
    end

    test "updates event tags" do
      event = insert_event(%{tags: ["música"]})
      {:ok, updated} = Events.update_event(event, %{tags: ["jazz", "bossa nova"]})
      assert updated.tags == ["jazz", "bossa nova"]
    end
  end

  describe "toggle_event_active/1" do
    test "deactivates an active event" do
      event = insert_event()
      {:ok, toggled} = Events.toggle_event_active(event)
      assert toggled.active == false
    end

    test "reactivates an inactive event" do
      event = insert_event()
      {:ok, inactive} = Events.toggle_event_active(event)
      {:ok, reactivated} = Events.toggle_event_active(inactive)
      assert reactivated.active == true
    end
  end

  describe "get_event!/1" do
    test "returns event by id with preloads" do
      et = insert_event_type()
      c = insert_collaborator()
      event = insert_event(%{event_type_id: et.id}, [{c.id, "Colaborador"}])

      fetched = Events.get_event!(event.id)
      assert fetched.id == event.id
      assert %EventType{} = fetched.event_type
      assert length(fetched.event_collaborators) == 1
    end

    test "raises if not found" do
      assert_raise Ecto.NoResultsError, fn -> Events.get_event!(0) end
    end
  end

  describe "change_event/2" do
    test "returns an empty changeset" do
      assert %Ecto.Changeset{} = Events.change_event(%Event{})
    end

    test "returns a changeset with attrs applied" do
      cs = Events.change_event(%Event{}, event_attrs())
      assert cs.changes[:title] == "Noche de Jazz"
    end
  end

  # ===========================================================================
  # EVENT COLLABORATOR (join table)
  # ===========================================================================

  describe "EventCollaborator join table" do
    test "prevents duplicate collaborator on same event (unique DB index)" do
      c = insert_collaborator()
      event = insert_event(%{}, [{c.id, "Artista"}])

      assert_raise Ecto.ConstraintError, fn ->
        %EventCollaborator{}
        |> EventCollaborator.changeset(%{
          event_id: event.id,
          collaborator_id: c.id,
          role_in_event: "Otro rol"
        })
        |> CRC.Repo.insert!()
      end
    end
  end
end
