defmodule Socialmedia.Cricket.Results do
  @moduledoc """
  Finds a fixture's match in CricketData.org and turns its finished scorecard into
  the facts `Socialmedia.Content.MatchResult` builds a result post from.
  """
  alias Socialmedia.Content.Matches

  @doc """
  The fixture's match among `matches`: the same two teams (by code or name),
  starting within a day of the fixture's start. Nil if none.
  """
  def find(matches, fixture_data) do
    fx = Matches.first_match(fixture_data) || %{}
    teams = fixture_data["teams"] || %{}
    wanted = Enum.map([fx["team1"], fx["team2"]], &names(teams, &1))
    start = parse(fx["start_utc"])

    Enum.find(matches, fn m ->
      sides =
        Enum.map(m["teamInfo"] || Enum.map(m["teams"] || [], &%{"name" => &1}), &side_names/1)

      same_teams?(wanted, sides) and near?(start, parse(m["dateTimeGMT"]))
    end)
  end

  @doc """
  Facts for a finished match, or `{:error, reason}` when it can't be posted
  automatically (abandoned, no result, more than two innings, missing scores).
  """
  def facts(card, fixture_data) do
    status = to_string(card["status"])
    teams = fixture_data["teams"] || %{}
    fx = Matches.first_match(fixture_data) || %{}
    codes = [fx["team1"], fx["team2"]]
    scores = card["score"] || []

    cond do
      status =~ ~r/abandon|no result|cancel/i ->
        {:error, "No result: #{status}"}

      length(scores) < 2 ->
        {:error, "Scorecard incomplete: #{status}"}

      length(scores) > 2 ->
        {:error, "More than two innings (Test or super over): enter it by hand"}

      true ->
        build(card, scores, status, teams, codes)
    end
  end

  defp build(card, scores, status, teams, codes) do
    innings =
      for {s, i} <- Enum.with_index(scores) do
        code = team_in(s["inning"], teams, codes)
        detail = Enum.find(card["scorecard"] || [], &(&1["inning"] == s["inning"])) || %{}
        bat = best_batter(detail["batting"] || [])
        bowl = best_bowler(detail["bowling"] || [])

        %{
          "team" => code || Enum.at(codes, i),
          "runs" => to_s(s["r"]),
          "wkts" => to_s(s["w"]),
          "overs" => to_s(s["o"]),
          "bat_name" => (bat && name(bat["batsman"])) || "",
          "bat_runs" => (bat && to_s(bat["r"])) || "",
          "bat_balls" => (bat && to_s(bat["b"])) || "",
          "bowl_name" => (bowl && name(bowl["bowler"])) || "",
          "bowl_w" => (bowl && to_s(bowl["w"])) || "",
          "bowl_r" => (bowl && to_s(bowl["r"])) || "",
          "bowl_ov" => (bowl && to_s(bowl["o"])) || ""
        }
      end

    {pom, figures} = top_performer(card["scorecard"] || [])

    {:ok,
     %{
       "innings" => innings,
       "pom" => pom,
       "pom_figures" => figures,
       "pom_label" => "Top performer",
       "result" => star_winner(status, teams, codes)
     }}
  end

  # "India won by 6 wkts" -> "*India* won by 6 wkts"
  defp star_winner(status, teams, codes) do
    Enum.reduce_while(codes, status, fn code, acc ->
      n = get_in(teams, [code, "name"]) || code

      if n && String.contains?(acc, n),
        do: {:halt, String.replace(acc, n, "*#{n}*", global: false)},
        else: {:cont, acc}
    end)
  end

  defp best_batter(rows), do: Enum.max_by(rows, &num(&1["r"]), fn -> nil end)

  defp best_bowler(rows),
    do: Enum.max_by(rows, &{num(&1["w"]), -num(&1["r"])}, fn -> nil end)

  # Most runs, or most wickets (a wicket counts as 20 runs), across the match
  defp top_performer(cards) do
    bats =
      for c <- cards,
          b <- c["batting"] || [],
          do: {num(b["r"]), name(b["batsman"]), "#{to_s(b["r"])} off #{to_s(b["b"])}"}

    bowls =
      for c <- cards,
          b <- c["bowling"] || [],
          do:
            {num(b["w"]) * 20 - num(b["r"]) / 10, name(b["bowler"]),
             "#{to_s(b["w"])}/#{to_s(b["r"])} in #{to_s(b["o"])} ov"}

    case Enum.max_by(bats ++ bowls, &elem(&1, 0), fn -> nil end) do
      {_, n, figures} -> {n, figures}
      nil -> {"", ""}
    end
  end

  # Full team names first; short codes only as whole words ("SA" must not match "pakiStAn")
  defp team_in(inning, teams, codes) do
    text = String.downcase(to_string(inning))

    Enum.find(codes, fn c ->
      n = get_in(teams, [c, "name"])
      n && String.contains?(text, String.downcase(n))
    end) ||
      Enum.find(codes, fn c -> c && text =~ ~r/\b#{Regex.escape(String.downcase(c))}\b/ end)
  end

  defp names(teams, code) do
    [code, get_in(teams, [code, "name"])]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&String.downcase/1)
  end

  defp side_names(info),
    do:
      [info["shortname"], info["name"]] |> Enum.reject(&is_nil/1) |> Enum.map(&String.downcase/1)

  defp same_teams?([a, b], [x, y]),
    do: (overlap?(a, x) and overlap?(b, y)) or (overlap?(a, y) and overlap?(b, x))

  defp same_teams?(_, _), do: false
  defp overlap?(a, b), do: Enum.any?(a, &(&1 in b))

  defp near?(nil, _), do: true
  defp near?(_, nil), do: true
  defp near?(a, b), do: abs(DateTime.diff(a, b)) <= 86_400

  defp parse(nil), do: nil

  defp parse(s) do
    s = if String.ends_with?(s, "Z") or String.contains?(s, "+"), do: s, else: s <> "Z"

    case DateTime.from_iso8601(s) do
      {:ok, at, _} -> at
      _ -> nil
    end
  end

  defp name(%{"name" => n}), do: n
  defp name(n) when is_binary(n), do: n
  defp name(_), do: ""

  defp num(n) when is_number(n), do: n

  defp num(s) when is_binary(s) do
    case Float.parse(s) do
      {f, _} -> f
      :error -> 0
    end
  end

  defp num(_), do: 0

  defp to_s(nil), do: ""

  defp to_s(n) when is_float(n),
    do: if(n == trunc(n), do: Integer.to_string(trunc(n)), else: Float.to_string(n))

  defp to_s(n), do: to_string(n)
end
