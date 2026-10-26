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

  def list_active_schedules do
    Repo.all(
      from s in Schedule,
        join: c in assoc(s, :channel),
        where: s.active and c.active,
        preload: [channel: c]
    )
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
