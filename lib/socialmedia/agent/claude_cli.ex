defmodule Socialmedia.Agent.ClaudeCli do
  @moduledoc """
  Runs the local Claude Code CLI headless (`claude -p`) using the logged-in
  subscription. No API key is used; ANTHROPIC_API_KEY is removed from the env
  so the CLI never silently bills an API account.
  """
  require Logger

  @tools "WebSearch,WebFetch,Read,Glob,Grep,Skill"

  @doc """
  Runs one prompt with a JSON schema for structured output.
  Returns `{:ok, output_map, raw_envelope}` or `{:error, reason}`.
  """
  def run(prompt, schema_json, opts \\ []) do
    bin = Keyword.get(opts, :bin, Application.get_env(:socialmedia, :claude_bin, "claude"))
    timeout = Keyword.get(opts, :timeout, Application.get_env(:socialmedia, :claude_timeout_ms))
    cwd = Keyword.get(opts, :cwd, Socialmedia.Paths.agent_dir())

    args = [
      "-p",
      prompt,
      "--output-format",
      "json",
      "--json-schema",
      schema_json,
      "--allowedTools",
      @tools,
      "--permission-mode",
      "dontAsk",
      "--max-turns",
      "40"
    ]

    with {:ok, exe} <- find_executable(bin),
         {:ok, stdout} <- exec(exe, args, cwd, timeout),
         {:ok, envelope} <- decode_envelope(stdout) do
      extract(envelope)
    end
  end

  defp find_executable(bin) do
    case System.find_executable(bin) do
      nil -> {:error, "claude CLI not found (#{bin}). Install Claude Code and log in."}
      path -> {:ok, path}
    end
  end

  # stdin is redirected from /dev/null so the CLI never waits for piped input.
  defp exec(exe, args, cwd, timeout) do
    port =
      Port.open({:spawn_executable, "/bin/sh"}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        :hide,
        args: ["-c", ~s(exec "$0" "$@" < /dev/null), exe | args],
        cd: cwd,
        env: [{~c"ANTHROPIC_API_KEY", false}]
      ])

    collect(port, [], deadline(timeout))
  end

  defp deadline(timeout), do: System.monotonic_time(:millisecond) + timeout

  defp collect(port, acc, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, chunk}} ->
        collect(port, [acc, chunk], deadline)

      {^port, {:exit_status, 0}} ->
        {:ok, IO.iodata_to_binary(acc)}

      {^port, {:exit_status, code}} ->
        {:error, "claude exited with #{code}: #{tail(IO.iodata_to_binary(acc))}"}
    after
      remaining ->
        kill(port)
        {:error, "claude timed out after #{div(remaining + 1, 1000)}s"}
    end
  end

  defp kill(port) do
    case Port.info(port, :os_pid) do
      {:os_pid, pid} -> System.cmd("kill", ["-TERM", Integer.to_string(pid)])
      _ -> :ok
    end

    Port.close(port)
  catch
    _, _ -> :ok
  end

  # The CLI prints one JSON object; stderr noise can precede it, so take the last line that parses.
  defp decode_envelope(stdout) do
    stdout
    |> String.split("\n", trim: true)
    |> Enum.reverse()
    |> Enum.find_value(fn line ->
      case Jason.decode(line) do
        {:ok, %{"type" => "result"} = env} -> env
        _ -> nil
      end
    end)
    |> case do
      nil -> {:error, "unexpected claude output: #{tail(stdout)}"}
      env -> {:ok, env}
    end
  end

  defp extract(%{"is_error" => true} = env),
    do: {:error, "claude error (#{env["subtype"]}): #{tail(to_string(env["result"]))}"}

  defp extract(%{"structured_output" => out} = env) when is_map(out), do: {:ok, out, env}

  defp extract(%{"result" => text} = env) when is_binary(text) do
    case decode_json_text(text) do
      {:ok, out} -> {:ok, out, env}
      :error -> {:error, "claude returned no JSON: #{tail(text)}"}
    end
  end

  defp extract(env), do: {:error, "claude result missing output: #{tail(inspect(env))}"}

  defp decode_json_text(text) do
    text =
      case Regex.run(~r/```(?:json)?\s*(\{.*\})\s*```/s, text) do
        [_, inner] -> inner
        _ -> text
      end

    case Jason.decode(String.trim(text)) do
      {:ok, map} when is_map(map) -> {:ok, map}
      _ -> :error
    end
  end

  defp tail(s), do: s |> String.slice(-1500, 1500) |> String.trim()
end
