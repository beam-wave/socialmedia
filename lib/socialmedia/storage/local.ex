defmodule Socialmedia.Storage.Local do
  @moduledoc "Folder-backed storage for tests and offline dev. Files are served at /local-storage."
  @behaviour Socialmedia.Storage

  def root,
    do:
      Application.get_env(:socialmedia, :local_storage_dir, Path.join(File.cwd!(), "tmp/storage"))

  @impl true
  def put(key, body, _ct) do
    path = Path.join(root(), key)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, body)
    :ok
  end

  @impl true
  def get(key) do
    case File.read(Path.join(root(), key)) do
      {:ok, b} -> {:ok, b}
      {:error, :enoent} -> {:error, :not_found}
      {:error, e} -> {:error, e}
    end
  end

  @impl true
  def delete(key) do
    File.rm(Path.join(root(), key))
    :ok
  end

  @impl true
  def list(prefix) do
    base = root()

    keys =
      Path.wildcard(Path.join(base, "**"))
      |> Enum.filter(&File.regular?/1)
      |> Enum.map(&Path.relative_to(&1, base))
      |> Enum.filter(&String.starts_with?(&1, prefix))
      |> Enum.sort()

    {:ok, keys}
  end

  @impl true
  def url(key, _expires), do: "/local-storage/" <> key
end
