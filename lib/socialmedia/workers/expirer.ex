defmodule Socialmedia.Workers.Expirer do
  @moduledoc """
  Only approved posts go live. Any post whose time has passed without approval
  is rejected (`not_approved_in_time`). Uploaded posts are left alone: they're
  scheduled wherever they're pulled, and their data still tells the agent what
  this channel has already posted.
  """
  use Oban.Worker, queue: :maintenance, max_attempts: 1
  import Ecto.Query
  alias Socialmedia.{Repo, Posts}
  alias Socialmedia.Posts.Post

  @impl Oban.Worker
  def perform(_job) do
    expire(DateTime.utc_now())
    :ok
  end

  def expire(now) do
    Repo.all(
      from p in Post,
        where: p.scheduled_at <= ^now,
        where: p.status not in ["uploaded", "approved", "publishing", "published", "rejected"]
    )
    |> Enum.map(&Posts.reject(&1, "not_approved_in_time"))
  end
end
