defmodule UsersWeb.SessionController do
  use UsersWeb, :controller

  alias Users.Accounts

  action_fallback UsersWeb.FallbackController

  @doc "Logs in through the auth service and relays its answer unchanged."
  def create(conn, %{"name" => name, "password" => password})
      when is_binary(name) and is_binary(password) do
    with {:ok, response} <- Accounts.login(name, password) do
      content_type =
        case Req.Response.get_header(response, "content-type") do
          [value | _] -> value
          [] -> "text/plain"
        end

      conn
      |> put_resp_header("content-type", content_type)
      |> send_resp(response.status, response.body)
    end
  end

  def create(_conn, _params), do: {:error, :bad_request}
end
