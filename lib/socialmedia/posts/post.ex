defmodule Socialmedia.Posts.Post do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(planned render_requested needs_review approved publishing published failed rejected)

  schema "posts" do
    field :scheduled_at, :utc_datetime
    field :post_type, :string
    field :status, :string, default: "planned"
    # Slot the planner made this post for; scheduled_at is when it goes out (admin can move it)
    field :slot_at, :utc_datetime
    field :generate_at, :utc_datetime
    # Content request number, bumped on regenerate / re-render (names the request on the S3 bus)
    field :gen_rev, :integer, default: 1
    field :retries, :integer, default: 0
    # Facts the admin typed in (match result); the agent writes from these
    field :facts, :map
    # Template data for exactly one Instagram post (channel base_data + one item)
    field :data, :map
    field :caption, :string
    field :slide_paths, {:array, :string}, default: []
    field :sources, {:array, :map}, default: []
    field :admin_note, :string
    field :agent_log, :string
    field :error, :string
    field :reject_reason, :string
    field :approved_at, :utc_datetime
    field :published_at, :utc_datetime
    field :ig_media_id, :string
    field :permalink, :string

    belongs_to :channel, Socialmedia.Channels.Channel
    belongs_to :schedule, Socialmedia.Channels.Schedule
    # Result posts point at the fixture whose predictions they score
    belongs_to :parent, __MODULE__
    has_one :child, __MODULE__, foreign_key: :parent_id

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  def changeset(post, attrs) do
    post
    |> cast(attrs, [
      :channel_id,
      :schedule_id,
      :scheduled_at,
      :post_type,
      :status,
      :slot_at,
      :generate_at,
      :gen_rev,
      :retries,
      :parent_id,
      :facts,
      :data,
      :caption,
      :slide_paths,
      :sources,
      :admin_note,
      :agent_log,
      :error,
      :reject_reason,
      :approved_at,
      :published_at,
      :ig_media_id,
      :permalink
    ])
    |> validate_required([:channel_id, :scheduled_at, :post_type, :status])
    |> validate_inclusion(:status, @statuses)
    |> validate_length(:caption, max: 2200)
    |> unique_constraint([:schedule_id, :slot_at])
  end

  @doc "True while the post can still be edited, regenerated or approved."
  def reviewable?(%__MODULE__{status: s}),
    do: s in ~w(planned render_requested needs_review approved failed)

  def final?(%__MODULE__{status: s}), do: s in ~w(published rejected)
end
