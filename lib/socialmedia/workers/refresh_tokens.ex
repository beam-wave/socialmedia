defmodule Socialmedia.Workers.RefreshTokens do
  @moduledoc "Extends Instagram long-lived tokens (60 days) that expire within 20 days."
  use Oban.Worker, queue: :maintenance, max_attempts: 3
  require Logger
  alias Socialmedia.Channels
  alias Socialmedia.Instagram.Graph

  @window_days 20

  @impl Oban.Worker
  def perform(_job) do
    soon = DateTime.add(DateTime.utc_now(), @window_days * 86_400)

    for ch <- Channels.list_channels(),
        ch.access_token,
        is_nil(ch.token_expires_at) or DateTime.compare(ch.token_expires_at, soon) == :lt do
      case Graph.refresh_token(ch.access_token) do
        {:ok, token, secs} ->
          expires = DateTime.utc_now() |> DateTime.add(secs) |> DateTime.truncate(:second)
          Channels.update_channel(ch, %{access_token: token, token_expires_at: expires})

        {:error, reason} ->
          Logger.warning("token refresh failed for #{ch.handle}: #{inspect(reason)}")
      end
    end

    :ok
  end
end
