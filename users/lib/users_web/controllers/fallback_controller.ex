defmodule UsersWeb.FallbackController do
  @moduledoc "Turns the error tuples returned by controller actions into responses."
  use UsersWeb, :controller

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    status = if name_taken?(changeset), do: :conflict, else: :unprocessable_entity

    conn
    |> put_status(status)
    |> put_view(json: UsersWeb.ChangesetJSON)
    |> render(:error, changeset: changeset)
  end

  def call(conn, {:error, :bad_request}),
    do: detail(conn, :bad_request, "name and password are required")

  def call(conn, {:error, :auth_rejected}),
    do: detail(conn, :bad_gateway, "auth service rejected the credentials")

  def call(conn, {:error, :auth_unavailable}),
    do: detail(conn, :service_unavailable, "auth service unavailable")

  defp detail(conn, status, message) do
    conn
    |> put_status(status)
    |> put_view(json: UsersWeb.ErrorJSON)
    |> render(:detail, detail: message)
  end

  defp name_taken?(changeset) do
    Enum.any?(changeset.errors, fn {field, {_msg, opts}} ->
      field == :name and opts[:constraint] == :unique
    end)
  end
end
