defmodule Socialmedia.Repo.Migrations.AddPostContentKey do
  use Ecto.Migration

  # Content is made on a button click now, not planned ahead, so the planning
  # columns go. content_key names a post on every machine and its folder in S3.
  def up do
    # Planner leftovers nobody has written yet; only result posts still wait in `planned`
    execute "DELETE FROM posts WHERE status = 'planned' AND post_type <> 'result' AND data IS NULL"
    execute "UPDATE posts SET status = 'needs_review' WHERE status = 'render_requested'"

    alter table(:posts) do
      add :content_key, :string
      remove :slot_at
      remove :generate_at
      remove :gen_rev
      remove :retries
    end

    execute "UPDATE posts SET content_key = gen_random_uuid()::text"
    execute "ALTER TABLE posts ALTER COLUMN content_key SET NOT NULL"
    create unique_index(:posts, [:content_key])

    alter table(:schedules) do
      remove :lead_hours
    end
  end

  def down do
    alter table(:schedules) do
      add :lead_hours, :integer, null: false, default: 48
    end

    alter table(:posts) do
      remove :content_key
      add :slot_at, :utc_datetime
      add :generate_at, :utc_datetime
      add :gen_rev, :integer, null: false, default: 1
      add :retries, :integer, null: false, default: 0
    end

    create unique_index(:posts, [:schedule_id, :slot_at])
  end
end
