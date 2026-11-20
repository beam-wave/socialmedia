defmodule Socialmedia.Workers.ResultWatcher do
  @moduledoc """
  Posts a scheduled @mid.innings fixture's result by itself, on prod.

  Queued when the fixture is scheduled, to run at its `ends_at` (when the match
  should be over). Every 30 minutes it asks CricketData.org whether the match has
  finished; once it has, it builds the result (Content.MatchResult), renders it
  and publishes it straight away, with no review. Gives up 12 hours after
  `ends_at`. Abandoned, no-result and incomplete matches aren't posted: the
  result post is marked failed with the reason, for the admin to finish by hand.
  The channel's Dry run switch still applies when publishing.
  """
  use Oban.Worker,
    queue: :results,
    max_attempts: 5,
    unique: [keys: [:post_id], period: :infinity, states: :incomplete]

  require Logger
  alias Socialmedia.{Content, Posts, Repo}
  alias Socialmedia.Content.MatchResult
  alias Socialmedia.Cricket.{Cricapi, Results}
  alias Socialmedia.Posts.Post

  @every_seconds 30 * 60
  @give_up_after 12 * 3600

  @doc "Queues the check for a fixture at its expected end (now, if that has passed)."
  def enqueue(%Post{post_type: "fixture", id: id} = fixture) do
    at = fixture.ends_at || Content.Matches.expected_end(fixture.data)

    opts =
      if at && DateTime.compare(at, DateTime.utc_now()) == :gt, do: [scheduled_at: at], else: []

    %{post_id: id} |> new(opts) |> Oban.insert()
  end

  def enqueue(_post), do: {:ok, :not_a_fixture}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"post_id" => id}}) do
    case Posts.get_post(id) do
      %Post{post_type: "fixture", status: s} = fixture
      when s in ~w(approved publishing published) ->
        check(Repo.preload(fixture, [:channel, :child]))

      nil ->
        {:cancel, :fixture_deleted}

      fixture ->
        {:cancel, "fixture is #{fixture.status}"}
    end
  end

  defp check(%Post{child: %Post{status: s}}) when s in ~w(approved publishing published),
    do: {:cancel, :result_already_posted}

  defp check(fixture) do
    cond do
      not Cricapi.configured?() ->
        give_up(fixture, "No CRICKETDATA_API_KEY on this server: enter the result by hand")

      too_late?(fixture) ->
        give_up(fixture, "No finished result 12 hours after the expected end: enter it by hand")

      true ->
        with {:ok, match_id} <- match_id(fixture),
             {:ok, card} <- Cricapi.scorecard(match_id) do
          if card["matchEnded"],
            do: post_result(fixture, card),
            else: wait("not finished: #{card["status"]}", fixture)
        else
          {:error, :not_listed} -> wait("not listed yet", fixture)
          {:error, reason} -> wait(reason, fixture)
        end
    end
  end

  defp match_id(%Post{source_match_id: id}) when is_binary(id) and id != "", do: {:ok, id}

  defp match_id(fixture) do
    with {:ok, matches} <- Cricapi.current_matches() do
      case Results.find(matches, fixture.data) do
        %{"id" => id} ->
          {:ok, _} = fixture |> Post.changeset(%{source_match_id: id}) |> Repo.update()
          {:ok, id}

        nil ->
          {:error, :not_listed}
      end
    end
  end

  defp post_result(fixture, card) do
    with {:ok, facts} <- Results.facts(card, fixture.data),
         {:ok, result} <- result_post(fixture),
         {:ok, data} <-
           MatchResult.build(%{result | parent: fixture, channel: fixture.channel}, facts),
         {:ok, _} <- Content.publish_result(result, data, facts) do
      Logger.info("result for fixture #{fixture.id} posted: #{facts["result"]}")
      :ok
    else
      {:error, reason} -> give_up(fixture, to_string(reason))
    end
  end

  # The result post: the one linked to the fixture, or a new one
  defp result_post(%Post{child: %Post{} = r}), do: {:ok, Repo.preload(r, :channel)}

  defp result_post(fixture) do
    with {:ok, r} <-
           Posts.create_post(%{
             channel_id: fixture.channel_id,
             parent_id: fixture.id,
             post_type: "result",
             status: "creating",
             scheduled_at: DateTime.utc_now() |> DateTime.truncate(:second)
           }) do
      {:ok, Repo.preload(r, :channel)}
    end
  end

  defp give_up(fixture, reason) do
    Logger.warning("result for fixture #{fixture.id}: #{reason}")

    with {:ok, r} <- result_post(fixture),
         true <- r.status not in ~w(approved publishing published) do
      Posts.mark(r, "failed", %{error: reason})
    end

    {:cancel, reason}
  end

  defp wait(why, fixture) do
    Logger.info("result for fixture #{fixture.id}: #{why}; checking again in 30 min")
    {:snooze, @every_seconds}
  end

  defp too_late?(%Post{ends_at: nil}), do: false

  defp too_late?(%Post{ends_at: at}),
    do: DateTime.diff(DateTime.utc_now(), at) > @give_up_after
end
