defmodule Socialmedia.Repo.Migrations.AddPostMatchFields do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      # Fixtures: when the match should be over; the result check starts then
      add :ends_at, :utc_datetime
      # Fixtures: the match's id in the results API (CricketData.org), once found
      add :source_match_id, :string
    end
  end
end
