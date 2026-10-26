defmodule Socialmedia.Storage do
  @moduledoc """
  Object storage for slides and the content-sync bus (S3 in dev and prod, a
  local folder in tests). Keys are relative; every key is placed under
  `S3_PREFIX` (e.g. "dev" or "prod") so environments never share objects.

  Bus layout under the prefix:

      plan.json                         prod → Mac: work that needs content
      inbox/<post_id>-<rev>.json        Mac → prod: finished (or failed) work
      content/<post_id>/<rev>/*.jpg     slides, uploaded untouched (JPEG q100)
  """

  @callback put(key :: String.t(), body :: iodata, content_type :: String.t()) ::
              :ok | {:error, term}
  @callback get(key :: String.t()) :: {:ok, binary} | {:error, :not_found | term}
  @callback list(prefix :: String.t()) :: {:ok, [String.t()]} | {:error, term}
  @callback delete(key :: String.t()) :: :ok | {:error, term}
  @callback url(key :: String.t(), expires_in :: pos_integer) :: String.t()

  defp impl, do: Application.get_env(:socialmedia, :storage, Socialmedia.Storage.S3)

  defp full(key), do: Path.join(prefix(), key) |> String.trim_leading("/")
  defp prefix, do: Application.get_env(:socialmedia, :storage_prefix) || ""

  defp strip(full_key) do
    case prefix() do
      "" -> full_key
      p -> String.replace_prefix(full_key, p <> "/", "")
    end
  end

  def put(key, body, content_type), do: impl().put(full(key), body, content_type)
  def put_file(key, path, content_type), do: put(key, File.read!(path), content_type)
  def put_json(key, term), do: put(key, Jason.encode!(term), "application/json")
  def delete(key), do: impl().delete(full(key))

  def get(key), do: impl().get(full(key))

  def get_json(key) do
    with {:ok, body} <- get(key), do: Jason.decode(body)
  end

  def exists?(key), do: match?({:ok, _}, get(key))

  @doc "Keys (relative to the prefix) under a sub-prefix."
  def list(sub) do
    with {:ok, keys} <- impl().list(full(sub)), do: {:ok, Enum.map(keys, &strip/1)}
  end

  @doc "Time-limited URL for a private object (admin previews, Instagram's image_url)."
  def url(key, expires_in \\ 3600), do: impl().url(full(key), expires_in)
end
