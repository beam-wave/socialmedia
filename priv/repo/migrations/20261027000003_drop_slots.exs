defmodule Socialmedia.Repo.Migrations.DropSlots do
  use Ecto.Migration

  # Posts are made on a click and given their time when scheduled, so slots
  # (default times and per-type agent instructions) are gone.
  def up do
    alter table(:posts) do
      remove :schedule_id
    end

    drop table(:schedules)
  end

  def down do
    create table(:schedules) do
      add :channel_id, references(:channels, on_delete: :delete_all), null: false
      add :post_type, :string, null: false
      add :weekdays, {:array, :integer}, null: false, default: []
      add :time_of_day, :time, null: false
      add :extra_instructions, :text
      add :active, :boolean, null: false, default: true
      timestamps(type: :utc_datetime)
    end

    alter table(:posts) do
      add :schedule_id, references(:schedules, on_delete: :nilify_all)
    end
  end
end
