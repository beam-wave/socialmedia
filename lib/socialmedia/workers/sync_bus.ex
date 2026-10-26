defmodule Socialmedia.Workers.SyncBus do
  @moduledoc """
  Primary (prod) side of the S3 bus: import finished content from inbox/,
  then publish a fresh plan.json for the content node.
  """
  use Oban.Worker, queue: :maintenance, max_attempts: 3, unique: [period: 30, states: :incomplete]
  require Logger
  alias Socialmedia.Content

  def enqueue, do: %{} |> new() |> Oban.insert()

  @impl Oban.Worker
  def perform(_job) do
    imported = Content.import_inbox()
    {:ok, pending} = Content.publish_plan()
    if imported > 0, do: Logger.info("sync: imported #{imported}, #{pending} waiting for content")
    :ok
  end
end
