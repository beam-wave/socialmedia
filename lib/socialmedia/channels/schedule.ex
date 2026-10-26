defmodule Socialmedia.Channels.Schedule do
  use Ecto.Schema
  import Ecto.Changeset

  @post_types ~w(quote top5 fixture result movie)

  # A slot gives a post type its default time (the next matching day) and its agent instructions.
  schema "schedules" do
    field :post_type, :string
    # ISO weekdays, 1 = Monday ... 7 = Sunday
    field :weekdays, {:array, :integer}, default: []
    # Local time in the channel's timezone
    field :time_of_day, :time
    field :extra_instructions, :string
    field :active, :boolean, default: true

    belongs_to :channel, Socialmedia.Channels.Channel

    timestamps(type: :utc_datetime)
  end

  def post_types, do: @post_types

  def changeset(schedule, attrs) do
    schedule
    |> cast(attrs, [
      :channel_id,
      :post_type,
      :weekdays,
      :time_of_day,
      :extra_instructions,
      :active
    ])
    |> validate_required([:channel_id, :post_type, :weekdays, :time_of_day])
    |> validate_inclusion(:post_type, @post_types)
    |> validate_length(:weekdays, min: 1, message: "pick at least one day")
    |> validate_subset(:weekdays, Enum.to_list(1..7))
  end
end
