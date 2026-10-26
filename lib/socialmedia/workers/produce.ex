defmodule Socialmedia.Workers.Produce do
  @moduledoc """
  Content node job: run the agent (kind "generate") and/or the renderer, then
  deliver slides + manifest to S3 for prod to import. Args are a `Work` map.
  """
  use Oban.Worker,
    queue: :claude,
    max_attempts: 2,
    unique: [keys: [:post_id, :rev, :kind], period: :infinity, states: :all]

  require Logger
  alias Socialmedia.{Agent, Content}
  alias Socialmedia.Content.{Renderer, Work}

  @impl Oban.Worker
  def timeout(_job), do: Application.get_env(:socialmedia, :claude_timeout_ms) + :timer.minutes(5)

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, attempt: attempt, max_attempts: max}) do
    work = Work.from_json_map(args)
    out = Path.join([System.tmp_dir!(), "socialmedia-render", "#{work.post_id}-#{work.rev}"])

    try do
      case produce(work, out) do
        {:ok, result} ->
          Content.deliver(work, result)

        {:skip, notes, retry_after} ->
          Content.deliver_failure(work, notes, true, retry_after)

        {:error, reason} when attempt < max ->
          Logger.warning(
            "post #{work.post_id} rev #{work.rev} attempt #{attempt} failed: #{reason}"
          )

          {:error, reason}

        {:error, reason} ->
          Content.deliver_failure(work, to_string(reason), false)
      end
    after
      File.rm_rf(out)
    end
  end

  defp produce(%Work{kind: "generate"} = work, out) do
    with {:ok, gen} <- Agent.generate(work),
         {:ok, rendered} <- Renderer.render(work.channel, gen.data, out) do
      {:ok,
       %{
         data: gen.data,
         caption: rendered.caption,
         sources: gen.sources,
         notes: gen.notes,
         slides: rendered.slides
       }}
    end
  end

  defp produce(%Work{kind: "render", data: data} = work, out) when is_map(data) do
    with {:ok, rendered} <- Renderer.render(work.channel, data, out) do
      {:ok, %{data: data, caption: rendered.caption, slides: rendered.slides}}
    end
  end

  defp produce(%Work{}, _out), do: {:error, "nothing to render"}
end
