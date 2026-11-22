defmodule Users.Accounts.User do
  @moduledoc """
  A SIGA user. Only the name is stored; the password is a virtual field that
  is validated here and handed to the auth service, never persisted.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @max_name_length 64

  @primary_key {:name, :string, autogenerate: false}
  schema "users" do
    field :password, :string, virtual: true, redact: true
  end

  @doc "Changeset for creating a user with a name and a password."
  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :password])
    |> validate_required([:name, :password])
    |> validate_length(:name, max: @max_name_length)
    |> unique_constraint(:name, message: "has already been taken")
  end
end
