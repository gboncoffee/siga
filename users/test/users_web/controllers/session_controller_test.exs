defmodule UsersWeb.SessionControllerTest do
  use UsersWeb.ConnCase, async: true
  @moduletag :capture_log

  test "POST /login relays a successful login", %{conn: conn} do
    Req.Test.stub(Users.Auth, fn auth_conn ->
      {:ok, body, auth_conn} = Plug.Conn.read_body(auth_conn)
      assert auth_conn.request_path == "/login"
      assert Jason.decode!(body) == %{"Username" => "ana", "Password" => "segredo"}
      Req.Test.json(auth_conn, %{"Token" => "8b47881d-650f-4ab1-a38a-bbf3e19ac0d2"})
    end)

    conn = post(conn, ~p"/login", %{name: "ana", password: "segredo"})
    assert json_response(conn, 200) == %{"Token" => "8b47881d-650f-4ab1-a38a-bbf3e19ac0d2"}
  end

  test "POST /login relays a failed login unchanged", %{conn: conn} do
    Req.Test.stub(Users.Auth, fn auth_conn ->
      auth_conn
      |> Plug.Conn.put_resp_content_type("text/plain")
      |> Plug.Conn.send_resp(401, "invalid username or password\n")
    end)

    conn = post(conn, ~p"/login", %{name: "ana", password: "errada"})
    assert response(conn, 401) == "invalid username or password\n"
    assert response_content_type(conn, :text)
  end

  test "POST /login without credentials answers 400", %{conn: conn} do
    conn = post(conn, ~p"/login", %{name: "ana"})

    assert json_response(conn, 400) == %{
             "errors" => %{"detail" => "name and password are required"}
           }
  end

  test "POST /login answers 503 when auth is down", %{conn: conn} do
    Req.Test.stub(Users.Auth, &Req.Test.transport_error(&1, :econnrefused))
    conn = post(conn, ~p"/login", %{name: "ana", password: "a"})
    assert json_response(conn, 503)
  end
end
