defmodule Socialmedia.Paths do
  @moduledoc "Locations of the non-Elixir parts of the repo (agent, templates, renderer)."

  def root, do: Application.get_env(:socialmedia, :project_root, File.cwd!())
  def agent_dir, do: Path.join(root(), "agent")
  def channels_dir, do: Path.join(root(), "channels")
  def renderer_script, do: Path.join([root(), "renderer", "render.js"])
  def schema_path(skill), do: Path.join([agent_dir(), "schemas", "#{skill}.json"])
end
