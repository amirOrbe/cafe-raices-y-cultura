defmodule CRC.Accounts do
  @moduledoc """
  Context that manages system users.

  Only an administrator can create or change the status of other users.
  Authentication is done via email and password.
  """

  import Ecto.Query, warn: false

  alias CRC.Accounts.{User, EmployeeRecognition, UserEmail}
  alias CRC.{Mailer, Repo}

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
  @spec create_user(User.t(), map()) ::
          {:ok, User.t()} | {:error, :unauthorized} | {:error, Ecto.Changeset.t()}
  def create_user(%User{role: "admin"}, attrs) do
    result =
      %User{}
      |> User.changeset(attrs)
      |> Repo.insert()
      |> broadcast_user_change()

    case result do
      {:ok, user} ->
        Task.start(fn -> deliver_welcome_email(user) end)
        {:ok, user}

      error ->
        error
    end
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
  Updates a user's own profile (name and avatar only).
  No role, email, or station changes — those are admin-only.
  """
  @spec update_own_profile(User.t(), map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def update_own_profile(%User{} = user, attrs) do
    user
    |> User.profile_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates a user's own password.
  The caller must have already verified the current password via `authenticate_user/2`
  before calling this function.
  """
  @spec update_own_password(User.t(), String.t()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def update_own_password(%User{} = user, new_password) do
    user
    |> User.password_changeset(%{"password" => new_password})
    |> Repo.update()
  end

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

  @doc """
  Marks a user's email address as confirmed.

  Called from the email-confirmation LiveView when the signed token is valid.
  Returns `{:ok, user}` or `{:error, changeset}`.
  """
  @spec confirm_user_email(User.t()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def confirm_user_email(%User{} = user) do
    user
    |> User.confirm_changeset()
    |> Repo.update()
  end

  # ---------------------------------------------------------------------------
  # Employee recognitions
  # ---------------------------------------------------------------------------

  @doc """
  Awards a recognition to an employee.

  `kind` must be one of: "top_sales", "top_speed", "custom".
  `period_date` anchors the recognition to a specific day (usually today).
  Returns `{:error, :unauthorized}` if the caller is not an admin.
  """
  @spec give_recognition(User.t(), map()) ::
          {:ok, EmployeeRecognition.t()} | {:error, :unauthorized} | {:error, Ecto.Changeset.t()}
  def give_recognition(%User{role: "admin"} = admin, attrs) do
    %EmployeeRecognition{}
    |> EmployeeRecognition.changeset(Map.put(attrs, :given_by_id, admin.id))
    |> Repo.insert()
  end

  def give_recognition(%User{}, _attrs), do: {:error, :unauthorized}

  @doc "Returns all recognitions for a given period_date, preloading user and given_by."
  @spec list_recognitions_for_period(Date.t()) :: [EmployeeRecognition.t()]
  def list_recognitions_for_period(date) do
    EmployeeRecognition
    |> where(period_date: ^date)
    |> order_by(desc: :inserted_at)
    |> preload([:user, :given_by])
    |> Repo.all()
  end

  @doc "Returns recent recognitions for a specific user (last 30 days), newest first."
  @spec list_recognitions_for_user(integer()) :: [EmployeeRecognition.t()]
  def list_recognitions_for_user(user_id) do
    since = Date.add(Date.utc_today(), -30)

    EmployeeRecognition
    |> where(user_id: ^user_id)
    |> where([r], r.period_date >= ^since)
    |> order_by(desc: :inserted_at)
    |> preload(:given_by)
    |> Repo.all()
  end

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

  # Builds a signed, 7-day confirmation URL for the given user.
  defp build_confirmation_url(user) do
    token = Phoenix.Token.sign(CRCWeb.Endpoint, "email_confirm", user.id)
    "#{CRCWeb.Endpoint.url()}/confirmar-email?token=#{token}"
  end

  # Sends the welcome/confirmation email. Runs inside a Task so it never
  # blocks the caller. Delivery errors are logged but do not surface to the UI.
  defp deliver_welcome_email(user) do
    url = build_confirmation_url(user)

    user
    |> UserEmail.welcome_confirmation(url)
    |> Mailer.deliver()
    |> case do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        require Logger
        Logger.error("Failed to deliver welcome email to #{user.email}: #{inspect(reason)}")
    end
  end

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
