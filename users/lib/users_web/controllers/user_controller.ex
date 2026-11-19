defmodule UsersWeb.UserController do
  use UsersWeb, :controller

  alias Users.Accounts

  action_fallback UsersWeb.FallbackController

  def create(conn, params) do
    attrs = Map.take(params, ["name", "password"])

    with {:ok, user} <- Accounts.create_user(attrs) do
      conn
      |> put_status(:created)
      |> render(:show, user: user)
    end
  end
end
