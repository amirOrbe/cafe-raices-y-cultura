defmodule CRC.Accounts.User do
  @moduledoc """
  Schema representing a system user.

  Available roles:
  - `"admin"` — full access, can manage users and the system.
  - `"empleado"` — restaurant staff; must have an assigned station.
  - `"cliente"` — external customer (reservations, own orders).

  Stations (`station`) — only applies to employees:
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
    field :station, :string
    field :is_active, :boolean, default: true
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
    |> cast(attrs, [:name, :email, :phone, :role, :station, :is_active, :password])
    |> normalize_empty_station()
    |> validate_required([:name, :email, :role])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/,
      message: "tiene formato inválido"
    )
    |> validate_inclusion(:role, @roles, message: "no es una opción válida")
    |> validate_password()
    |> validate_station()
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

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp normalize_empty_station(changeset) do
    case get_change(changeset, :station) do
      "" -> put_change(changeset, :station, nil)
      _ -> changeset
    end
  end

  defp validate_password(changeset) do
    # Password is only required on creation (when no hash is stored yet)
    if is_nil(get_field(changeset, :password_hash)) do
      changeset
      |> validate_required([:password])
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

  defp validate_station(changeset) do
    role = get_field(changeset, :role)
    station = get_field(changeset, :station)

    cond do
      role == "empleado" and is_nil(station) ->
        add_error(changeset, :station, "no puede estar en blanco")

      role == "empleado" and station not in @stations ->
        add_error(changeset, :station, "no es una opción válida")

      role in ~w(admin cliente) and not is_nil(station) ->
        add_error(changeset, :station, "debe estar en blanco para este rol")

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
