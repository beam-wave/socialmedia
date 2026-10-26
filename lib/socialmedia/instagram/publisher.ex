defmodule Socialmedia.Instagram.Publisher do
  @moduledoc "Publishes a rendered post (1 image or a carousel of up to 10) to Instagram."
  alias Socialmedia.Instagram.Graph
  alias Socialmedia.Storage

  @poll_every 3_000
  @poll_max 40

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
         :ok <- Enum.reduce_while(ids, :ok, fn id, :ok -> {:cont, wait_ready(token, id, 0)} end) do
      Graph.carousel_container(token, user, ids, caption)
    end
  end

  defp wait_ready(_token, id, n) when n >= @poll_max,
    do: {:error, "container #{id} not ready in time"}

  defp wait_ready(token, id, n) do
    case Graph.container_status(token, id) do
      {:ok, "FINISHED", _} -> :ok
      {:ok, code, _} when code in ["ERROR", "EXPIRED"] -> {:error, "container #{id} #{code}"}
      {:ok, _in_progress, _} -> sleep_and_retry(token, id, n)
      error -> error
    end
  end

  defp sleep_and_retry(token, id, n) do
    Process.sleep(Application.get_env(:socialmedia, :graph_poll_ms, @poll_every))
    wait_ready(token, id, n + 1)
  end

  defp check_quota(token, user) do
    case Graph.publishing_quota(token, user) do
      {:ok, n} when is_integer(n) and n <= 0 -> {:error, "Instagram 24h publishing limit reached"}
      {:ok, _} -> :ok
      error -> error
    end
  end
end
