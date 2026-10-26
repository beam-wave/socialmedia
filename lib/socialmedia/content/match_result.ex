defmodule Socialmedia.Content.MatchResult do
  @moduledoc """
  Builds a @mid.innings result post from the scores the admin enters. No agent:
  the winner and margin come from the two innings, and the fixture's three
  predictions (who wins, first-innings score band, player of the match) are
  marked against the result.

  Facts, as the form sends them (every value a string):

      %{"innings" => [%{"team", "runs", "wkts", "overs",
                        "bat_name", "bat_runs", "bat_balls",
                        "bowl_name", "bowl_w", "bowl_r", "bowl_ov"}, …2],
        "pom" => name, "pom_figures" => "78* (44)",
        "result" => optional line that replaces the worked-out one (e.g. DLS)}
  """
  alias Socialmedia.Posts.Post
  alias Socialmedia.Content.Matches

  @hook %{
    "q" => "What was the *turning point* of the match? Comment your view 👇",
    "q_hi" => "मैच का *टर्निंग पॉइंट* क्या था? कमेंट में अपनी राय लिखो 👇"
  }

  @innings_fields ~w(team runs wkts overs bat_name bat_runs bat_balls bowl_name bowl_w bowl_r bowl_ov)

  @doc "Empty facts for the form: the fixture's teams in batting order."
  def blank(%Post{parent: %Post{data: fx_data}}) do
    fx = Matches.first_match(fx_data) || %{}

    %{
      "innings" => [blank_innings(fx["team1"]), blank_innings(fx["team2"])],
      "pom" => "",
      "pom_figures" => "",
      "result" => ""
    }
  end

  def blank(_), do: %{"innings" => [], "pom" => "", "pom_figures" => "", "result" => ""}

  defp blank_innings(team), do: @innings_fields |> Map.new(&{&1, ""}) |> Map.put("team", team)

  @doc "Trims the form params into facts (innings in order)."
  def clean(params) do
    innings =
      params
      |> Map.get("innings", %{})
      |> Enum.sort_by(fn {k, _} -> String.to_integer(k) end)
      |> Enum.map(fn {_, inn} -> Map.new(@innings_fields, &{&1, String.trim(inn[&1] || "")}) end)

    %{
      "innings" => innings,
      "pom" => String.trim(params["pom"] || ""),
      "pom_figures" => String.trim(params["pom_figures"] || ""),
      "result" => String.trim(params["result"] || "")
    }
  end

  @doc """
  Template data for the result post: `{:ok, data}` or `{:error, message}` for
  the admin. `post` is preloaded with `:parent` (the fixture) and `:channel`.
  """
  def build(%Post{parent: %Post{data: %{} = fx_data}, channel: channel}, facts) do
    fx = Matches.first_match(fx_data) || %{}
    teams = fx_data["teams"] || %{}

    with {:ok, [i1, i2]} <- innings(facts["innings"], teams),
         {:ok, pom} <- pom(facts) do
      {winner, line} = outcome(i1, i2, teams)

      post = %{
        "type" => "result",
        "series" => fx["series"],
        "match" => fx["match"],
        "venue" => fx["venue"],
        "team1" => i1.team,
        "team2" => i2.team,
        "winner" => winner,
        "result" => if(facts["result"] in [nil, ""], do: line, else: facts["result"]),
        "innings" => Enum.map([i1, i2], & &1.score),
        "pom" => pom,
        "bat" => Enum.flat_map([i1, i2], & &1.bat),
        "bowl" => Enum.flat_map([i1, i2], & &1.bowl),
        "hook" => @hook,
        "answers" => answers(fx["questions"] || [], winner, i1, pom, teams)
      }

      {:ok,
       channel.base_data
       |> Map.drop(["series_start"])
       |> Map.merge(%{"handle" => channel.handle, "teams" => teams, "posts" => [post]})}
    end
  end

  def build(_post, _facts), do: {:error, "This result has no fixture to score."}

  ## Innings

  defp innings([a, b], teams) do
    with {:ok, i1} <- one_innings(a, 1, teams),
         {:ok, i2} <- one_innings(b, 2, teams) do
      if i1.team == i2.team,
        do: {:error, "Both innings have the same batting team."},
        else: {:ok, [bowled_by(i1, i2.team), bowled_by(i2, i1.team)]}
    end
  end

  defp innings(_, _), do: {:error, "Enter both innings."}

  defp one_innings(f, n, teams) do
    with true <-
           Map.has_key?(teams, f["team"]) || {:error, "Innings #{n}: pick the batting team."},
         {:ok, runs} <- int(f["runs"], "Innings #{n}: runs"),
         {:ok, wkts} <- int(f["wkts"], "Innings #{n}: wickets"),
         true <- wkts in 0..10 || {:error, "Innings #{n}: wickets must be 0 to 10."},
         true <- f["overs"] != "" || {:error, "Innings #{n}: enter the overs."},
         {:ok, bat} <- batter(f, n),
         {:ok, bowl} <- bowler(f, n) do
      {:ok,
       %{
         team: f["team"],
         runs: runs,
         wkts: wkts,
         score: %{"team" => f["team"], "runs" => runs, "wkts" => wkts, "overs" => f["overs"]},
         bat: bat,
         bowl: bowl
       }}
    end
  end

  # The best batter bats for this innings' team; the best bowler bowls for the other one
  defp bowled_by(inn, other), do: %{inn | bowl: Enum.map(inn.bowl, &Map.put(&1, "team", other))}

  defp batter(%{"bat_name" => ""}, _n), do: {:ok, []}

  defp batter(f, n) do
    with {:ok, balls} <- int(f["bat_balls"], "Innings #{n}: best batter's balls") do
      runs = if f["bat_runs"] == "", do: "0", else: f["bat_runs"]
      {:ok, [%{"name" => f["bat_name"], "team" => f["team"], "runs" => runs, "balls" => balls}]}
    end
  end

  defp bowler(%{"bowl_name" => ""}, _n), do: {:ok, []}

  defp bowler(f, n) do
    with {:ok, w} <- int(f["bowl_w"], "Innings #{n}: best bowler's wickets"),
         {:ok, r} <- int(f["bowl_r"], "Innings #{n}: best bowler's runs") do
      {:ok, [%{"name" => f["bowl_name"], "w" => w, "r" => r, "ov" => f["bowl_ov"]}]}
    end
  end

  defp pom(%{"pom" => ""}), do: {:error, "Enter the player of the match."}
  defp pom(f), do: {:ok, %{"name" => f["pom"], "figures" => f["pom_figures"] || ""}}

  defp int(s, label) do
    case Integer.parse(s || "") do
      {n, ""} when n >= 0 -> {:ok, n}
      _ -> {:error, "#{label} must be a whole number."}
    end
  end

  ## Outcome

  defp outcome(i1, i2, teams) do
    cond do
      i2.runs > i1.runs ->
        {i2.team,
         "*#{name(teams, i2.team)}* beat #{name(teams, i1.team)} by #{plural(10 - i2.wkts, "wicket")}"}

      i1.runs > i2.runs ->
        {i1.team,
         "*#{name(teams, i1.team)}* beat #{name(teams, i2.team)} by #{plural(i1.runs - i2.runs, "run")}"}

      true ->
        {"", "Match *tied*"}
    end
  end

  defp name(teams, code), do: get_in(teams, [code, "name"]) || code

  defp plural(1, word), do: "1 #{word}"
  defp plural(n, word), do: "#{n} #{word}s"

  ## Prediction answers

  # Q1 who wins, Q2 first-innings score band, Q3 player of the match
  defp answers([q1, q2, q3], winner, i1, pom, teams) do
    [
      answer(q1, &same_team?(&1, winner, teams), winner_note(winner, teams)),
      answer(q2, &in_band?(&1, i1.runs), "#{name(teams, i1.team)} made #{i1.runs}/#{i1.wkts}"),
      answer(q3, &same_player?(&1, pom["name"]), "#{pom["name"]} was player of the match")
    ]
  end

  defp answers(_questions, _winner, _i1, _pom, _teams), do: []

  defp answer(%{"q" => q, "options" => opts}, match?, note) do
    letter =
      case Enum.find_index(opts, match?) do
        nil -> "X"
        i -> <<?A + i>>
      end

    %{"q" => q, "options" => opts, "answer" => letter, "note" => String.slice(note, 0, 60)}
  end

  defp winner_note("", _teams), do: "The match was tied"
  defp winner_note(code, teams), do: "#{name(teams, code)} won"

  defp same_team?(_option, "", _teams), do: false

  defp same_team?(option, code, teams),
    do: norm(option) in [norm(code), norm(name(teams, code))]

  defp same_player?(option, pom) do
    {a, b} = {norm(option), norm(pom)}
    a == b or String.contains?(a, b) or String.contains?(b, a)
  end

  # "Under 160", "160–190" (from 160, below 190) or "190+"
  defp in_band?(option, runs) do
    nums = Regex.scan(~r/\d+/, option) |> Enum.map(fn [n] -> String.to_integer(n) end)

    cond do
      String.contains?(String.downcase(option), "under") -> match?([n | _] when runs < n, nums)
      String.contains?(option, "+") -> match?([n | _] when runs >= n, nums)
      length(nums) >= 2 -> Enum.at(nums, 0) <= runs and runs < Enum.at(nums, 1)
      true -> false
    end
  end

  defp norm(s), do: s |> to_string() |> String.downcase() |> String.trim()
end
