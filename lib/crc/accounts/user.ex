defmodule CRC.Accounts.User do
  @moduledoc """
  Schema representing a system user.

  Available roles:
  - `"admin"` — full access, can manage users and the system.
  - `"empleado"` — restaurant staff; must have at least one assigned station.
  - `"cliente"` — external customer (reservations, own orders).

  Stations (`stations`) — only apply to employees; an employee may belong to
  more than one station (e.g., a waiter who also covers the bar):
  - `"cocina"` — prepares dishes.
  - `"barra"` — prepares drinks.
  - `"sala"` — serves tables; can see order status without going to the station.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @roles ~w(admin empleado cliente)
  @stations ~w(cocina barra sala)
  @min_password_length 8

  schema "users" do
    field :name, :string
    field :email, :string
    field :phone, :string
    field :role, :string, default: "cliente"
    field :stations, {:array, :string}, default: []
    field :avatar_url, :string
    field :birthday, :date
    field :qr_token, :string
    field :is_active, :boolean, default: true
    field :confirmed_at, :utc_datetime
    field :password_hash, :string
    field :password, :string, virtual: true

    timestamps(type: :utc_datetime)
  end

  @doc """
  Main changeset for creating and updating users.
  Password is required on creation (when `password_hash` does not yet exist).
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :email, :phone, :role, :stations, :is_active, :password, :avatar_url, :birthday])
    |> normalize_stations()
    |> update_change(:name, &CRC.Utils.title_case/1)
    |> validate_required([:name, :email, :role], message: "no puede estar en blanco")
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/, message: "tiene formato inválido")
    |> validate_inclusion(:role, @roles, message: "no es una opción válida")
    |> validate_password()
    |> validate_stations()
    |> unique_constraint(:email, message: "ya está en uso")
    |> hash_password()
  end

  @doc """
  Changeset exclusively for updating the `is_active` status.
  Does not require a password.
  """
  @spec status_changeset(t(), map()) :: Ecto.Changeset.t()
  def status_changeset(user, attrs) do
    user
    |> cast(attrs, [:is_active])
    |> validate_required([:is_active])
  end

  @doc "Returns the list of valid station identifiers."
  def valid_stations, do: @stations

  @doc """
  Changeset for a user updating their own profile.
  Only allows changing name and avatar_url — role, email, stations, etc. are locked.
  """
  @spec profile_changeset(t(), map()) :: Ecto.Changeset.t()
  def profile_changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :avatar_url])
    |> update_change(:name, &CRC.Utils.title_case/1)
    |> validate_required([:name], message: "no puede estar en blanco")
    |> validate_length(:name,
      min: 2,
      max: 100,
      message: "debe tener al menos %{count} caracteres"
    )
  end

  @doc """
  Changeset for public self-registration. Role is always forced to "cliente"
  and a unique QR token is generated automatically.
  """
  @spec registration_changeset(t(), map()) :: Ecto.Changeset.t()
  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :email, :phone, :birthday, :password])
    |> put_change(:role, "cliente")
    |> put_change(:stations, [])
    |> put_change(:qr_token, Ecto.UUID.generate())
    |> update_change(:name, &CRC.Utils.title_case/1)
    |> validate_required([:name, :email, :password],
      message: "no puede estar en blanco"
    )
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/,
      message: "tiene formato inválido"
    )
    |> validate_length(:password,
      min: @min_password_length,
      message: "debe tener al menos %{count} caracteres"
    )
    |> unique_constraint(:email, message: "ya está en uso")
    |> unique_constraint(:qr_token)
    |> hash_password()
  end

  @doc """
  Changeset for a client updating their own profile fields.
  """
  @spec client_profile_changeset(t(), map()) :: Ecto.Changeset.t()
  def client_profile_changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :phone, :birthday])
    |> update_change(:name, &CRC.Utils.title_case/1)
    |> validate_required([:name], message: "no puede estar en blanco")
    |> validate_length(:name,
      min: 2,
      max: 100,
      message: "debe tener al menos %{count} caracteres"
    )
  end

  @doc """
  Changeset for updating only the password.
  Caller must have already verified the current password before using this.
  """
  @spec password_changeset(t(), map()) :: Ecto.Changeset.t()
  def password_changeset(user, attrs) do
    user
    |> cast(attrs, [:password])
    |> validate_required([:password], message: "no puede estar en blanco")
    |> validate_length(:password,
      min: @min_password_length,
      message: "debe tener al menos %{count} caracteres"
    )
    |> hash_password()
  end

  @doc "Changeset that marks a user's email as confirmed."
  @spec confirm_changeset(t()) :: Ecto.Changeset.t()
  def confirm_changeset(user) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    change(user, confirmed_at: now)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Filters out blank strings that HTML forms submit for unchecked checkboxes.
  defp normalize_stations(changeset) do
    case get_change(changeset, :stations) do
      nil ->
        changeset

      stations ->
        clean = stations |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == "")) |> Enum.uniq()
        put_change(changeset, :stations, clean)
    end
  end

  defp validate_password(changeset) do
    # Password is only required on creation (when no hash is stored yet)
    if is_nil(get_field(changeset, :password_hash)) do
      changeset
      |> validate_required([:password], message: "no puede estar en blanco")
      |> validate_length(:password,
        min: @min_password_length,
        message: "debe tener al menos %{count} caracteres"
      )
    else
      validate_length(changeset, :password,
        min: @min_password_length,
        message: "debe tener al menos %{count} caracteres"
      )
    end
  end

  defp validate_stations(changeset) do
    role = get_field(changeset, :role)
    stations = get_field(changeset, :stations) || []

    cond do
      role == "empleado" and stations == [] ->
        add_error(changeset, :stations, "debe asignarse al menos una estación")

      role == "empleado" ->
        invalid = Enum.reject(stations, &(&1 in @stations))

        if invalid == [] do
          changeset
        else
          add_error(
            changeset,
            :stations,
            "contiene opciones inválidas: #{Enum.join(invalid, ", ")}"
          )
        end

      role in ~w(admin cliente) and stations != [] ->
        put_change(changeset, :stations, [])

      true ->
        changeset
    end
  end

  defp hash_password(changeset) do
    case fetch_change(changeset, :password) do
      {:ok, password} when is_binary(password) ->
        put_change(changeset, :password_hash, Bcrypt.hash_pwd_salt(password))

      _ ->
        changeset
    end
  end
end
