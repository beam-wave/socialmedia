defmodule Socialmedia.Repo.Migrations.MidInningsSplitBold do
  use Ecto.Migration

  # @mid.innings cards use the team-colour "split bold" design by default
  def up do
    execute """
    UPDATE channels SET base_data = jsonb_set(coalesce(base_data, '{}'::jsonb), '{theme}', '"splitbold"')
    WHERE handle = '@mid.innings' AND coalesce(base_data->>'theme', 'floodlight') = 'floodlight'
    """
  end

  def down do
    execute """
    UPDATE channels SET base_data = jsonb_set(base_data, '{theme}', '"floodlight"')
    WHERE handle = '@mid.innings' AND base_data->>'theme' = 'splitbold'
    """
  end
end
