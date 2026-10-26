defmodule Socialmedia.Channels do
  @moduledoc "Channels and the post types they make."
  import Ecto.Query
  alias Socialmedia.Repo
  alias Socialmedia.Channels.Channel

  def list_channels do
    Repo.all(from c in Channel, order_by: c.name)
  end

  def list_active_channels do
    Repo.all(from c in Channel, where: c.active, order_by: c.name)
  end

  def get_channel!(id), do: Repo.get!(Channel, id)

  def get_channel_by_handle(handle), do: Repo.get_by(Channel, handle: handle)

  def change_channel(%Channel{} = c, attrs \\ %{}), do: Channel.changeset(c, attrs)

  def create_channel(attrs), do: %Channel{} |> Channel.changeset(attrs) |> Repo.insert()

  def update_channel(%Channel{} = c, attrs), do: c |> Channel.changeset(attrs) |> Repo.update()

  # What each channel's skill writes. Result posts come from fixtures, not Create.
  @post_types %{
    "motivation2live" => ["quote"],
    "puree-heartz" => ["quote"],
    "spotlight-startups" => ["top5"],
    "mid-innings" => ["fixture"],
    "bollyvibe" => ["movie"]
  }

  @doc "Post types the Create form offers for a channel (all of them for an unknown skill)."
  def post_types(%Channel{skill: skill}),
    do: Map.get(@post_types, skill, ~w(quote top5 fixture movie))

  @doc """
  Time a new post is made for, at noon on `date` (default tomorrow) in the
  channel's timezone. The agent uses it for dates and the admin picks the real
  time when scheduling. UTC.
  """
  def made_for(%Channel{timezone: tz}, date \\ nil) do
    date = date || tz |> DateTime.now!() |> DateTime.to_date() |> Date.add(1)

    local =
      case DateTime.new(date, ~T[12:00:00], tz) do
        {:ok, dt} -> dt
        {:ambiguous, first, _} -> first
        {:gap, _, after_gap} -> after_gap
      end

    local |> DateTime.shift_zone!("Etc/UTC") |> DateTime.truncate(:second)
  end

  @doc "Absolute path to the channel's template folder."
  def template_path(%Channel{template_dir: dir}),
    do: Path.join(Socialmedia.Paths.channels_dir(), dir)
end
