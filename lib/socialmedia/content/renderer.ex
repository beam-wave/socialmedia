defmodule Socialmedia.Content.Renderer do
  @moduledoc """
  Renders one post's slides (JPEG, 1080x1350) and caption by driving the channel's
  `channels/<dir>/template.html` through `renderer/render.js` (Playwright).
  """
  require Logger
  alias Socialmedia.Paths

  @timeout :timer.minutes(3)

  @doc "Returns {:ok, %{slides: [abs_path], caption: string}} or {:error, reason}."
  def render(%{template_dir: dir}, data, out_dir) do
    File.rm_rf!(out_dir)
    File.mkdir_p!(out_dir)
    data = localize_poster(data, out_dir)
    input = Path.join(out_dir, "input.json")
    File.write!(input, Jason.encode!(data))

    node = Application.get_env(:socialmedia, :node_bin, "node")
    template = Path.join(Paths.channels_dir(), dir)
    cmd = ~s(exec "$0" "$1" "$2" "$3" < "$4")
    args = ["-c", cmd, node, Paths.renderer_script(), template, out_dir, input]

    task = Task.async(fn -> System.cmd("/bin/sh", args, stderr_to_stdout: false) end)

    case Task.yield(task, @timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {out, 0}} -> parse(out)
      {:ok, {out, code}} -> {:error, "renderer exited #{code}: #{String.slice(out, -1000, 1000)}"}
      nil -> {:error, "renderer timed out"}
    end
  after
    File.rm(Path.join(out_dir, "input.json"))
  end

  defp parse(out) do
    case Jason.decode(out) do
      {:ok, %{"slides" => [_ | _] = slides, "captions" => [%{"text" => caption} | _]}} ->
        {:ok, %{slides: slides, caption: caption}}

      _ ->
        {:error, "renderer gave unexpected output: #{String.slice(out, 0, 500)}"}
    end
  end

  # Bollyvibe posters: download the official poster next to the slides so the
  # template loads a local file (remote hosts often block hotlinking).
  defp localize_poster(%{"movies" => [%{"poster_url" => url} = m | rest]} = data, out_dir)
       when is_binary(url) and url != "" do
    case Req.get(url, headers: [user_agent: "Mozilla/5.0 socialmedia-bot"], retry: false) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        file = Path.join(out_dir, "poster" <> poster_ext(url))
        File.write!(file, body)
        %{data | "movies" => [Map.put(m, "poster", "file://" <> file) | rest]}

      other ->
        Logger.warning("poster download failed for #{url}: #{inspect(other, limit: 3)}")
        %{data | "movies" => [Map.put(m, "poster", url) | rest]}
    end
  end

  defp localize_poster(data, _), do: data

  defp poster_ext(url) do
    case url
         |> URI.parse()
         |> Map.get(:path, "")
         |> to_string()
         |> Path.extname()
         |> String.downcase() do
      ext when ext in ~w(.jpg .jpeg .png .webp) -> ext
      _ -> ".jpg"
    end
  end
end
