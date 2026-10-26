defmodule Socialmedia.Repo.Migrations.LinkResultToFixture do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      # A result post points at the fixture post it scores
      add :parent_id, references(:posts, on_delete: :nilify_all)
      # Times the agent asked to try again later (e.g. match not finished)
      add :retries, :integer, null: false, default: 0
    end

    create unique_index(:posts, [:parent_id], where: "parent_id IS NOT NULL")
  end
end
