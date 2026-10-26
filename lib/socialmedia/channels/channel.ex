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
    field :hashtags, :string
    field :ig_user_id, :string
    field :access_token, Socialmedia.Encrypted.Binary, redact: true
    field :token_expires_at, :utc_datetime
    field :dry_run, :boolean, default: true
    field :active, :boolean, default: true
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
      :hashtags,
      :ig_user_id,
      :access_token,
      :token_expires_at,
      :dry_run,
      :active,
      :base_data
    ])
    |> validate_required([:name, :handle, :skill, :template_dir, :timezone])
    |> validate_format(:handle, ~r/^@[\w.]+$/)
    |> validate_change(:timezone, fn :timezone, tz ->
      if Tzdata.zone_exists?(tz), do: [], else: [timezone: "is not a known timezone"]
    end)
    |> unique_constraint(:handle)
  end
end
