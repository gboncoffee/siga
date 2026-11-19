defmodule Users.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    # Only the list of names lives here; passwords are kept by the auth service.
    create table(:users, primary_key: false) do
      add :name, :string, primary_key: true
    end
  end
end
