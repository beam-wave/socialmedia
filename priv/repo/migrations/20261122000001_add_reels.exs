defmodule Socialmedia.Repo.Migrations.AddReels do
  use Ecto.Migration

  def change do
    alter table(:channels) do
      # What one Create makes: the photo/carousel post, the animated reel, or both
      add :make_post, :boolean, null: false, default: true
      add :make_reel, :boolean, null: false, default: false
    end

    alter table(:posts) do
      # Snapshot of the channel's choice when the post was created
      add :formats, {:array, :string}, null: false, default: ["post"]
      add :video_path, :string
      add :cover_path, :string
      add :reel_media_id, :string
      add :reel_permalink, :string
      add :reel_audio, :map
    end
  end
end
