defmodule CRC.Events do
  @moduledoc """
  Bounded context for events and collaborations management.

  Handles event types, collaborators, and events (with their collaborators).
  Events track date/time windows and can be filtered by status (upcoming, past, current).
  """

  import Ecto.Query

  alias CRC.Repo
  alias CRC.Events.Collaborator
  alias CRC.Events.Event
  alias CRC.Events.EventCollaborator
  alias CRC.Events.EventType

  # ---------------------------------------------------------------------------
  # Event Types
  # ---------------------------------------------------------------------------

  @doc "Returns all event types ordered by name."
  @spec list_event_types() :: [EventType.t()]
  def list_event_types do
    Repo.all(from et in EventType, order_by: [asc: et.name])
  end

  @doc "Returns active event types ordered by name."
  @spec list_active_event_types() :: [EventType.t()]
  def list_active_event_types do
    Repo.all(from et in EventType, where: et.active == true, order_by: [asc: et.name])
  end

  @doc "Gets an event type by id. Raises if not found."
  @spec get_event_type!(integer()) :: EventType.t()
  def get_event_type!(id), do: Repo.get!(EventType, id)

  @doc "Creates an event type."
  @spec create_event_type(map()) :: {:ok, EventType.t()} | {:error, Ecto.Changeset.t()}
  def create_event_type(attrs) do
    %EventType{}
    |> EventType.changeset(attrs)
    |> Repo.insert()
    |> broadcast_event_type_change()
  end

  @doc "Updates an event type."
  @spec update_event_type(EventType.t(), map()) ::
          {:ok, EventType.t()} | {:error, Ecto.Changeset.t()}
  def update_event_type(%EventType{} = event_type, attrs) do
    event_type
    |> EventType.changeset(attrs)
    |> Repo.update()
    |> broadcast_event_type_change()
  end

  @doc "Toggles the active status of an event type."
  @spec toggle_event_type_active(EventType.t()) ::
          {:ok, EventType.t()} | {:error, Ecto.Changeset.t()}
  def toggle_event_type_active(%EventType{} = event_type) do
    event_type
    |> EventType.changeset(%{active: !event_type.active})
    |> Repo.update()
    |> broadcast_event_type_change()
  end

  @doc "Returns a changeset for the given event type."
  @spec change_event_type(EventType.t(), map()) :: Ecto.Changeset.t()
  def change_event_type(%EventType{} = event_type, attrs \\ %{}) do
    EventType.changeset(event_type, attrs)
  end

  # ---------------------------------------------------------------------------
  # Collaborators
  # ---------------------------------------------------------------------------

  @doc "Returns all collaborators ordered by name."
  @spec list_collaborators() :: [Collaborator.t()]
  def list_collaborators do
    Repo.all(from c in Collaborator, order_by: [asc: c.name])
  end

  @doc "Returns active collaborators ordered by name."
  @spec list_active_collaborators() :: [Collaborator.t()]
  def list_active_collaborators do
    Repo.all(from c in Collaborator, where: c.active == true, order_by: [asc: c.name])
  end

  @doc "Gets a collaborator by id. Raises if not found."
  @spec get_collaborator!(integer()) :: Collaborator.t()
  def get_collaborator!(id), do: Repo.get!(Collaborator, id)

  @doc "Creates a collaborator."
  @spec create_collaborator(map()) :: {:ok, Collaborator.t()} | {:error, Ecto.Changeset.t()}
  def create_collaborator(attrs) do
    %Collaborator{}
    |> Collaborator.changeset(attrs)
    |> Repo.insert()
    |> broadcast_collaborator_change()
  end

  @doc "Updates a collaborator."
  @spec update_collaborator(Collaborator.t(), map()) ::
          {:ok, Collaborator.t()} | {:error, Ecto.Changeset.t()}
  def update_collaborator(%Collaborator{} = collaborator, attrs) do
    collaborator
    |> Collaborator.changeset(attrs)
    |> Repo.update()
    |> broadcast_collaborator_change()
  end

  @doc "Toggles the active status of a collaborator."
  @spec toggle_collaborator_active(Collaborator.t()) ::
          {:ok, Collaborator.t()} | {:error, Ecto.Changeset.t()}
  def toggle_collaborator_active(%Collaborator{} = collaborator) do
    collaborator
    |> Collaborator.changeset(%{active: !collaborator.active})
    |> Repo.update()
    |> broadcast_collaborator_change()
  end

  @doc "Returns a changeset for the given collaborator."
  @spec change_collaborator(Collaborator.t(), map()) :: Ecto.Changeset.t()
  def change_collaborator(%Collaborator{} = collaborator, attrs \\ %{}) do
    Collaborator.changeset(collaborator, attrs)
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @doc """
  Returns all events with event_type and collaborators preloaded,
  ordered by event_date descending.
  """
  @spec list_events() :: [Event.t()]
  def list_events do
    Repo.all(
      from e in Event,
        left_join: et in assoc(e, :event_type),
        left_join: ec in assoc(e, :event_collaborators),
        left_join: c in assoc(ec, :collaborator),
        preload: [event_type: et, event_collaborators: {ec, collaborator: c}],
        order_by: [desc: e.event_date, desc: e.start_time]
    )
  end

  @doc """
  Returns upcoming events (within next 15 days from CDMX time),
  active only, preloaded.
  """
  @spec list_upcoming_events() :: [Event.t()]
  def list_upcoming_events do
    now = cdmx_now()
    today = NaiveDateTime.to_date(now)
    cdmx_time = NaiveDateTime.to_time(now)
    window_end = Date.add(today, 15)

    Repo.all(
      from e in Event,
        left_join: et in assoc(e, :event_type),
        left_join: ec in assoc(e, :event_collaborators),
        left_join: c in assoc(ec, :collaborator),
        where:
          e.active == true and
            e.event_date >= ^today and
            e.event_date <= ^window_end and
            not (e.event_date == ^today and e.end_time < ^cdmx_time),
        preload: [event_type: et, event_collaborators: {ec, collaborator: c}],
        order_by: [asc: e.event_date, asc: e.start_time]
    )
  end

  @doc """
  Returns past events (date < today OR date == today AND end_time < now),
  active only, most recent 20.
  """
  @spec list_past_events() :: [Event.t()]
  def list_past_events do
    now = cdmx_now()
    today = NaiveDateTime.to_date(now)
    cdmx_time = NaiveDateTime.to_time(now)

    Repo.all(
      from e in Event,
        left_join: et in assoc(e, :event_type),
        left_join: ec in assoc(e, :event_collaborators),
        left_join: c in assoc(ec, :collaborator),
        where:
          e.active == true and
            (e.event_date < ^today or
               (e.event_date == ^today and e.end_time < ^cdmx_time)),
        preload: [event_type: et, event_collaborators: {ec, collaborator: c}],
        order_by: [desc: e.event_date, desc: e.start_time],
        limit: 20
    )
  end

  @doc """
  Returns the first event happening right now (CDMX time),
  or nil if none is active at this moment.
  """
  @spec get_current_event() :: Event.t() | nil
  def get_current_event do
    now = cdmx_now()
    today = NaiveDateTime.to_date(now)
    cdmx_time = NaiveDateTime.to_time(now)

    Repo.one(
      from e in Event,
        left_join: et in assoc(e, :event_type),
        left_join: ec in assoc(e, :event_collaborators),
        left_join: c in assoc(ec, :collaborator),
        where:
          e.active == true and
            e.event_date == ^today and
            e.start_time <= ^cdmx_time and
            e.end_time > ^cdmx_time,
        preload: [event_type: et, event_collaborators: {ec, collaborator: c}],
        limit: 1,
        order_by: [asc: e.start_time]
    )
  end

  @doc "Gets an event by id with event_type and event_collaborators preloaded. Raises if not found."
  @spec get_event!(integer()) :: Event.t()
  def get_event!(id) do
    Event
    |> Repo.get!(id)
    |> Repo.preload([:event_type, event_collaborators: :collaborator])
  end

  @doc """
  Creates an event along with its collaborator associations.

  `collaborators_with_roles` is a list of `{collaborator_id, role}` tuples.
  """
  @spec create_event(map(), list()) :: {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
  def create_event(attrs, collaborators_with_roles \\ []) do
    result =
      %Event{}
      |> Event.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, event} ->
        insert_event_collaborators(event.id, collaborators_with_roles)
        event = get_event!(event.id)
        broadcast_event_change({:ok, event})

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Updates an event and replaces all its collaborator associations.

  `collaborators_with_roles` is a list of `{collaborator_id, role}` tuples.
  """
  @spec update_event(Event.t(), map(), list()) :: {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
  def update_event(%Event{} = event, attrs, collaborators_with_roles \\ []) do
    result =
      event
      |> Event.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, updated_event} ->
        Repo.delete_all(from ec in EventCollaborator, where: ec.event_id == ^updated_event.id)
        insert_event_collaborators(updated_event.id, collaborators_with_roles)
        updated_event = get_event!(updated_event.id)
        broadcast_event_change({:ok, updated_event})

      {:error, _} = error ->
        error
    end
  end

  @doc "Toggles the active status of an event."
  @spec toggle_event_active(Event.t()) :: {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
  def toggle_event_active(%Event{} = event) do
    event
    |> Event.changeset(%{active: !event.active})
    |> Repo.update()
    |> broadcast_event_change()
  end

  @doc "Returns a changeset for the given event."
  @spec change_event(Event.t(), map()) :: Ecto.Changeset.t()
  def change_event(%Event{} = event, attrs \\ %{}) do
    Event.changeset(event, attrs)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp insert_event_collaborators(_event_id, []), do: :ok

  defp insert_event_collaborators(event_id, collaborators_with_roles) do
    Enum.each(collaborators_with_roles, fn {collaborator_id, role} ->
      %EventCollaborator{}
      |> EventCollaborator.changeset(%{
        event_id: event_id,
        collaborator_id: collaborator_id,
        role_in_event: role
      })
      |> Repo.insert()
    end)
  end

  # Returns CDMX time (UTC-6) as a NaiveDateTime for date/time comparisons.
  defp cdmx_now do
    DateTime.utc_now()
    |> DateTime.add(-6 * 3600, :second)
    |> DateTime.to_naive()
  end

  defp broadcast_event_type_change({:ok, event_type} = result) do
    Phoenix.PubSub.broadcast(CRC.PubSub, "admin:event_types", {:event_type_changed, event_type})
    result
  end

  defp broadcast_event_type_change(error), do: error

  defp broadcast_collaborator_change({:ok, collaborator} = result) do
    Phoenix.PubSub.broadcast(
      CRC.PubSub,
      "admin:collaborators",
      {:collaborator_changed, collaborator}
    )

    result
  end

  defp broadcast_collaborator_change(error), do: error

  defp broadcast_event_change({:ok, event} = result) do
    Phoenix.PubSub.broadcast(CRC.PubSub, "admin:events", {:event_changed, event})
    result
  end

  defp broadcast_event_change(error), do: error
end
