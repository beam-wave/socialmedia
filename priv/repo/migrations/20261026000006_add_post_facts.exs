defmodule Socialmedia.Repo.Migrations.AddPostFacts do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      # Facts typed in by the admin (e.g. match result); the agent writes from these instead of searching
      add :facts, :map
    end
  end
end
