defmodule Socialmedia.Channels.Channel do
  use Ecto.Schema
  import Ecto.Changeset

  schema "channels" do
    field :name, :string
    field :handle, :string
    # Skill folder under agent/.claude/skills that writes this channel's posts
    field :skill, :string
    # Folder under channels/ holding template.html
    field :template_dir, :string
    field :timezone, :string, default: "Asia/Kolkata"
    # When this channel's posts usually go out (channel timezone); new posts start at it
    field :default_post_time, :time
    field :hashtags, :string
    field :ig_user_id, :string
    field :access_token, Socialmedia.Encrypted.Binary, redact: true
    field :token_expires_at, :utc_datetime
    field :dry_run, :boolean, default: true
    field :active, :boolean, default: true
    # What one Create makes: the photo/carousel post, the animated reel, or both
    field :make_post, :boolean, default: true
    field :make_reel, :boolean, default: false
    # Channel-level template fields (theme, handle, tags...) merged under every post's data
    field :base_data, :map, default: %{}

    has_many :posts, Socialmedia.Posts.Post

    timestamps(type: :utc_datetime)
  end

  def changeset(channel, attrs) do
    channel
    |> cast(attrs, [
      :name,
      :handle,
      :skill,
      :template_dir,
      :timezone,
      :default_post_time,
      :hashtags,
      :ig_user_id,
      :access_token,
      :token_expires_at,
      :dry_run,
      :active,
      :make_post,
      :make_reel,
      :base_data
    ])
    |> validate_required([:name, :handle, :skill, :template_dir, :timezone])
    |> validate_format(:handle, ~r/^@[\w.]+$/)
    |> validate_change(:timezone, fn :timezone, tz ->
      if Tzdata.zone_exists?(tz), do: [], else: [timezone: "is not a known timezone"]
    end)
    |> validate_format_choice()
    |> update_change(:access_token, &(&1 && String.trim(&1)))
    |> unique_constraint(:handle)
  end

  defp validate_format_choice(cs) do
    if get_field(cs, :make_post) or get_field(cs, :make_reel),
      do: cs,
      else: add_error(cs, :make_post, "pick at least one: post or reel")
  end

  @doc "What one Create makes for this channel: [\"post\"], [\"reel\"] or both."
  def formats(%__MODULE__{} = c),
    do: for({f, true} <- [{"post", c.make_post}, {"reel", c.make_reel}], do: f)
end
