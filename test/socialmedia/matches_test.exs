defmodule Socialmedia.MatchesTest do
  use Socialmedia.DataCase, async: false
  import Socialmedia.Fixtures
  alias Socialmedia.{Content, Posts, Repo}
  alias Socialmedia.Posts.Post

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

  defp deliver_fixture(post, data) do
    {:ok, _} = Content.publish_plan()
    {:ok, [w]} = Content.read_plan()
    file = Path.join(System.tmp_dir!(), "fx-#{post.id}.jpg")
    File.write!(file, "jpg")
    :ok = Content.deliver(w, %{data: data, caption: "c", slides: [file]})
    Content.import_inbox()
    Posts.get_post!(post.id)
  end

  test "a fixture creates its result post, which waits for the admin's facts", %{ch: ch} do
    start = hours(10)

    fx =
      insert_post(ch, %{
        post_type: "fixture",
        status: "planned",
        data: nil,
        slide_paths: [],
        scheduled_at: hours(5),
        generate_at: hours(-1)
      })

    fx = deliver_fixture(fx, fixture_data(start))
    assert fx.status == "needs_review"

    result = Repo.get_by!(Post, parent_id: fx.id) |> Repo.preload([:channel, :parent])
    assert result.post_type == "result" and result.status == "planned"
    assert result.scheduled_at == DateTime.add(start, (225 + 60) * 60)
    # not handed to Claude until the admin types the result
    assert is_nil(result.generate_at)
    assert [] = Content.pending_work()

    facts = %{
      "summary" => "India won by 6 wkts",
      "pom" => "Kohli 78* (44)",
      "innings" => [%{"team" => "AUS", "score" => "184/7 (20)"}]
    }

    assert {:ok, result} = Posts.enter_facts(result, facts)
    assert result.status == "planned" and result.gen_rev == 2

    # Claude gets the facts plus the fixture whose questions it scores
    [%{kind: "generate", facts: ^facts, related: related} = w] = Content.pending_work()
    assert related["posts"] |> hd() |> Map.get("questions") |> length() == 1
    assert Socialmedia.Agent.build_prompt(w) =~ "Match facts entered by the admin"
  end

  test "a fixture slot after the first ball is moved earlier", %{ch: ch} do
    start = hours(3)

    fx =
      insert_post(ch, %{
        post_type: "fixture",
        status: "planned",
        data: nil,
        slide_paths: [],
        scheduled_at: hours(5),
        generate_at: hours(-1)
      })

    fx = deliver_fixture(fx, fixture_data(start))
    assert fx.scheduled_at == DateTime.add(start, -90 * 60)
  end

  test "match not over: the result is retried later as a new revision", %{ch: ch} do
    fx = insert_post(ch, %{post_type: "fixture"})

    res =
      insert_post(ch, %{
        post_type: "result",
        status: "planned",
        data: nil,
        slide_paths: [],
        parent_id: fx.id,
        scheduled_at: hours(1),
        generate_at: hours(-1)
      })

    {:ok, _} = Content.publish_plan()
    {:ok, [w]} = Content.read_plan()
    :ok = Content.deliver_failure(w, "2nd innings, 14 overs", true, 60)
    Content.import_inbox()

    res = Posts.get_post!(res.id)
    assert res.status == "planned" and res.gen_rev == 2 and res.retries == 1
    assert DateTime.diff(res.generate_at, DateTime.utc_now()) in 3500..3600
    # still 45 min of review time after the new writing time
    assert DateTime.diff(res.scheduled_at, res.generate_at) >= 45 * 60
    assert res.error =~ "14 overs"
  end

  test "rejecting the fixture drops its result post", %{ch: ch} do
    fx = insert_post(ch, %{post_type: "fixture"})
    res = insert_post(ch, %{post_type: "result", status: "planned", data: nil, parent_id: fx.id})
    {:ok, _} = Posts.reject(fx)
    assert %{status: "rejected", reject_reason: "fixture_rejected"} = Posts.get_post!(res.id)
  end
end
