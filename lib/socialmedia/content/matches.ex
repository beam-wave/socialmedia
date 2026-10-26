defmodule Socialmedia.Content.Matches do
  @moduledoc """
  @mid.innings: every fixture post gets a linked result post.

  Claude writes the fixture (match card + 3 prediction questions). When it
  arrives, the result post is created and timed from the match start and
  format. It waits for the admin to type the match facts (summary, innings
  scores, best bat/bowl per innings, POM); then Claude writes the result post
  from those facts (no web search) and scores the fixture's predictions.
  The fixture is moved earlier if the match starts before its slot.
  """
  import Ecto.Query
  alias Socialmedia.{Repo, Posts}
  alias Socialmedia.Posts.Post

  # Typical length of a match, used to time the result post
  @durations %{
    "T10" => 100,
    "The Hundred" => 170,
    "T20" => 225,
    "ODI" => 510,
    "Test" => 4 * 24 * 60 + 480
  }
  # Result goes out this long after the expected finish (time to enter facts and review)
  @result_after_minutes 60
  # Post the fixture at least this long before the first ball
  @fixture_lead_minutes 90

  def after_fixture(%Post{} = fixture) do
    with %{"start_utc" => start_s} = match <- first_match(fixture.data),
         {:ok, start, _} <- DateTime.from_iso8601(start_s) do
      move_fixture_before_start(fixture, start)
      ensure_result(fixture, start, Map.get(@durations, match["match_type"], 240))
    else
      _ -> :no_start_time
    end
  end

  def first_match(%{"posts" => [m | _]}), do: m
  def first_match(_), do: nil

  @doc "Result posts are written from facts the admin types in."
  def needs_facts?(%Post{post_type: "result", parent_id: id}) when not is_nil(id), do: true
  def needs_facts?(_), do: false

  @doc "Blank facts form shaped by the fixture (teams in order, two innings)."
  def blank_facts(%Post{parent: %Post{data: fx_data}}) do
    fx = first_match(fx_data) || %{}

    %{
      "summary" => "",
      "pom" => "",
      "innings" => [
        %{"team" => fx["team1"], "score" => "", "best_bat" => "", "best_bowl" => ""},
        %{"team" => fx["team2"], "score" => "", "best_bat" => "", "best_bowl" => ""}
      ]
    }
  end

  def blank_facts(_), do: %{"summary" => "", "pom" => "", "innings" => []}

  defp move_fixture_before_start(fixture, start) do
    latest = DateTime.add(start, -@fixture_lead_minutes * 60)

    if DateTime.compare(fixture.scheduled_at, latest) == :gt and
         DateTime.compare(latest, DateTime.utc_now()) == :gt do
      Posts.reschedule(fixture, latest)
    end
  end

  # No generate_at: the result waits for the admin's facts, not a time.
  defp ensure_result(fixture, start, duration_min) do
    scheduled_at =
      start
      |> DateTime.add((duration_min + @result_after_minutes) * 60)
      |> DateTime.truncate(:second)

    case Repo.one(from p in Post, where: p.parent_id == ^fixture.id) do
      nil ->
        Posts.create_linked(%{
          channel_id: fixture.channel_id,
          parent_id: fixture.id,
          post_type: "result",
          status: "planned",
          scheduled_at: scheduled_at
        })

      # Fixture was regenerated (maybe a different match): re-time the untouched result
      %Post{status: "planned", facts: nil} = result ->
        Posts.mark(result, "planned", %{scheduled_at: scheduled_at})

      result ->
        {:ok, result}
    end
  end
end
