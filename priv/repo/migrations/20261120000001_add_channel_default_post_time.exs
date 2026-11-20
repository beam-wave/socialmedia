defmodule Socialmedia.Repo.Migrations.AddChannelDefaultPostTime do
  use Ecto.Migration

  def up do
    alter table(:channels) do
      # Local time new posts start at (the Schedule form's default)
      add :default_post_time, :time
    end

    flush()

    for {handle, time} <- [
          {"@_motivation2live__", "08:00:00"},
          {"@spotlight.startups", "21:00:00"},
          {"@puree_heartz", "18:00:00"}
        ] do
      execute "UPDATE channels SET default_post_time = '#{time}' WHERE handle = '#{handle}' AND default_post_time IS NULL"
    end
  end

  def down do
    alter table(:channels) do
      remove :default_post_time
    end
  end
end
