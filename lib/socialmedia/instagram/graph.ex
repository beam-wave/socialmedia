defmodule Socialmedia.Instagram.Graph do
  @moduledoc """
  Minimal Instagram Graph API client (Instagram API with Instagram Login).
  https://developers.facebook.com/docs/instagram-platform/content-publishing
  """

  def new(token) do
    Req.new(
      base_url: Application.fetch_env!(:socialmedia, :graph_api_base),
      params: [access_token: token],
      retry: :transient,
      receive_timeout: 60_000
    )
    |> Req.merge(Application.get_env(:socialmedia, __MODULE__, []))
  end

  @doc "Returns %{\"user_id\" => ..., \"username\" => ...} for the token's account."
  def me(token), do: get(new(token), "/me", fields: "user_id,username")

  def image_container(token, ig_user_id, image_url, opts \\ []) do
    params =
      [image_url: image_url] ++
        if(opts[:carousel_item], do: [is_carousel_item: true], else: []) ++
        if(opts[:caption], do: [caption: opts[:caption]], else: [])

    post(new(token), "/#{ig_user_id}/media", params) |> id()
  end

  def carousel_container(token, ig_user_id, children, caption) do
    post(new(token), "/#{ig_user_id}/media",
      media_type: "CAROUSEL",
      children: Enum.join(children, ","),
      caption: caption
    )
    |> id()
  end

  def container_status(token, container_id) do
    case get(new(token), "/#{container_id}", fields: "status_code,status") do
      {:ok, %{"status_code" => code} = body} -> {:ok, code, body["status"]}
      {:ok, body} -> {:error, {:unexpected, body}}
      error -> error
    end
  end

  def publish(token, ig_user_id, creation_id),
    do: post(new(token), "/#{ig_user_id}/media_publish", creation_id: creation_id) |> id()

  def permalink(token, media_id) do
    case get(new(token), "/#{media_id}", fields: "permalink") do
      {:ok, %{"permalink" => link}} -> {:ok, link}
      {:ok, _} -> {:ok, nil}
      error -> error
    end
  end

  @doc "Remaining posts in the rolling 24h window."
  def publishing_quota(token, ig_user_id) do
    case get(new(token), "/#{ig_user_id}/content_publishing_limit", fields: "quota_usage,config") do
      {:ok, %{"data" => [%{"quota_usage" => used} = row | _]}} ->
        {:ok, (get_in(row, ["config", "quota_total"]) || 100) - used}

      {:ok, _} ->
        {:ok, :unknown}

      error ->
        error
    end
  end

  @doc "Extends a long-lived token by another 60 days."
  def refresh_token(token) do
    req = new(token) |> Req.merge(base_url: "https://graph.instagram.com")

    case get(req, "/refresh_access_token", grant_type: "ig_refresh_token") do
      {:ok, %{"access_token" => t, "expires_in" => s}} -> {:ok, t, s}
      {:ok, body} -> {:error, {:unexpected, body}}
      error -> error
    end
  end

  defp get(req, url, params), do: req |> Req.get(url: url, params: params) |> handle()
  defp post(req, url, params), do: req |> Req.post(url: url, form: params) |> handle()

  defp handle({:ok, %{status: 200, body: body}}), do: {:ok, body}

  defp handle({:ok, %{status: s, body: %{"error" => %{"message" => m} = e}}}),
    do: {:error, "Instagram API #{s}: #{m} (code #{e["code"]})"}

  defp handle({:ok, %{status: s, body: b}}),
    do: {:error, "Instagram API #{s}: #{inspect(b, limit: 5)}"}

  defp handle({:error, e}), do: {:error, "Instagram request failed: #{Exception.message(e)}"}

  defp id({:ok, %{"id" => id}}), do: {:ok, id}
  defp id({:ok, body}), do: {:error, {:no_id, body}}
  defp id(error), do: error
end
