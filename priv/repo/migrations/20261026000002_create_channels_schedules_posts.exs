defmodule Socialmedia.Repo.Migrations.CreateChannelsSchedulesPosts do
  use Ecto.Migration

  def change do
    create table(:channels) do
      add :name, :string, null: false
      add :handle, :string, null: false
      add :skill, :string, null: false
      add :template_dir, :string, null: false
      add :timezone, :string, null: false, default: "Asia/Kolkata"
      add :hashtags, :text
      add :ig_user_id, :string
      add :access_token, :binary
      add :token_expires_at, :utc_datetime
      add :dry_run, :boolean, null: false, default: true
      add :active, :boolean, null: false, default: true
      add :base_data, :map, null: false, default: %{}
      timestamps(type: :utc_datetime)
    end

    create unique_index(:channels, [:handle])

    create table(:schedules) do
      add :channel_id, references(:channels, on_delete: :delete_all), null: false
      add :post_type, :string, null: false
      add :weekdays, {:array, :integer}, null: false, default: []
      add :time_of_day, :time, null: false
      add :lead_hours, :integer, null: false, default: 48
      add :extra_instructions, :text
      add :active, :boolean, null: false, default: true
      timestamps(type: :utc_datetime)
    end

    create index(:schedules, [:channel_id])

    create table(:posts) do
      add :channel_id, references(:channels, on_delete: :delete_all), null: false
      add :schedule_id, references(:schedules, on_delete: :nilify_all)
      add :scheduled_at, :utc_datetime, null: false
      add :post_type, :string, null: false
      add :status, :string, null: false, default: "planned"
      # When content should be created (scheduled_at - lead_hours, or now on regenerate)
      add :generate_at, :utc_datetime
      # Set when a content worker claims the post; stale claims are released
      add :claimed_at, :utc_datetime
      add :data, :map
      add :caption, :text
      add :slide_paths, {:array, :string}, null: false, default: []
      add :sources, {:array, :map}, null: false, default: []
      add :admin_note, :text
      add :agent_log, :text
      add :error, :text
      add :reject_reason, :string
      add :approved_at, :utc_datetime
      add :published_at, :utc_datetime
      add :ig_media_id, :string
      add :permalink, :string
      timestamps(type: :utc_datetime)
    end

    create unique_index(:posts, [:schedule_id, :scheduled_at])
    create index(:posts, [:channel_id, :scheduled_at])
    create index(:posts, [:status, :scheduled_at])
    create index(:posts, [:status, :generate_at])
  end
end
