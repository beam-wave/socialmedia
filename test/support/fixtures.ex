defmodule Socialmedia.Fixtures do
  @moduledoc false
  alias Socialmedia.{Channels, Repo}
  alias Socialmedia.Posts.Post

  def channel(attrs \\ %{}) do
    {:ok, ch} =
      %{
        name: "Motivation",
        handle: "@m#{System.unique_integer([:positive])}",
        skill: "motivation2live",
        template_dir: "_motivation2live__",
        timezone: "Asia/Kolkata",
        base_data: %{
          "theme" => "concrete",
          "series_start" => %{"n" => 42}
        }
      }
      |> Map.merge(attrs)
      |> Channels.create_channel()

    ch
  end

  def insert_post(channel, attrs \\ %{}) do
    %Post{}
    |> Post.changeset(
      Map.merge(
        %{
          channel_id: channel.id,
          post_type: "quote",
          status: "needs_review",
          scheduled_at: DateTime.utc_now() |> DateTime.add(3600) |> DateTime.truncate(:second),
          data: %{"quotes" => [%{"quote" => "x"}]},
          slide_paths: ["content/0/1/a.jpg"]
        },
        attrs
      )
    )
    |> Repo.insert!()
    |> Repo.preload(:channel)
  end
end
