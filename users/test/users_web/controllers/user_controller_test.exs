defmodule UsersWeb.UserControllerTest do
  use UsersWeb.ConnCase, async: true
  @moduletag :capture_log

  setup do
    Req.Test.stub(Users.Auth, &Plug.Conn.send_resp(&1, 200, ""))
    :ok
  end

  test "POST /users creates a user", %{conn: conn} do
    conn = post(conn, ~p"/users", %{name: "ana", password: "segredo"})
    assert json_response(conn, 201) == %{"name" => "ana"}
  end

  test "POST /users with a taken name answers 409", %{conn: conn} do
    post(conn, ~p"/users", %{name: "ana", password: "a"})
    conn = post(conn, ~p"/users", %{name: "ana", password: "b"})
    assert json_response(conn, 409) == %{"errors" => %{"name" => ["has already been taken"]}}
  end

  test "POST /users with missing fields answers 422", %{conn: conn} do
    conn = post(conn, ~p"/users", %{name: "ana"})
    assert json_response(conn, 422) == %{"errors" => %{"password" => ["can't be blank"]}}
  end

  test "POST /users answers 503 when auth is down", %{conn: conn} do
    Req.Test.stub(Users.Auth, &Req.Test.transport_error(&1, :econnrefused))
    conn = post(conn, ~p"/users", %{name: "ana", password: "a"})
    assert json_response(conn, 503) == %{"errors" => %{"detail" => "auth service unavailable"}}
  end

  test "POST /users answers 502 when auth rejects the credentials", %{conn: conn} do
    Req.Test.stub(Users.Auth, &Plug.Conn.send_resp(&1, 500, "internal server error"))
    conn = post(conn, ~p"/users", %{name: "ana", password: "a"})
    assert json_response(conn, 502)
  end
end
