defmodule Users.AccountsTest do
  use Users.DataCase, async: true
  @moduletag :capture_log

  alias Users.Accounts
  alias Users.Accounts.User
  alias Users.Repo

  defp stub_auth(status) do
    Req.Test.stub(Users.Auth, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(self(), {:auth_request, conn.method, conn.request_path, Jason.decode!(body)})
      Plug.Conn.send_resp(conn, status, "")
    end)
  end

  describe "create_user/1" do
    test "stores only the name and sends the credentials to auth" do
      stub_auth(200)

      assert {:ok, %User{name: "ana", password: nil}} =
               Accounts.create_user(%{"name" => "ana", "password" => "segredo"})

      assert_received {:auth_request, "POST", "/credentials",
                       %{"Username" => "ana", "Password" => "segredo"}}

      assert [%User{name: "ana"}] = Repo.all(User)
    end

    test "requires name and password, without calling auth" do
      assert {:error, changeset} = Accounts.create_user(%{"name" => "", "password" => nil})
      assert %{name: ["can't be blank"], password: ["can't be blank"]} = errors_on(changeset)
      refute_received {:auth_request, _, _, _}
    end

    test "rejects a name that is already taken, without calling auth" do
      stub_auth(200)
      {:ok, _} = Accounts.create_user(%{"name" => "ana", "password" => "a"})
      assert_received {:auth_request, _, _, _}

      assert {:error, changeset} = Accounts.create_user(%{"name" => "ana", "password" => "b"})
      assert %{name: ["has already been taken"]} = errors_on(changeset)
      refute_received {:auth_request, _, _, _}
    end

    test "rolls back the name when auth rejects the credentials" do
      stub_auth(500)

      assert {:error, :auth_rejected} =
               Accounts.create_user(%{"name" => "ana", "password" => "a"})

      assert Repo.all(User) == []
    end

    test "rolls back the name when auth is unreachable" do
      Req.Test.stub(Users.Auth, &Req.Test.transport_error(&1, :econnrefused))

      assert {:error, :auth_unavailable} =
               Accounts.create_user(%{"name" => "ana", "password" => "a"})

      assert Repo.all(User) == []
    end
  end
end
