defmodule Socialmedia.Content.Matches do
  @moduledoc """
  @mid.innings timing. Claude writes a fixture (match card + 3 prediction
  questions) for the day the admin picked; it goes out before the first ball,
  and `expected_end/1` says when the match should be over. Once the fixture is
  scheduled on prod, Workers.ResultWatcher posts the result by itself; a result
  can also be entered by hand (Content.MatchResult builds it without Claude).
  """
  alias Socialmedia.Posts.Post

  # Typical length of a match, used to time the result post
  @durations %{
    "T10" => 100,
    "The Hundred" => 170,
    "T20" => 225,
    "ODI" => 510,
    "Test" => 4 * 24 * 60 + 480
  }
  # Post the fixture at least this long before the first ball
  @fixture_lead_minutes 90

  @doc "When the match should be over: its start plus the format's usual length. Nil without a start time."
  def expected_end(data) do
    case start_time(data) do
      {:ok, start, match} ->
        start
        |> DateTime.add(Map.get(@durations, match["match_type"], 240) * 60)
        |> DateTime.truncate(:second)

      :error ->
        nil
    end
  end

  @doc "When a fixture should go out: its chosen time, or earlier if the match starts first."
  def fixture_time(data, %DateTime{} = chosen) do
    with {:ok, start, _} <- start_time(data),
         latest = DateTime.add(start, -@fixture_lead_minutes * 60),
         true <- DateTime.compare(chosen, latest) == :gt,
         true <- DateTime.compare(latest, DateTime.utc_now()) == :gt do
      DateTime.truncate(latest, :second)
    else
      _ -> chosen
    end
  end

  defp start_time(data) do
    with %{"start_utc" => start_s} = match <- first_match(data),
         {:ok, start, _} <- DateTime.from_iso8601(start_s) do
      {:ok, start, match}
    else
      _ -> :error
    end
  end

  @doc """
  One data map per match. The agent returns all of a day's fixtures in one
  run; each becomes its own post with only its two teams.
  """
  def split_fixtures(%{"posts" => [_, _ | _] = posts} = data) do
    teams = data["teams"] || %{}

    for p <- posts,
        do:
          %{data | "posts" => [p]} |> Map.put("teams", Map.take(teams, [p["team1"], p["team2"]]))
  end

  def split_fixtures(data), do: [data]

  def first_match(%{"posts" => [m | _]}), do: m
  def first_match(_), do: nil

  @doc "Result posts are built from the scores the admin enters."
  def needs_facts?(%Post{post_type: "result", parent_id: id}) when not is_nil(id), do: true
  def needs_facts?(_), do: false
end
