defmodule CRC.Accounts.User do
  @moduledoc """
  Schema que representa a un usuario del sistema.

  Roles disponibles:
  - `"admin"` — acceso total, puede gestionar usuarios y el sistema.
  - `"empleado"` — personal del restaurante; debe tener una estación asignada.
  - `"cliente"` — cliente externo (reservas, pedidos propios).

  Estaciones (`station`) — solo aplica a empleados:
  - `"cocina"` — prepara platos.
  - `"barra"` — prepara bebidas.
  - `"sala"` — sirve mesas; puede ver el estado de sus pedidos sin ir a la estación.
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
  Changeset principal para crear y actualizar usuarios.
  La contraseña es obligatoria al crear (cuando `password_hash` aún no existe).
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :email, :phone, :role, :station, :is_active, :password])
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
  Changeset exclusivo para actualizar el estado `is_active`.
  No requiere contraseña.
  """
  @spec status_changeset(t(), map()) :: Ecto.Changeset.t()
  def status_changeset(user, attrs) do
    user
    |> cast(attrs, [:is_active])
    |> validate_required([:is_active])
  end

  # ---------------------------------------------------------------------------
  # Helpers privados
  # ---------------------------------------------------------------------------

  defp validate_password(changeset) do
    # Solo es requerida al crear (cuando aún no hay hash guardado)
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
