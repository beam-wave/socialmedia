defmodule Socialmedia.Workers.ProduceFailures do
  @moduledoc """
  Marks a post `failed` when its Produce job is discarded after a crash (an
  exception, a timeout, a lost node), so it doesn't stay on "Creating". Errors
  `Produce` returns itself already fail the post.
  """
  require Logger
  alias Socialmedia.Posts

  @produce inspect(Socialmedia.Workers.Produce)

  def attach do
    :telemetry.attach(__MODULE__, [:oban, :job, :exception], &__MODULE__.handle_event/4, nil)
  end

  def handle_event(_event, _measure, %{state: :discard, job: %{worker: @produce} = job} = meta, _) do
    with %{status: "creating"} = post <- Posts.get_post(job.args["post_id"]) do
      Posts.fail(post, "Making it failed: #{describe(meta)}")
    end
  rescue
    e -> Logger.warning("could not mark post failed: #{Exception.message(e)}")
  end

  def handle_event(_event, _measure, _meta, _config), do: :ok

  defp describe(%{reason: %{__exception__: true} = e}),
    do: Exception.message(e) |> String.slice(0, 600)

  defp describe(%{reason: reason}), do: inspect(reason, limit: 20, printable_limit: 600)
  defp describe(%{error: error}), do: describe(%{reason: error})
  defp describe(_), do: "the job crashed"
end
