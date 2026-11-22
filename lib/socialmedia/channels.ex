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
    "bollyvibe" => ["movie"],
    "ogbook" => ["promo"],
    "english-vinglish" => ["word"]
  }

  @doc "Post types the Create form offers for a channel (all of them for an unknown skill)."
  def post_types(%Channel{skill: skill}),
    do: Map.get(@post_types, skill, ~w(quote top5 fixture movie promo words word))

  # Time left before a default post time for a new post to still take it today
  @lead_minutes 30

  @doc """
  Time a new post is made for, in UTC, at the channel's default post time
  (noon when unset). With a `date`, on that day. Otherwise the day after the
  channel's latest post, so new posts fill consecutive days; with no upcoming
  post, the next occurrence at least #{@lead_minutes} minutes away. Failed and
  rejected posts don't hold a day. The agent uses it for dates; it's the time
  the Schedule form starts from.
  """
  def made_for(%Channel{timezone: tz} = channel, date \\ nil, now \\ DateTime.utc_now()) do
    time = channel.default_post_time || ~T[12:00:00]

    if date do
      local_utc(date, time, tz)
    else
      today = now |> DateTime.shift_zone!(tz) |> DateTime.to_date()
      soon = DateTime.add(now, @lead_minutes * 60)
      at = local_utc(today, time, tz)

      next =
        if DateTime.compare(at, soon) == :gt,
          do: at,
          else: local_utc(Date.add(today, 1), time, tz)

      case latest_post_day(channel) do
        nil -> next
        last_day -> Enum.max([next, local_utc(Date.add(last_day, 1), time, tz)], DateTime)
      end
    end
  end

  # Local date of the channel's latest post that still holds its day
  defp latest_post_day(%Channel{id: id, timezone: tz}) do
    Repo.one(
      from p in Socialmedia.Posts.Post,
        where: p.channel_id == ^id and p.status not in ["rejected", "failed"],
        select: max(p.scheduled_at)
    )
    |> case do
      nil -> nil
      at -> at |> DateTime.shift_zone!(tz) |> DateTime.to_date()
    end
  end

  defp local_utc(date, time, tz) do
    local =
      case DateTime.new(date, Time.truncate(time, :second), tz) do
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
