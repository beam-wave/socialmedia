defmodule Socialmedia.Workers.ContentPoller do
  @moduledoc """
  Content node (Mac, CONTENT=true): reads plan.json from S3 and queues a
  Produce job per request not yet delivered. Each (post_id, rev) runs once.
  """
  use Oban.Worker, queue: :planner, max_attempts: 1, unique: [period: 60]
  require Logger
  alias Socialmedia.Content
  alias Socialmedia.Content.Work
  alias Socialmedia.Workers.Produce

  def enqueue, do: %{} |> new() |> Oban.insert()

  @impl Oban.Worker
  def perform(_job) do
    case Content.read_plan() do
      {:ok, works} ->
        for w <- works, not Content.delivered?(w) do
          w |> Work.to_json_map() |> Produce.new() |> Oban.insert!()
        end

        :ok

      {:error, reason} ->
        Logger.warning("could not read plan.json: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
