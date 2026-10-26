defmodule Socialmedia.Workers.Produce do
  @moduledoc """
  Makes one post: runs the agent and the renderer (or only the renderer after
  the admin edited the slide data), then uploads it to S3 for a Pull.
  One job per click; the `claude` queue runs them one at a time. A fixture
  run returns every match that day: the first fills this post, and each of
  the others gets its own post and a render-only job.
  """
  use Oban.Worker,
    queue: :claude,
    max_attempts: 2,
    unique: [keys: [:post_id], period: :infinity, states: :incomplete]

  require Logger
  alias Socialmedia.{Agent, Content, Posts, Repo}
  alias Socialmedia.Content.{Matches, Renderer, Work}

  def enqueue(post, opts \\ []),
    do: %{post_id: post.id, render_only: opts[:render_only] || false} |> new() |> Oban.insert()

  @impl Oban.Worker
  def timeout(_job), do: Application.get_env(:socialmedia, :claude_timeout_ms) + :timer.minutes(5)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"post_id" => id} = args, attempt: attempt, max_attempts: max}) do
    case Posts.get_post(id) do
      %{status: "creating"} = post ->
        post = Repo.preload(post, :parent)
        kind = if args["render_only"] && post.data, do: "render", else: "generate"
        work = Work.from_post(post, kind, Posts.recent_data(post.channel, 20))
        out = Path.join([System.tmp_dir!(), "socialmedia-render", post.content_key])

        try do
          case produce(work, out) do
            {:ok, result} ->
              {:ok, uploaded} = Content.upload(post, result)
              # Added only after the first one is up, so a retry can't add them twice
              Content.add_fixtures(uploaded, result[:more] || [], post.scheduled_at, result)
              :ok

            {:skip, notes, _retry_after} ->
              Posts.fail(post, "Agent skipped: #{notes}")
              :ok

            {:error, reason} when attempt < max ->
              Logger.warning("post #{post.id} attempt #{attempt} failed: #{reason}")
              {:error, reason}

            {:error, reason} ->
              Posts.fail(post, reason)
              {:cancel, reason}
          end
        after
          File.rm_rf(out)
        end

      nil ->
        {:cancel, :post_deleted}

      post ->
        {:cancel, "post is #{post.status}, not creating"}
    end
  end

  defp produce(%Work{kind: "generate"} = work, out) do
    with {:ok, gen} <- Agent.generate(work),
         [data | more] <- split(work, gen.data),
         {:ok, rendered} <- Renderer.render(work.channel, data, out) do
      {:ok,
       %{
         data: data,
         more: more,
         caption: rendered.caption,
         sources: gen.sources,
         notes: gen.notes,
         slides: rendered.slides
       }}
    end
  end

  defp produce(%Work{kind: "render", data: data} = work, out) do
    with {:ok, rendered} <- Renderer.render(work.channel, data, out) do
      {:ok, %{data: data, caption: rendered.caption, slides: rendered.slides}}
    end
  end

  # A fixture run can return all of the day's matches
  defp split(%Work{post_type: "fixture"}, data), do: Matches.split_fixtures(data)
  defp split(_work, data), do: [data]
end
