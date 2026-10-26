defmodule Socialmedia.Channels do
  @moduledoc "Channels and their posting slots."
  import Ecto.Query
  alias Socialmedia.Repo
  alias Socialmedia.Channels.{Channel, Schedule}

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

  def list_schedules(%Channel{id: id}) do
    Repo.all(from s in Schedule, where: s.channel_id == ^id, order_by: [s.time_of_day, s.id])
  end

  @doc "The channel's active slot for a post type, if any."
  def slot_for(%Channel{id: id}, post_type) do
    Repo.one(
      from s in Schedule,
        where: s.channel_id == ^id and s.post_type == ^post_type and s.active,
        order_by: [s.time_of_day, s.id],
        limit: 1
    )
  end

  @doc """
  Time a new post is made for (the admin picks the real time when scheduling):
  the slot's next day and time after `now`, or tomorrow at noon when the type
  has no slot. UTC.
  """
  def next_slot_time(%Channel{timezone: tz} = channel, post_type, now \\ DateTime.utc_now()) do
    today = now |> DateTime.shift_zone!(tz) |> DateTime.to_date()

    candidates =
      case slot_for(channel, post_type) do
        %Schedule{weekdays: days, time_of_day: time} ->
          for d <- 0..7,
              date = Date.add(today, d),
              Date.day_of_week(date) in days,
              do: {date, time}

        nil ->
          [{Date.add(today, 1), ~T[12:00:00]}]
      end

    Enum.find_value(candidates, fn {date, time} ->
      at = local_to_utc(date, time, tz)
      if DateTime.compare(at, now) == :gt, do: at
    end)
  end

  @doc "The slot's time (noon without a slot) on a given local date. UTC."
  def slot_time_on(%Channel{timezone: tz} = channel, post_type, %Date{} = date) do
    time =
      case slot_for(channel, post_type) do
        %Schedule{time_of_day: t} -> t
        nil -> ~T[12:00:00]
      end

    local_to_utc(date, time, tz)
  end

  defp local_to_utc(date, time, tz) do
    local =
      case DateTime.new(date, Time.truncate(time, :second), tz) do
        {:ok, dt} -> dt
        {:ambiguous, first, _} -> first
        {:gap, _, after_gap} -> after_gap
      end

    local |> DateTime.shift_zone!("Etc/UTC") |> DateTime.truncate(:second)
  end

  def get_schedule!(id), do: Repo.get!(Schedule, id)

  def change_schedule(%Schedule{} = s, attrs \\ %{}), do: Schedule.changeset(s, attrs)

  def create_schedule(attrs), do: %Schedule{} |> Schedule.changeset(attrs) |> Repo.insert()

  def update_schedule(%Schedule{} = s, attrs), do: s |> Schedule.changeset(attrs) |> Repo.update()

  def delete_schedule(%Schedule{} = s), do: Repo.delete(s)

  @doc "Absolute path to the channel's template folder."
  def template_path(%Channel{template_dir: dir}),
    do: Path.join(Socialmedia.Paths.channels_dir(), dir)
end
