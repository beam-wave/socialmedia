defmodule Socialmedia.Posts.Post do
  use Ecto.Schema
  import Ecto.Changeset

  # creating: Claude + the renderer are on it. uploaded: in S3, waiting for a Pull.
  # planned: a result post waiting for the admin's match facts.
  @statuses ~w(planned creating uploaded needs_review approved publishing published failed rejected)

  schema "posts" do
    field :scheduled_at, :utc_datetime
    field :post_type, :string
    field :status, :string, default: "creating"
    # Same on every machine; the post's folder in S3 (content/<key>/, inbox/<key>.json)
    field :content_key, :string
    # Day N / quote N for series channels, taken in order when the post is created
    field :series_number, :integer

    # Fixtures: when the match should be over (the result check starts then), and its id in the results API
    field :ends_at, :utc_datetime
    field :source_match_id, :string
    # Facts the admin typed in (match result); the agent writes from these
    field :facts, :map
    # Template data for exactly one Instagram post (channel base_data + one item)
    field :data, :map
    field :caption, :string
    field :slide_paths, {:array, :string}, default: []
    # "post" (photo/carousel) and/or "reel" (animated video); both go out at scheduled_at
    field :formats, {:array, :string}, default: ["post"]
    field :video_path, :string
    field :cover_path, :string
    field :reel_media_id, :string
    field :reel_permalink, :string
    # The trending track attached when the reel was published (title, artist, audio_id)
    field :reel_audio, :map
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
      :scheduled_at,
      :post_type,
      :status,
      :content_key,
      :series_number,
      :ends_at,
      :source_match_id,
      :parent_id,
      :facts,
      :data,
      :caption,
      :slide_paths,
      :formats,
      :video_path,
      :cover_path,
      :reel_media_id,
      :reel_permalink,
      :reel_audio,
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
    |> put_new_key()
    |> validate_required([:channel_id, :scheduled_at, :post_type, :status, :content_key])
    |> validate_inclusion(:status, @statuses)
    |> validate_length(:caption, max: 2200)
    |> unique_constraint(:content_key)
  end

  defp put_new_key(cs) do
    if get_field(cs, :content_key),
      do: cs,
      else: put_change(cs, :content_key, Ecto.UUID.generate())
  end

  @doc "True while the post can still be edited, regenerated or approved."
  def reviewable?(%__MODULE__{status: s}),
    do: s in ~w(planned creating uploaded needs_review approved failed)

  def final?(%__MODULE__{status: s}), do: s in ~w(published rejected)

  def reel?(%__MODULE__{formats: f}), do: "reel" in (f || [])
  def photo?(%__MODULE__{formats: f}), do: "post" in (f || ["post"])
end
