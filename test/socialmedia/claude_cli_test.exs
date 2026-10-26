defmodule Socialmedia.ClaudeCliTest do
  use ExUnit.Case, async: true
  alias Socialmedia.Agent.ClaudeCli

  @tag :tmp_dir
  test "parses structured output from the CLI envelope", %{tmp_dir: dir} do
    bin =
      fake_cli(
        dir,
        ~s({"type":"result","is_error":false,"result":"","structured_output":{"skip":false,"post":{"a":1}}})
      )

    assert {:ok, %{"post" => %{"a" => 1}}, _} =
             ClaudeCli.run("hi", "{}", bin: bin, cwd: dir, timeout: 5_000)
  end

  @tag :tmp_dir
  test "falls back to JSON inside the result text", %{tmp_dir: dir} do
    env =
      Jason.encode!(%{type: "result", is_error: false, result: "```json\n{\"skip\": true}\n```"})

    bin = fake_cli(dir, env)

    assert {:ok, %{"skip" => true}, _} =
             ClaudeCli.run("hi", "{}", bin: bin, cwd: dir, timeout: 5_000)
  end

  @tag :tmp_dir
  test "times out and reports", %{tmp_dir: dir} do
    path = Path.join(dir, "slow")
    File.write!(path, "#!/bin/sh\nsleep 5\n")
    File.chmod!(path, 0o755)
    assert {:error, msg} = ClaudeCli.run("hi", "{}", bin: path, cwd: dir, timeout: 200)
    assert msg =~ "timed out"
  end

  defp fake_cli(dir, output) do
    path = Path.join(dir, "claude")
    File.write!(path, "#!/bin/sh\ncat <<'EOF'\n#{output}\nEOF\n")
    File.chmod!(path, 0o755)
    path
  end
end
