defmodule Socialmedia.Repo.Migrations.S3BusAndReschedule do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      # The slot this post was planned for (stable, used for uniqueness).
      # scheduled_at is when it actually goes out and the admin can move it.
      add :slot_at, :utc_datetime
      # Bumped on every regenerate / re-render request; names the request on the S3 bus
      add :gen_rev, :integer, null: false, default: 1
      remove :claimed_at, :utc_datetime
    end

    execute "UPDATE posts SET slot_at = scheduled_at", ""

    drop unique_index(:posts, [:schedule_id, :scheduled_at])
    create unique_index(:posts, [:schedule_id, :slot_at])
  end
end
