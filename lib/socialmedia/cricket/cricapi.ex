defmodule Socialmedia.Cricket.Cricapi do
  @moduledoc """
  Minimal client for CricketData.org (CricAPI v1), free plan (about 100 calls a day).
  https://cricketdata.org/how-to-use-cricket-data-api/

  The key comes from `CRICKETDATA_API_KEY` (prod only).
  """

  defp new do
    Req.new(
      base_url: Application.get_env(:socialmedia, :cricapi_base, "https://api.cricapi.com/v1"),
      params: [apikey: Application.get_env(:socialmedia, :cricapi_key)],
      retry: :transient,
      receive_timeout: 30_000
    )
    |> Req.merge(Application.get_env(:socialmedia, __MODULE__, []))
  end

  def configured?, do: Application.get_env(:socialmedia, :cricapi_key) not in [nil, ""]

  @doc "Recent and live matches: a list of maps with id, teams, teamInfo, dateTimeGMT, status, matchEnded."
  def current_matches, do: get("/currentMatches", offset: 0)

  @doc "One match with its innings scores and batting/bowling scorecard."
  def scorecard(id), do: get("/match_scorecard", id: id)

  defp get(url, params) do
    case Req.get(new(), url: url, params: params) do
      {:ok, %{status: 200, body: %{"status" => "success", "data" => data}}} -> {:ok, data}
      {:ok, %{status: 200, body: %{"reason" => reason}}} -> {:error, "CricketData: #{reason}"}
      {:ok, %{status: s, body: b}} -> {:error, "CricketData #{s}: #{inspect(b, limit: 5)}"}
      {:error, e} -> {:error, "CricketData request failed: #{Exception.message(e)}"}
    end
  end
end
