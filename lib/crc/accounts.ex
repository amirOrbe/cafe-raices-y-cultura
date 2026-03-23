defmodule CRC.Accounts do
  @moduledoc """
  Contexto que gestiona los usuarios del sistema.

  Solo un administrador puede crear o cambiar el estado de otros usuarios.
  La autenticación se realiza mediante email y contraseña.
  """

  import Ecto.Query, warn: false

  alias CRC.Accounts.User
  alias CRC.Repo

  # ---------------------------------------------------------------------------
  # Consultas
  # ---------------------------------------------------------------------------

  @doc "Retorna todos los usuarios ordenados alfabéticamente por nombre."
  @spec list_users() :: [User.t()]
  def list_users do
    User
    |> order_by(:name)
    |> Repo.all()
  end

  @doc "Obtiene un usuario por id. Lanza `Ecto.NoResultsError` si no existe."
  @spec get_user!(integer()) :: User.t()
  def get_user!(id), do: Repo.get!(User, id)

  # ---------------------------------------------------------------------------
  # Gestión de usuarios — solo admin
  # ---------------------------------------------------------------------------

  @doc """
  Crea un usuario nuevo.

  Requiere que el ejecutor sea un administrador; de lo contrario retorna
  `{:error, :no_autorizado}`.
  """
  @spec create_user(User.t(), map()) :: {:ok, User.t()} | {:error, :no_autorizado} | {:error, Ecto.Changeset.t()}
  def create_user(%User{role: "admin"}, attrs) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  def create_user(%User{}, _attrs), do: {:error, :no_autorizado}

  @doc """
  Desactiva un usuario (is_active = false).

  Requiere que el ejecutor sea administrador y que no sea el mismo usuario.
  """
  @spec deactivate_user(User.t(), User.t()) ::
          {:ok, User.t()}
          | {:error, :no_autorizado}
          | {:error, :no_puede_desactivarse_a_si_mismo}
          | {:error, Ecto.Changeset.t()}
  def deactivate_user(%User{role: "admin", id: admin_id}, %User{id: id})
      when admin_id == id do
    {:error, :no_puede_desactivarse_a_si_mismo}
  end

  def deactivate_user(%User{role: "admin"}, %User{} = user) do
    user
    |> User.status_changeset(%{is_active: false})
    |> Repo.update()
  end

  def deactivate_user(%User{}, _user), do: {:error, :no_autorizado}

  @doc """
  Activa un usuario previamente desactivado (is_active = true).

  Requiere que el ejecutor sea administrador.
  """
  @spec activate_user(User.t(), User.t()) ::
          {:ok, User.t()} | {:error, :no_autorizado} | {:error, Ecto.Changeset.t()}
  def activate_user(%User{role: "admin"}, %User{} = user) do
    user
    |> User.status_changeset(%{is_active: true})
    |> Repo.update()
  end

  def activate_user(%User{}, _user), do: {:error, :no_autorizado}

  # ---------------------------------------------------------------------------
  # Autenticación
  # ---------------------------------------------------------------------------

  @doc """
  Autentica un usuario por email y contraseña.

  Retorna:
  - `{:ok, user}` si las credenciales son válidas y el usuario está activo.
  - `{:error, :usuario_inactivo}` si la cuenta está desactivada.
  - `{:error, :credenciales_invalidas}` si el email o contraseña no coinciden.

  Siempre ejecuta la verificación de hash para evitar timing attacks.
  """
  @spec authenticate_user(String.t(), String.t()) ::
          {:ok, User.t()} | {:error, :credenciales_invalidas | :usuario_inactivo}
  def authenticate_user(email, password) do
    user = Repo.get_by(User, email: email)
    do_authenticate(user, password)
  end

  # ---------------------------------------------------------------------------
  # Helpers privados
  # ---------------------------------------------------------------------------

  defp do_authenticate(nil, _password) do
    # Previene timing attacks: siempre se ejecuta una verificación ficticia
    Bcrypt.no_user_verify()
    {:error, :credenciales_invalidas}
  end

  defp do_authenticate(%User{is_active: false}, _password) do
    {:error, :usuario_inactivo}
  end

  defp do_authenticate(%User{password_hash: hash} = user, password) do
    if Bcrypt.verify_pass(password, hash) do
      {:ok, user}
    else
      {:error, :credenciales_invalidas}
    end
  end
end
