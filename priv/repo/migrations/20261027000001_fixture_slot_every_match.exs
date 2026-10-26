defmodule Socialmedia.Repo.Migrations.FixtureSlotEveryMatch do
  use Ecto.Migration

  # A match-day run now returns every relevant match, so the seeded slot text
  # shouldn't tell the agent to pick one. Edited slots are left alone.
  @old "Pick by the skill's priority: India, ICC events, T20 leagues, The Hundred, T10 leagues. Skip if no match starts today."
  @new "Every relevant match that day, by the skill's priority: India, ICC events, T20 leagues, The Hundred, T10 leagues. Skip if no match starts that day."

  def up, do: swap(@old, @new)
  def down, do: swap(@new, @old)

  defp swap(from, to) do
    execute fn ->
      repo().query!(
        "UPDATE schedules SET extra_instructions = $1 WHERE extra_instructions = $2",
        [to, from]
      )
    end
  end
end
