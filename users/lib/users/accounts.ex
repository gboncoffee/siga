defmodule Users.Accounts do
  @moduledoc """
  User accounts. Names are stored here; credentials live in the auth service.
  """
  alias Users.Accounts.User
  alias Users.Auth
  alias Users.Repo

  @doc """
  Creates a user and its credentials in the auth service.

  The name is inserted inside a transaction that is rolled back if the auth
  service does not accept the credentials, so both sides stay in sync.
  """
  @spec create_user(map()) ::
          {:ok, User.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, :auth_rejected | :auth_unavailable}
  def create_user(attrs) do
    changeset = User.registration_changeset(%User{}, attrs)

    Repo.transact(fn ->
      with {:ok, user} <- Repo.insert(changeset),
           :ok <- Auth.create_credentials(user.name, user.password) do
        {:ok, %{user | password: nil}}
      end
    end)
  end

  @doc "Logs a user in. Relays the auth service response as is."
  defdelegate login(name, password), to: Auth
end
