defmodule Socialmedia.Agent do
  @moduledoc """
  One content agent for every channel: the local Claude CLI running in `agent/`,
  where each channel has a skill (`agent/.claude/skills/<skill>`) and an output
  schema (`agent/schemas/<skill>.json`).
  """
  alias Socialmedia.Paths
  alias Socialmedia.Content.Work
  alias Socialmedia.Agent.ClaudeCli

  @doc """
  Generates template data for one post. Returns
  `{:ok, %{data: map, sources: list, notes: string}}`, `{:skip, notes, retry_after_minutes | nil}`
  or `{:error, reason}`.
  """
  def generate(%Work{channel: channel} = work, opts \\ []) do
    with {:ok, schema_json, schema} <- load_schema(channel.skill),
         {:ok, out, envelope} <- ClaudeCli.run(build_prompt(work), schema_json, opts),
         :ok <- validate(schema, out) do
      case out do
        %{"skip" => true} ->
          {:skip, out["notes"] || "agent skipped without a note", out["retry_after_minutes"]}

        %{"post" => post_out} when is_map(post_out) ->
          {:ok,
           %{
             data: assemble(work, post_out),
             sources: out["sources"] || [],
             notes: out["notes"],
             cost_usd: envelope["total_cost_usd"]
           }}

        _ ->
          {:error, "agent returned no post"}
      end
    end
  end

  def load_schema(skill) do
    path = Paths.schema_path(skill)

    with {:ok, json} <- File.read(path),
         {:ok, map} <- Jason.decode(json) do
      {:ok, json, ExJsonSchema.Schema.resolve(map)}
    else
      _ -> {:error, "missing or invalid schema #{path}"}
    end
  end

  def validate(schema, out) do
    case ExJsonSchema.Validator.validate(schema, out) do
      :ok ->
        :ok

      {:error, errors} ->
        msg = Enum.map_join(errors, "; ", fn {m, path} -> "#{path}: #{m}" end)
        {:error, "agent output failed schema: #{msg}"}
    end
  end

  ## Prompt

  def build_prompt(%Work{channel: channel} = work) do
    local = local_time(work)
    recent = Enum.map(work.recent, &summarize(channel.skill, &1))

    """
    Use the `#{channel.skill}` skill to write ONE Instagram post for #{channel.handle}.

    Post type: #{work.post_type}
    Goes live: #{Calendar.strftime(local, "%A %d %B %Y, %H:%M")} (#{channel.timezone})
    Today is: #{Date.utc_today() |> Date.to_iso8601()}
    #{series_line(channel, work)}
    #{line("Admin note for this post (highest priority)", work.admin_note)}
    #{fixtures_line(work)}
    #{related(work)}
    #{facts(work)}
    Recent posts on this channel (newest first). Don't repeat their topic, quote, startup, movie, match or hook:
    #{if recent == [], do: "- none yet", else: Enum.map_join(recent, "\n", &"- #{&1}")}

    Research facts with WebSearch/WebFetch where the skill says so, then return only the structured output.
    """
    |> String.replace(~r/\n{3,}/, "\n\n")
  end

  defp fixtures_line(%Work{post_type: "fixture"}),
    do:
      "Return every relevant match that starts on this day (up to 6, most relevant first), one item each in `posts`. Each becomes its own post."

  defp fixtures_line(_), do: ""

  defp related(%Work{related: data}) when is_map(data) do
    "Linked fixture post (score these exact questions in `answers`):\n" <> Jason.encode!(data)
  end

  defp related(_), do: ""

  defp facts(%Work{facts: f}) when is_map(f) and map_size(f) > 0 do
    "Match facts entered by the admin. They are verified: use them as the source of truth and don't search for the result:\n" <>
      Jason.encode!(f, pretty: true)
  end

  defp facts(_), do: ""

  defp line(_label, v) when v in [nil, ""], do: ""
  defp line(label, v), do: "#{label}: #{v}"

  defp series_line(%{skill: "motivation2live"} = c, work),
    do: "Streak: this is Day #{series_number(work)} of #{c.base_data["total_days"] || 365}."

  defp series_line(%{skill: "puree-heartz"}, work),
    do: "This is quote number #{series_number(work)}."

  defp series_line(_, _), do: ""

  @doc "The post's running number (Day N, quote N), set when it was created."
  def series_number(%Work{series_number: n}) when is_integer(n), do: n
  def series_number(%Work{}), do: 1

  defp summarize("spotlight-startups", d),
    do:
      "#{d["domain"]}: #{d["startups"] |> List.wrap() |> Enum.map_join(", ", & &1["name"])} | hook: #{hook_q(d)}"

  defp summarize("mid-innings", d) do
    p = first(d, "posts")
    "#{p["type"]} #{p["team1"]} v #{p["team2"]} #{p["match"]} #{p["date"]} | hook: #{hook_q(p)}"
  end

  defp summarize("bollyvibe", d) do
    m = first(d, "movies")
    "#{m["title"]} (#{m["release_date"]}) | hook: #{hook_q(m)}"
  end

  defp summarize(_quotes, d) do
    q = first(d, "quotes")
    "\"#{q["quote"]}\" | theme: #{q["theme"]} | hook: #{hook_q(q)}"
  end

  defp first(d, key), do: d[key] |> List.wrap() |> List.first() || %{}

  defp hook_q(%{"hook" => %{"q" => q}}), do: q
  defp hook_q(_), do: "-"

  ## Assembling template data

  @doc """
  Builds the full template data for one post: the channel's base_data with the
  agent's fields on top, plus app-owned fields (dates, streak numbers).
  """
  def assemble(%Work{channel: channel} = work, post_out) do
    local = local_time(work)

    channel.base_data
    |> Map.drop(["series_start"])
    |> Map.put("handle", channel.handle)
    |> Map.merge(post_out)
    |> put_app_fields(channel, work, local)
  end

  defp put_app_fields(data, %{skill: "motivation2live"}, work, local) do
    update_first(data, "quotes", fn q ->
      Map.merge(q, %{"day" => series_number(work), "date" => short_date(local)})
    end)
  end

  defp put_app_fields(data, %{skill: "puree-heartz"}, work, local) do
    update_first(data, "quotes", fn q ->
      n = series_number(work) |> Integer.to_string() |> String.pad_leading(2, "0")
      Map.merge(q, %{"number" => n, "date" => short_date(local)})
    end)
  end

  defp put_app_fields(data, %{skill: "bollyvibe"}, _work, local) do
    Map.put(data, "today", local |> DateTime.to_date() |> Date.to_iso8601())
  end

  defp put_app_fields(data, _, _, _), do: data

  defp update_first(data, key, fun) do
    case data[key] do
      [first | rest] -> Map.put(data, key, [fun.(first) | rest])
      _ -> data
    end
  end

  defp short_date(local), do: Calendar.strftime(local, "%a · %d %b") |> String.replace(" 0", " ")

  def local_time(%Work{scheduled_at: at, channel: %{timezone: tz}}),
    do: DateTime.shift_zone!(at, tz)
end
