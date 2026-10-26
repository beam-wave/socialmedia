defmodule Socialmedia.MatchesTest do
  use Socialmedia.DataCase, async: false
  use Oban.Testing, repo: Socialmedia.Repo
  import Socialmedia.Fixtures
  alias Socialmedia.{Content, Posts, Repo}
  alias Socialmedia.Content.Matches
  alias Socialmedia.Posts.Post
  alias Socialmedia.Workers.Produce

  setup do
    File.rm_rf!(Socialmedia.Storage.Local.root())
    ch = channel(%{skill: "mid-innings", template_dir: "mid.innings", base_data: %{}})
    %{ch: ch}
  end

  defp iso(dt), do: DateTime.to_iso8601(dt)
  defp hours(n), do: DateTime.utc_now() |> DateTime.add(n * 3600) |> DateTime.truncate(:second)

  defp fixture_data(start, type \\ "T20") do
    %{
      "teams" => %{
        "IND" => %{"code" => "IND", "name" => "India", "color" => "#1f5fd1"},
        "AUS" => %{"code" => "AUS", "name" => "Australia", "color" => "#d9a400"}
      },
      "posts" => [
        %{
          "type" => "fixture",
          "team1" => "IND",
          "team2" => "AUS",
          "start_utc" => iso(start),
          "match_type" => type,
          "series" => "T20I Series",
          "match" => "2nd T20I",
          "venue" => "Wankhede, Mumbai",
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
  end

  defp facts do
    %{
      "innings" => [
        %{
          "team" => "AUS",
          "runs" => "184",
          "wkts" => "7",
          "overs" => "20.0",
          "bat_name" => "Travis Head",
          "bat_runs" => "61",
          "bat_balls" => "39",
          "bowl_name" => "Jasprit Bumrah",
          "bowl_w" => "3",
          "bowl_r" => "24",
          "bowl_ov" => "4"
        },
        %{
          "team" => "IND",
          "runs" => "188",
          "wkts" => "4",
          "overs" => "18.3",
          "bat_name" => "Virat Kohli",
          "bat_runs" => "78*",
          "bat_balls" => "44",
          "bowl_name" => "",
          "bowl_w" => "",
          "bowl_r" => "",
          "bowl_ov" => ""
        }
      ],
      "pom" => "Kohli",
      "pom_figures" => "78* (44)",
      "result" => ""
    }
  end

  defp make_fixture(ch, at, data) do
    {:ok, fx} = Content.create(ch, %{post_type: "fixture", scheduled_at: at})
    file = Path.join(System.tmp_dir!(), "fx-#{fx.id}.jpg")
    File.write!(file, "jpg")
    {:ok, fx} = Content.upload(fx, %{data: data, caption: "c", slides: [file]})
    fx
  end

  test "a fixture creates its result post, which waits for the admin's facts", %{ch: ch} do
    start = hours(10)
    fx = make_fixture(ch, hours(5), fixture_data(start))
    assert fx.status == "uploaded"

    result = Repo.get_by!(Post, parent_id: fx.id) |> Repo.preload([:channel, :parent])
    assert result.post_type == "result" and result.status == "planned"
    assert result.scheduled_at == DateTime.add(start, (225 + 60) * 60)
    # not handed to Claude until the admin types the result
    refute_enqueued(worker: Produce, args: %{post_id: result.id})

    assert {:ok, result} = Posts.enter_facts(result, facts())
    assert result.status == "creating"
    # built by the app, so only the renderer runs
    assert_enqueued(worker: Produce, args: %{post_id: result.id, render_only: true})

    %{"posts" => [r], "teams" => %{"IND" => _}} = result.data
    assert r["result"] == "*India* beat Australia by 6 wickets"
    assert r["winner"] == "IND" and r["team1"] == "AUS"
    assert Enum.map(r["answers"], & &1["answer"]) == ["A", "B", "A"]
  end

  test "bad scores are refused with a message", %{ch: ch} do
    fx = make_fixture(ch, hours(5), fixture_data(hours(10)))
    result = Repo.get_by!(Post, parent_id: fx.id)
    bad = put_in(facts(), ["innings", Access.at(0), "runs"], "lots")
    assert {:error, "Innings 1: runs must be a whole number."} = Posts.enter_facts(result, bad)
    assert Posts.get_post!(result.id).status == "planned"
  end

  test "the result's manifest points at its fixture, so a pull links them", %{ch: ch} do
    fx = make_fixture(ch, hours(5), fixture_data(hours(10)))
    result = Repo.get_by!(Post, parent_id: fx.id)
    {:ok, result} = Posts.enter_facts(result, facts())
    file = Path.join(System.tmp_dir!(), "res-#{result.id}.jpg")
    File.write!(file, "jpg")
    {:ok, _} = Content.upload(result, %{data: %{"posts" => []}, caption: "r", slides: [file]})

    # pull both on a machine that has neither
    Repo.delete_all(Post)
    assert Content.pull_all() == 2

    pulled_fx = Repo.get_by!(Post, content_key: fx.content_key)
    assert %{parent_id: parent_id} = Repo.get_by!(Post, content_key: result.content_key)
    assert parent_id == pulled_fx.id
  end

  test "a fixture after the first ball is moved earlier", %{ch: ch} do
    start = hours(3)
    fx = make_fixture(ch, hours(5), fixture_data(start))
    assert fx.scheduled_at == DateTime.add(start, -90 * 60)

    assert [%{"scheduled_at" => at}] =
             Content.manifests() |> Enum.filter(&(&1["key"] == fx.content_key))

    assert at == iso(fx.scheduled_at)
  end

  test "one run's fixtures are split into a post per match, each with its own teams" do
    data = %{
      "theme" => "floodlight",
      "teams" => %{"IND" => %{}, "AUS" => %{}, "MI" => %{}, "CSK" => %{}},
      "posts" => [
        %{"type" => "fixture", "team1" => "IND", "team2" => "AUS"},
        %{"type" => "fixture", "team1" => "MI", "team2" => "CSK"}
      ]
    }

    assert [a, b] = Matches.split_fixtures(data)

    assert a["posts"] == [hd(data["posts"])] and
             Map.keys(a["teams"]) |> Enum.sort() == ["AUS", "IND"]

    assert Map.keys(b["teams"]) |> Enum.sort() == ["CSK", "MI"] and b["theme"] == "floodlight"
    assert Matches.split_fixtures(a) == [a]
  end

  test "the other fixtures of the day become posts that only need rendering", %{ch: ch} do
    first = make_fixture(ch, hours(30), fixture_data(hours(40)))
    second = put_in(fixture_data(hours(44)), ["posts", Access.at(0), "team1"], "AUS")

    [{:ok, extra}] =
      Content.add_fixtures(first, [second], hours(30), %{sources: [%{"url" => "u"}], notes: "n"})

    assert extra.status == "creating" and extra.post_type == "fixture"
    assert extra.data == second and extra.sources == [%{"url" => "u"}]
    refute extra.content_key == first.content_key
    assert_enqueued(worker: Produce, args: %{post_id: extra.id, render_only: true})
  end

  test "a match-day prompt asks for every match that day", %{ch: ch} do
    {:ok, fx} = Content.create(ch, %{post_type: "fixture", scheduled_at: hours(5)})

    w =
      Socialmedia.Content.Work.from_post(
        Repo.preload(Posts.get_post!(fx.id), :parent),
        "generate",
        []
      )

    assert Socialmedia.Agent.build_prompt(w) =~ "Return every relevant match"
  end

  test "rejecting the fixture drops its result post", %{ch: ch} do
    fx = insert_post(ch, %{post_type: "fixture"})
    res = insert_post(ch, %{post_type: "result", status: "planned", data: nil, parent_id: fx.id})
    {:ok, _} = Posts.reject(fx)
    assert %{status: "rejected", reject_reason: "fixture_rejected"} = Posts.get_post!(res.id)
  end
end
