defmodule Socialmedia.ResultWatcherTest do
  use Socialmedia.DataCase, async: false
  use Oban.Testing, repo: Socialmedia.Repo
  import Socialmedia.Fixtures
  alias Socialmedia.{Posts, Repo}
  alias Socialmedia.Posts.Post
  alias Socialmedia.Cricket.Results
  alias Socialmedia.Workers.{ResultWatcher, Publish}

  setup do
    File.rm_rf!(Socialmedia.Storage.Local.root())

    ch =
      channel(%{
        handle: "@mid#{System.unique_integer([:positive])}",
        skill: "mid-innings",
        template_dir: "mid.innings",
        base_data: %{}
      })

    start = DateTime.utc_now() |> DateTime.add(-5 * 3600) |> DateTime.truncate(:second)

    data = %{
      "teams" => %{
        "IND" => %{"code" => "IND", "name" => "India", "color" => "#1f5fd1"},
        "AUS" => %{"code" => "AUS", "name" => "Australia", "color" => "#d9a400"}
      },
      "posts" => [
        %{
          "type" => "fixture",
          "team1" => "IND",
          "team2" => "AUS",
          "series" => "S",
          "match" => "2nd T20I",
          "venue" => "V",
          "start_utc" => DateTime.to_iso8601(start),
          "match_type" => "T20",
          "questions" => [
            %{"q" => "Who wins the match?", "options" => ["India", "Australia"]},
            %{"q" => "First-innings score?", "options" => ["Under 160", "160–190", "190+"]},
            %{
              "q" => "Player of the match?",
              "options" => ["Virat Kohli", "Pat Cummins", "Travis Head"]
            }
          ]
        }
      ]
    }

    fx =
      insert_post(ch, %{
        post_type: "fixture",
        status: "approved",
        data: data,
        scheduled_at: DateTime.add(start, -3600),
        ends_at: DateTime.add(start, 225 * 60)
      })

    %{ch: ch, fx: fx, start: start}
  end

  defp listing(start, ended?) do
    [
      %{
        "id" => "m1",
        "teams" => ["Australia", "India"],
        "dateTimeGMT" => start |> DateTime.to_iso8601() |> String.trim_trailing("Z"),
        "teamInfo" => [
          %{"name" => "Australia", "shortname" => "AUS"},
          %{"name" => "India", "shortname" => "IND"}
        ],
        "matchEnded" => ended?
      },
      %{
        "id" => "other",
        "teams" => ["Pakistan", "England"],
        "teamInfo" => [],
        "dateTimeGMT" => "2026-01-01T00:00:00"
      }
    ]
  end

  defp card(ended?, status \\ "India won by 6 wkts") do
    %{
      "id" => "m1",
      "matchEnded" => ended?,
      "status" => status,
      "score" => [
        %{"r" => 184, "w" => 7, "o" => 20, "inning" => "australia Inning 1"},
        %{"r" => 188, "w" => 4, "o" => 18.3, "inning" => "india Inning 1"}
      ],
      "scorecard" => [
        %{
          "inning" => "australia Inning 1",
          "batting" => [
            %{"batsman" => %{"name" => "Travis Head"}, "r" => 61, "b" => 39},
            %{"batsman" => %{"name" => "Mitch Marsh"}, "r" => 20, "b" => 15}
          ],
          "bowling" => [
            %{"bowler" => %{"name" => "Jasprit Bumrah"}, "o" => 4, "r" => 24, "w" => 3}
          ]
        },
        %{
          "inning" => "india Inning 1",
          "batting" => [%{"batsman" => %{"name" => "Virat Kohli"}, "r" => 78, "b" => 44}],
          "bowling" => [%{"bowler" => %{"name" => "Pat Cummins"}, "o" => 4, "r" => 31, "w" => 2}]
        }
      ]
    }
  end

  defp stub(start, card) do
    Req.Test.stub(Socialmedia.Cricket.Cricapi, fn conn ->
      case conn.request_path do
        "/v1/currentMatches" ->
          Req.Test.json(conn, %{
            "status" => "success",
            "data" => listing(start, card["matchEnded"])
          })

        "/v1/match_scorecard" ->
          Req.Test.json(conn, %{"status" => "success", "data" => card})
      end
    end)
  end

  test "scheduling a fixture queues its result check at the match end", %{ch: ch} do
    ends = DateTime.utc_now() |> DateTime.add(4 * 3600) |> DateTime.truncate(:second)
    fx = insert_post(ch, %{post_type: "fixture", status: "needs_review", ends_at: ends})
    {:ok, _} = Posts.approve(fx)
    assert_enqueued(worker: ResultWatcher, args: %{post_id: fx.id}, scheduled_at: ends)
  end

  test "not finished yet: checks again in 30 minutes", %{fx: fx, start: start} do
    stub(start, card(false, "India need 20 runs"))
    assert {:snooze, 1800} = perform_job(ResultWatcher, %{post_id: fx.id})
    assert Posts.get_post!(fx.id).source_match_id == "m1"
  end

  test "finished: builds the result and publishes it straight away", %{fx: fx, start: start} do
    stub(start, card(true))
    assert :ok = perform_job(ResultWatcher, %{post_id: fx.id})

    result = Repo.get_by!(Post, parent_id: fx.id)
    assert result.status == "approved" and length(result.slide_paths) == 2
    assert_enqueued(worker: Publish, args: %{post_id: result.id})

    %{"posts" => [r]} = result.data
    assert r["result"] == "*India* won by 6 wkts"

    assert r["pom"] == %{"name" => "Virat Kohli", "figures" => "78 (44)"} and
             r["pom_label"] == "Top performer"

    assert Enum.map(r["answers"], & &1["answer"]) == ["A", "B", "A"]

    assert [
             %{"team" => "AUS", "runs" => 184},
             %{"team" => "IND", "runs" => 188, "overs" => "18.3"}
           ] = r["innings"]
  end

  test "abandoned: not posted, the result is marked failed for a human", %{fx: fx, start: start} do
    stub(start, card(true, "Match abandoned due to rain"))

    assert {:cancel, "No result: Match abandoned due to rain"} =
             perform_job(ResultWatcher, %{post_id: fx.id})

    assert %{status: "failed", error: "No result: " <> _} = Repo.get_by!(Post, parent_id: fx.id)
    refute_enqueued(worker: Publish)
  end

  test "an unscheduled fixture is left alone", %{fx: fx} do
    {:ok, _} = Posts.unapprove(fx)
    assert {:cancel, _} = perform_job(ResultWatcher, %{post_id: fx.id})
  end

  test "team codes only match whole words" do
    data = %{
      "teams" => %{"SA" => %{"name" => "South Africa"}, "PAK" => %{"name" => "Pakistan"}},
      "posts" => [%{"team1" => "SA", "team2" => "PAK"}]
    }

    card = %{
      "status" => "Pakistan won by 10 runs",
      "score" => [
        %{"r" => 150, "w" => 8, "o" => 20, "inning" => "pakistan Inning 1"},
        %{"r" => 140, "w" => 9, "o" => 20, "inning" => "south africa Inning 1"}
      ],
      "scorecard" => []
    }

    assert {:ok, %{"innings" => [%{"team" => "PAK"}, %{"team" => "SA"}]}} =
             Results.facts(card, data)
  end
end
