defmodule Socialmedia.Instagram.Publisher do
  @moduledoc """
  Publishes a rendered post (1 image or a carousel of up to 10) or its animated
  reel to Instagram. A reel gets a random trending track from the Audio API
  when the token allows it (EAA… tokens); otherwise it goes out silent.
  """
  alias Socialmedia.Instagram.Graph
  alias Socialmedia.Storage

  @poll_every 3_000
  @poll_max 40
  # Videos take longer to process than images
  @reel_poll_max 120

  @doc "Returns {:ok, %{ig_media_id, permalink}} or {:error, reason}."
  def publish(%{channel: ch, slide_paths: slides, caption: caption}) do
    token = ch.access_token
    # Presigned S3 links; Instagram downloads each image once while creating containers
    urls = Enum.map(slides, &Storage.url(&1, 3600))

    cond do
      is_nil(token) or is_nil(ch.ig_user_id) ->
        {:error, "channel has no Instagram token or user id"}

      slides == [] ->
        {:error, "post has no slides"}

      length(slides) > 10 ->
        {:error, "Instagram carousels take at most 10 slides"}

      true ->
        do_publish(token, ch.ig_user_id, urls, caption || "")
    end
  end

  @doc "Returns {:ok, %{reel_media_id, reel_permalink, reel_audio}} or {:error, reason}."
  def publish_reel(%{channel: ch, video_path: video, cover_path: cover, caption: caption}) do
    token = ch.access_token

    cond do
      is_nil(token) or is_nil(ch.ig_user_id) ->
        {:error, "channel has no Instagram token or user id"}

      is_nil(video) ->
        {:error, "post has no reel video"}

      true ->
        user = ch.ig_user_id
        video_url = Storage.url(video, 3600)
        cover_url = cover && Storage.url(cover, 3600)
        audio = pick_audio(token, user)

        with :ok <- check_quota(token, user),
             {:ok, container, audio} <-
               reel_container(token, user, video_url, caption || "", cover_url, audio),
             :ok <- wait_ready(token, container, 0, @reel_poll_max),
             {:ok, media_id} <- Graph.publish(token, user, container),
             {:ok, link} <- Graph.permalink(token, media_id) do
          {:ok, %{reel_media_id: media_id, reel_permalink: link, reel_audio: audio}}
        end
    end
  end

  # A random track from what's trending now; nil when the token can't use the Audio API
  defp pick_audio(token, user) do
    with true <- String.starts_with?(token, "EAA"),
         {:ok, [_ | _] = tracks} <- Graph.trending_audio(token, user) do
      t = Enum.random(tracks)

      %{
        "audio_id" => to_string(t["audio_id"] || t["id"]),
        "title" => t["title"],
        "artist" => t["display_artist"] || t["ig_username"]
      }
    else
      _ -> nil
    end
  end

  # If Instagram refuses the track, the reel still goes out, silent
  defp reel_container(token, user, video_url, caption, cover_url, nil) do
    with {:ok, id} <- Graph.reel_container(token, user, video_url, caption, cover_url: cover_url),
         do: {:ok, id, nil}
  end

  defp reel_container(token, user, video_url, caption, cover_url, audio) do
    case Graph.reel_container(token, user, video_url, caption,
           cover_url: cover_url,
           audio_id: audio["audio_id"]
         ) do
      {:ok, id} -> {:ok, id, audio}
      {:error, _} -> reel_container(token, user, video_url, caption, cover_url, nil)
    end
  end

  defp do_publish(token, user, urls, caption) do
    with :ok <- check_quota(token, user),
         {:ok, container} <- container(token, user, urls, caption),
         :ok <- wait_ready(token, container, 0),
         {:ok, media_id} <- Graph.publish(token, user, container),
         {:ok, link} <- Graph.permalink(token, media_id) do
      {:ok, %{ig_media_id: media_id, permalink: link}}
    end
  end

  defp container(token, user, [url], caption),
    do: Graph.image_container(token, user, url, caption: caption)

  defp container(token, user, urls, caption) do
    children =
      Enum.reduce_while(urls, {:ok, []}, fn url, {:ok, acc} ->
        case Graph.image_container(token, user, url, carousel_item: true) do
          {:ok, id} -> {:cont, {:ok, [id | acc]}}
          error -> {:halt, error}
        end
      end)

    with {:ok, ids} <- children,
         ids = Enum.reverse(ids),
         :ok <-
           Enum.reduce_while(ids, :ok, fn id, :ok ->
             case wait_ready(token, id, 0) do
               :ok -> {:cont, :ok}
               error -> {:halt, error}
             end
           end) do
      Graph.carousel_container(token, user, ids, caption)
    end
  end

  defp wait_ready(token, id, n, max \\ @poll_max)

  defp wait_ready(_token, id, n, max) when n >= max,
    do: {:error, "container #{id} not ready in time"}

  defp wait_ready(token, id, n, max) do
    case Graph.container_status(token, id) do
      {:ok, "FINISHED", _} ->
        :ok

      {:ok, code, status} when code in ["ERROR", "EXPIRED"] ->
        {:error, "container #{id} #{code}: #{status}"}

      {:ok, _in_progress, _} ->
        sleep_and_retry(token, id, n, max)

      error ->
        error
    end
  end

  defp sleep_and_retry(token, id, n, max) do
    Process.sleep(Application.get_env(:socialmedia, :graph_poll_ms, @poll_every))
    wait_ready(token, id, n + 1, max)
  end

  defp check_quota(token, user) do
    case Graph.publishing_quota(token, user) do
      {:ok, n} when is_integer(n) and n <= 0 -> {:error, "Instagram 24h publishing limit reached"}
      {:ok, _} -> :ok
      error -> error
    end
  end
end
