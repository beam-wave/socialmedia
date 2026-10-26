defmodule Socialmedia.Content.Matches do
  @moduledoc """
  @mid.innings: every fixture post gets a linked result post.

  Claude writes the fixture (match card + 3 prediction questions) for the day
  the admin picked. Once it's made, the result post is created and timed from
  the match start and format. It waits for the admin to enter the scores and
  the player of the match; the app then builds it without Claude (see
  `Socialmedia.Content.MatchResult`) and renders it. The fixture goes out
  before the first ball.
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

  @doc "Creates (or re-times) the result post for a fixture that has just been made."
  def after_fixture(%Post{} = fixture) do
    case start_time(fixture.data) do
      {:ok, start, match} ->
        ensure_result(fixture, start, Map.get(@durations, match["match_type"], 240))

      :error ->
        :no_start_time
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

  def first_match(%{"posts" => [m | _]}), do: m
  def first_match(_), do: nil

  @doc "Result posts are built from the scores the admin enters."
  def needs_facts?(%Post{post_type: "result", parent_id: id}) when not is_nil(id), do: true
  def needs_facts?(_), do: false

  # The result waits for the admin's scores.
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
