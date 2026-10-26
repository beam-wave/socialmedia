defmodule Socialmedia.Storage.S3 do
  @moduledoc "S3 adapter using Req's built-in SigV4 signing. Bucket stays private."
  @behaviour Socialmedia.Storage

  @impl true
  def put(key, body, content_type) do
    case Req.put(req(), url: path(key), body: body, headers: [content_type: content_type]) do
      {:ok, %{status: s}} when s in 200..299 -> :ok
      other -> {:error, describe(other)}
    end
  end

  @impl true
  def get(key) do
    case Req.get(req(), url: path(key), decode_body: false) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: 404}} -> {:error, :not_found}
      other -> {:error, describe(other)}
    end
  end

  @impl true
  def delete(key) do
    case Req.delete(req(), url: path(key)) do
      {:ok, %{status: s}} when s in 200..299 -> :ok
      other -> {:error, describe(other)}
    end
  end

  @impl true
  def list(prefix), do: list_page(prefix, nil, [])

  defp list_page(prefix, token, acc) do
    params =
      [{"list-type", "2"}, {"prefix", prefix}] ++
        if(token, do: [{"continuation-token", token}], else: [])

    case Req.get(req(), url: "/", params: params, decode_body: false) do
      {:ok, %{status: 200, body: xml}} ->
        keys =
          Regex.scan(~r{<Key>(.*?)</Key>}, xml, capture: :all_but_first)
          |> List.flatten()
          |> Enum.map(&unescape/1)

        acc = acc ++ keys

        case Regex.run(~r{<NextContinuationToken>(.*?)</NextContinuationToken>}, xml) do
          [_, next] -> list_page(prefix, unescape(next), acc)
          _ -> {:ok, acc}
        end

      other ->
        {:error, describe(other)}
    end
  end

  @impl true
  def url(key, expires_in) do
    c = conf()

    Req.Utils.aws_sigv4_url(
      access_key_id: c.access_key_id,
      secret_access_key: c.secret_access_key,
      region: c.region,
      service: :s3,
      method: :get,
      datetime: DateTime.utc_now(),
      expires: expires_in,
      url: base_url(c) <> path(key)
    )
    |> to_string()
  end

  defp req do
    c = conf()

    Req.new(
      base_url: base_url(c),
      aws_sigv4: [
        access_key_id: c.access_key_id,
        secret_access_key: c.secret_access_key,
        region: c.region,
        service: :s3
      ],
      retry: :transient,
      receive_timeout: 60_000
    )
  end

  # Virtual-hosted style URL, e.g. https://socialmedia-dravya.s3.ap-south-1.amazonaws.com
  defp base_url(c), do: c.endpoint || "https://#{c.bucket}.s3.#{c.region}.amazonaws.com"

  defp path(key), do: "/" <> (key |> String.split("/") |> Enum.map_join("/", &encode_segment/1))

  defp encode_segment(seg), do: URI.encode(seg, &URI.char_unreserved?/1)

  defp conf do
    c = Application.fetch_env!(:socialmedia, __MODULE__)

    %{
      bucket: c[:bucket] || raise("S3_BUCKET is not set"),
      region: c[:region] || "ap-south-1",
      access_key_id: c[:access_key_id] || raise("AWS_ACCESS_KEY_ID is not set"),
      secret_access_key: c[:secret_access_key] || raise("AWS_SECRET_ACCESS_KEY is not set"),
      endpoint: c[:endpoint]
    }
  end

  defp unescape(s),
    do:
      s
      |> String.replace("&amp;", "&")
      |> String.replace("&lt;", "<")
      |> String.replace("&gt;", ">")
      |> String.replace("&quot;", "\"")
      |> String.replace("&apos;", "'")

  defp describe({:ok, %{status: s, body: b}}),
    do: "S3 HTTP #{s}: #{b |> to_string() |> String.slice(0, 300)}"

  defp describe({:error, e}), do: "S3 request failed: #{Exception.message(e)}"
end
