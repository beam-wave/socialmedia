defmodule Socialmedia.Repo.Migrations.AddPostSeriesNumber do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      # Day N (@_motivation2live__) / quote N (@puree_heartz), taken when the post is created
      add :series_number, :integer
    end
  end
end
