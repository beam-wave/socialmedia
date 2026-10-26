defmodule Socialmedia.MatchesTest do
  use Socialmedia.DataCase, async: false
  use Oban.Testing, repo: Socialmedia.Repo
  import Socialmedia.Fixtures
  alias Socialmedia.{Content, Posts, Repo}
  alias Socialmedia.Posts.Post
  alias Socialmedia.Content.Work
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
      "posts" => [
        %{
          "type" => "fixture",
          "team1" => "IND",
          "team2" => "AUS",
          "start_utc" => iso(start),
          "match_type" => type,
          "questions" => [%{"q" => "Who wins the match?", "options" => ["India", "Australia"]}]
        }
      ]
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

    facts = %{
      "summary" => "India won by 6 wkts",
      "pom" => "Kohli 78* (44)",
      "innings" => [%{"team" => "AUS", "score" => "184/7 (20)"}]
    }

    assert {:ok, result} = Posts.enter_facts(result, facts)
    assert result.status == "creating"
    assert_enqueued(worker: Produce, args: %{post_id: result.id})

    # Claude gets the facts plus the fixture whose questions it scores
    result = Repo.preload(Posts.get_post!(result.id), :parent)
    w = Work.from_post(result, "generate", [])
    assert w.facts == facts
    assert w.related["posts"] |> hd() |> Map.get("questions") |> length() == 1
    assert Socialmedia.Agent.build_prompt(w) =~ "Match facts entered by the admin"
  end

  test "the result's manifest points at its fixture, so a pull links them", %{ch: ch} do
    fx = make_fixture(ch, hours(5), fixture_data(hours(10)))
    result = Repo.get_by!(Post, parent_id: fx.id)
    {:ok, result} = Posts.enter_facts(result, %{"pom" => "x", "innings" => []})
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

  test "rejecting the fixture drops its result post", %{ch: ch} do
    fx = insert_post(ch, %{post_type: "fixture"})
    res = insert_post(ch, %{post_type: "result", status: "planned", data: nil, parent_id: fx.id})
    {:ok, _} = Posts.reject(fx)
    assert %{status: "rejected", reject_reason: "fixture_rejected"} = Posts.get_post!(res.id)
  end
end
