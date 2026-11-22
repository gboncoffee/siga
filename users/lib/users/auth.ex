defmodule Users.Auth do
  @moduledoc """
  HTTP client for the SIGA auth service (`auth/`, written in Go).

  The base URL comes from the `:auth_url` application environment
  (`SIGA_AUTH_URL` at runtime). Extra `Req` options, such as a test plug,
  can be set in `:auth_req_options`.
  """
  require Logger

  @doc "Registers the credentials of a user in the auth service."
  @spec create_credentials(String.t(), String.t()) ::
          :ok | {:error, :auth_rejected | :auth_unavailable}
  def create_credentials(name, password) do
    case post("/credentials", name, password) do
      {:ok, %Req.Response{status: 200}} ->
        :ok

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("auth: POST /credentials answered #{status}: #{inspect(body)}")
        {:error, :auth_rejected}

      {:error, exception} ->
        Logger.error("auth: POST /credentials failed: #{Exception.message(exception)}")
        {:error, :auth_unavailable}
    end
  end

  @doc """
  Logs in through the auth service. Returns its response untouched, whatever
  the status, so it can be relayed to the client.
  """
  @spec login(String.t(), String.t()) :: {:ok, Req.Response.t()} | {:error, :auth_unavailable}
  def login(name, password) do
    case post("/login", name, password) do
      {:ok, response} ->
        {:ok, response}

      {:error, exception} ->
        Logger.error("auth: POST /login failed: #{Exception.message(exception)}")
        {:error, :auth_unavailable}
    end
  end

  defp post(path, name, password) do
    [
      method: :post,
      base_url: Application.fetch_env!(:users, :auth_url),
      url: path,
      json: %{"Username" => name, "Password" => password},
      decode_body: false,
      retry: false,
      receive_timeout: 5_000
    ]
    |> Req.new()
    |> Req.merge(Application.get_env(:users, :auth_req_options, []))
    |> Req.request()
  end
end
