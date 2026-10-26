defmodule Socialmedia.Content.Work do
  @moduledoc """
  A unit of content work handed to a content node: generate (agent + render) or
  render only. Prod publishes pending work as JSON in `plan.json` on S3; the
  content node (your Mac) reads it from there.
  """
  alias Socialmedia.Posts.Post

  @enforce_keys [:kind, :post_id, :rev, :post_type, :scheduled_at, :channel]
  defstruct [
    :kind,
    :post_id,
    :rev,
    :post_type,
    :scheduled_at,
    :admin_note,
    :extra_instructions,
    :data,
    :channel,
    # Data of the linked fixture post, for result posts
    :related,
    # Facts entered by the admin (match result)
    :facts,
    recent: []
  ]

  @channel_fields ~w(handle skill template_dir timezone base_data)a

  @doc "Builds work from a post preloaded with :channel and :schedule."
  def from_post(%Post{} = post, kind, recent) when kind in ["generate", "render"] do
    %__MODULE__{
      kind: kind,
      post_id: post.id,
      rev: post.gen_rev,
      post_type: post.post_type,
      scheduled_at: post.scheduled_at,
      admin_note: post.admin_note,
      extra_instructions: post.schedule && post.schedule.extra_instructions,
      data: post.data,
      channel: Map.take(post.channel, @channel_fields),
      related: related_data(post),
      facts: post.facts,
      recent: recent
    }
  end

  defp related_data(%Post{parent: %Post{data: data}}), do: data
  defp related_data(_), do: nil

  def to_json_map(%__MODULE__{} = w) do
    w
    |> Map.from_struct()
    |> Map.update!(:scheduled_at, &DateTime.to_iso8601/1)
  end

  def from_json_map(%{} = m) do
    {:ok, at, _} = DateTime.from_iso8601(m["scheduled_at"])
    ch = m["channel"]

    %__MODULE__{
      kind: m["kind"],
      post_id: m["post_id"],
      rev: m["rev"],
      post_type: m["post_type"],
      scheduled_at: at,
      admin_note: m["admin_note"],
      extra_instructions: m["extra_instructions"],
      data: m["data"],
      channel: Map.new(@channel_fields, &{&1, ch[Atom.to_string(&1)]}),
      related: m["related"],
      facts: m["facts"],
      recent: m["recent"] || []
    }
  end
end
