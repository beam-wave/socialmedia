defmodule Socialmedia.Content.Work do
  @moduledoc """
  Everything the agent and the renderer need to make one post: generate (agent +
  render) or render only (the admin edited the slide data).
  """
  alias Socialmedia.Posts.Post

  @enforce_keys [:kind, :post_id, :post_type, :scheduled_at, :channel]
  defstruct [
    :kind,
    :post_id,
    :post_type,
    :scheduled_at,
    :admin_note,
    :data,
    :channel,
    # Data of the linked fixture post, for result posts
    :related,
    # Facts entered by the admin (match result)
    :facts,
    # Day N / quote N for series channels
    :series_number,
    recent: []
  ]

  @channel_fields ~w(handle skill template_dir timezone base_data)a

  @doc "Builds work from a post preloaded with :channel (and :parent for results)."
  def from_post(%Post{} = post, kind, recent) when kind in ["generate", "render"] do
    %__MODULE__{
      kind: kind,
      post_id: post.id,
      post_type: post.post_type,
      scheduled_at: post.scheduled_at,
      admin_note: post.admin_note,
      data: post.data,
      channel: Map.take(post.channel, @channel_fields),
      related: related_data(post),
      facts: post.facts,
      series_number: post.series_number,
      recent: recent
    }
  end

  defp related_data(%Post{parent: %Post{data: data}}), do: data
  defp related_data(_), do: nil
end
