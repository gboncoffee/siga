defmodule UsersWeb.UserJSON do
  alias Users.Accounts.User

  def show(%{user: user}), do: data(user)

  defp data(%User{} = user), do: %{name: user.name}
end
