defmodule UsersWeb.Router do
  use UsersWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", UsersWeb do
    pipe_through :api

    post "/users", UserController, :create
    post "/login", SessionController, :create
  end
end
