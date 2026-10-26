defmodule Mix.Tasks.Agent.Try do
  @shortdoc "Runs the content agent + renderer for one channel without touching posts"
  @moduledoc """
  Writes and renders one post for a channel, prints the data and caption, and
  leaves the slides in tmp. Nothing is saved to the database.

      mix agent.try @_motivation2live__ quote
      mix agent.try @mid.innings fixture 2026-10-28T12:00
      mix agent.try @bollyvibe movie --note "pick a November release"
  """
  use Mix.Task
  alias Socialmedia.{Agent, Channels}
  alias Socialmedia.Content.{Renderer, Work}

  @impl true
  def run(argv) do
    {opts, args} = OptionParser.parse!(argv, strict: [note: :string])
    Mix.Task.run("app.start")

    [handle, type | rest] = args
    channel = Channels.get_channel_by_handle(handle) || Mix.raise("no channel #{handle}")

    at =
      case rest do
        [iso] ->
          # Accept 2026-10-28T12:00 as well as full seconds
          if(String.length(iso) == 16, do: iso <> ":00", else: iso)
          |> NaiveDateTime.from_iso8601!()
          |> DateTime.from_naive!(channel.timezone)
          |> DateTime.shift_zone!("Etc/UTC")

        [] ->
          DateTime.utc_now() |> DateTime.add(86_400) |> DateTime.truncate(:second)
      end

    work = %Work{
      kind: "generate",
      post_id: 0,
      post_type: type,
      scheduled_at: at,
      admin_note: opts[:note],
      channel: Map.take(channel, [:handle, :skill, :template_dir, :timezone, :base_data]),
      recent: Socialmedia.Posts.recent_data(channel, 20)
    }

    Mix.shell().info("Prompt:\n" <> Agent.build_prompt(work))
    Mix.shell().info("Running claude… (can take a few minutes)")

    case Agent.generate(work) do
      {:ok, gen} ->
        Mix.shell().info(
          "Notes: #{gen.notes}\nCost: #{inspect(gen.cost_usd)}\nData:\n" <>
            Jason.encode!(gen.data, pretty: true)
        )

        out = Path.join(System.tmp_dir!(), "agent-try-#{System.os_time(:second)}")

        case Renderer.render(work.channel, gen.data, out) do
          {:ok, r} ->
            Mix.shell().info("\nCaption:\n#{r.caption}\n\nSlides:\n" <> Enum.join(r.slides, "\n"))

          {:error, e} ->
            Mix.raise("render failed: #{e}")
        end

      {:skip, notes, retry} ->
        Mix.shell().info("Agent skipped (retry in #{inspect(retry)} min): #{notes}")

      {:error, e} ->
        Mix.raise("agent failed: #{e}")
    end
  end
end
