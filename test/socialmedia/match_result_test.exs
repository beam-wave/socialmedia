defmodule Socialmedia.MatchResultTest do
  use ExUnit.Case, async: true
  alias Socialmedia.Content.MatchResult
  alias Socialmedia.Posts.Post

  @teams %{
    "IND" => %{"code" => "IND", "name" => "India", "color" => "#1f5fd1"},
    "AUS" => %{"code" => "AUS", "name" => "Australia", "color" => "#d9a400"}
  }

  defp post do
    fixture = %Post{
      data: %{
        "teams" => @teams,
        "posts" => [
          %{
            "team1" => "IND",
            "team2" => "AUS",
            "series" => "S",
            "match" => "M",
            "venue" => "V",
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
    }

    %Post{
      parent: fixture,
      channel: %{handle: "@mid.innings", base_data: %{"theme" => "floodlight"}}
    }
  end

  defp inn(team, runs, wkts, extra \\ %{}) do
    Map.merge(
      %{
        "team" => team,
        "runs" => runs,
        "wkts" => wkts,
        "overs" => "20.0",
        "bat_name" => "",
        "bat_runs" => "",
        "bat_balls" => "",
        "bowl_name" => "",
        "bowl_w" => "",
        "bowl_r" => "",
        "bowl_ov" => ""
      },
      extra
    )
  end

  defp build(i1, i2, pom \\ "Pat Cummins", line \\ "") do
    {:ok, %{"posts" => [r]} = data} =
      MatchResult.build(post(), %{
        "innings" => [i1, i2],
        "pom" => pom,
        "pom_figures" => "4/20",
        "result" => line
      })

    {r, data}
  end

  test "team batting first wins by runs; answers marked" do
    {r, data} = build(inn("IND", "200", "5"), inn("AUS", "170", "10"))
    assert r["result"] == "*India* beat Australia by 30 runs"
    assert r["winner"] == "IND"
    assert Enum.map(r["answers"], & &1["answer"]) == ["A", "C", "B"]
    assert hd(tl(r["answers"]))["note"] == "India made 200/5"
    assert data["handle"] == "@mid.innings" and data["theme"] == "floodlight"
    assert data["teams"] == @teams
  end

  test "chasing team wins by wickets; one wicket is singular" do
    {r, _} = build(inn("IND", "150", "8"), inn("AUS", "151", "9"))
    assert r["result"] == "*Australia* beat India by 1 wicket"
    assert Enum.at(r["answers"], 1)["answer"] == "A"
  end

  test "band edges: 190 is 190+, 160 is 160–190" do
    {r, _} = build(inn("IND", "190", "5"), inn("AUS", "100", "10"))
    assert Enum.at(r["answers"], 1)["answer"] == "C"
    {r, _} = build(inn("IND", "160", "5"), inn("AUS", "100", "10"))
    assert Enum.at(r["answers"], 1)["answer"] == "B"
  end

  test "a tie, an unlisted POM, and a manual result line" do
    {r, _} = build(inn("IND", "160", "5"), inn("AUS", "160", "8"), "Someone Else")
    assert r["result"] == "Match *tied*" and r["winner"] == ""
    assert Enum.map(r["answers"], & &1["answer"]) == ["X", "B", "X"]

    {r, _} =
      build(
        inn("IND", "160", "5"),
        inn("AUS", "120", "6"),
        "Pat Cummins",
        "*India* won by 40 runs (DLS)"
      )

    assert r["result"] == "*India* won by 40 runs (DLS)"
  end

  test "best batter and bowler go on the right sides" do
    {r, _} =
      build(
        inn("IND", "200", "5", %{
          "bat_name" => "Kohli",
          "bat_runs" => "78*",
          "bat_balls" => "44",
          "bowl_name" => "Cummins",
          "bowl_w" => "3",
          "bowl_r" => "30",
          "bowl_ov" => "4"
        }),
        inn("AUS", "170", "10")
      )

    assert r["bat"] == [%{"name" => "Kohli", "team" => "IND", "runs" => "78*", "balls" => 44}]

    assert r["bowl"] == [
             %{"name" => "Cummins", "team" => "AUS", "w" => 3, "r" => 30, "ov" => "4"}
           ]
  end

  test "errors name the field" do
    assert {:error, "Innings 2: wickets must be a whole number."} =
             MatchResult.build(post(), %{
               "innings" => [inn("IND", "1", "1"), inn("AUS", "1", "x")],
               "pom" => "P"
             })

    assert {:error, "Both innings have the same batting team."} =
             MatchResult.build(post(), %{
               "innings" => [inn("IND", "1", "1"), inn("IND", "1", "1")],
               "pom" => "P"
             })

    assert {:error, "Enter the player of the match."} =
             MatchResult.build(post(), %{
               "innings" => [inn("IND", "1", "1"), inn("AUS", "1", "1")],
               "pom" => ""
             })

    assert {:error, "This result has no fixture to score."} = MatchResult.build(%Post{}, %{})
  end
end
