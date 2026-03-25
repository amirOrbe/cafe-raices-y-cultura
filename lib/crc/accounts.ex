defmodule CRC.Accounts do
  @moduledoc """
  Context that manages system users.

  Only an administrator can create or change the status of other users.
  Authentication is done via email and password.
  """

  import Ecto.Query, warn: false

  alias CRC.Accounts.User
  alias CRC.Repo

  # ---------------------------------------------------------------------------
  # Queries
  # ---------------------------------------------------------------------------

  @doc "Returns all users sorted alphabetically by name."
  @spec list_users() :: [User.t()]
  def list_users do
    User
    |> order_by(:name)
    |> Repo.all()
  end

  @doc "Gets a user by id. Returns `nil` if not found."
  @spec get_user(integer()) :: User.t() | nil
  def get_user(id), do: Repo.get(User, id)

  @doc "Gets a user by id. Raises `Ecto.NoResultsError` if not found."
  @spec get_user!(integer()) :: User.t()
  def get_user!(id), do: Repo.get!(User, id)

  # ---------------------------------------------------------------------------
  # User management — admin only
  # ---------------------------------------------------------------------------

  @doc """
  Creates a new user.

  Requires the caller to be an administrator; otherwise returns
  `{:error, :unauthorized}`.
  """
  @spec create_user(User.t(), map()) :: {:ok, User.t()} | {:error, :unauthorized} | {:error, Ecto.Changeset.t()}
  def create_user(%User{role: "admin"}, attrs) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
    |> broadcast_user_change()
  end

  def create_user(%User{}, _attrs), do: {:error, :unauthorized}

  @doc """
  Updates an existing user's data.

  Requires the caller to be an administrator; otherwise returns
  `{:error, :unauthorized}`.
  """
  @spec update_user(User.t(), User.t(), map()) ::
          {:ok, User.t()} | {:error, :unauthorized} | {:error, Ecto.Changeset.t()}
  def update_user(%User{role: "admin"}, %User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
    |> broadcast_user_change()
  end

  def update_user(%User{}, _user, _attrs), do: {:error, :unauthorized}

  @doc """
  Deactivates a user (is_active = false).

  Requires the caller to be an administrator and not the same user.
  """
  @spec deactivate_user(User.t(), User.t()) ::
          {:ok, User.t()}
          | {:error, :unauthorized}
          | {:error, :cannot_deactivate_self}
          | {:error, Ecto.Changeset.t()}
  def deactivate_user(%User{role: "admin", id: admin_id}, %User{id: id})
      when admin_id == id do
    {:error, :cannot_deactivate_self}
  end

  def deactivate_user(%User{role: "admin"}, %User{} = user) do
    user
    |> User.status_changeset(%{is_active: false})
    |> Repo.update()
    |> broadcast_user_change()
  end

  def deactivate_user(%User{}, _user), do: {:error, :unauthorized}

  @doc """
  Activates a previously deactivated user (is_active = true).

  Requires the caller to be an administrator.
  """
  @spec activate_user(User.t(), User.t()) ::
          {:ok, User.t()} | {:error, :unauthorized} | {:error, Ecto.Changeset.t()}
  def activate_user(%User{role: "admin"}, %User{} = user) do
    user
    |> User.status_changeset(%{is_active: true})
    |> Repo.update()
    |> broadcast_user_change()
  end

  def activate_user(%User{}, _user), do: {:error, :unauthorized}

  # ---------------------------------------------------------------------------
  # Authentication
  # ---------------------------------------------------------------------------

  @doc """
  Authenticates a user by email and password.

  Returns:
  - `{:ok, user}` if credentials are valid and the user is active.
  - `{:error, :inactive_user}` if the account is deactivated.
  - `{:error, :invalid_credentials}` if email or password do not match.

  Always runs hash verification to prevent timing attacks.
  """
  @spec authenticate_user(String.t(), String.t()) ::
          {:ok, User.t()} | {:error, :invalid_credentials | :inactive_user}
  def authenticate_user(email, password) do
    user = Repo.get_by(User, email: email)
    do_authenticate(user, password)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp broadcast_user_change({:ok, user} = result) do
    Phoenix.PubSub.broadcast(CRC.PubSub, "admin:users", {:user_changed, user})
    result
  end

  defp broadcast_user_change(error), do: error

  defp do_authenticate(nil, _password) do
    # Prevents timing attacks: always runs a dummy verification
    Bcrypt.no_user_verify()
    {:error, :invalid_credentials}
  end

  defp do_authenticate(%User{is_active: false}, _password) do
    {:error, :inactive_user}
  end

  defp do_authenticate(%User{password_hash: hash} = user, password) do
    if Bcrypt.verify_pass(password, hash) do
      {:ok, user}
    else
      {:error, :invalid_credentials}
    end
  end
end
