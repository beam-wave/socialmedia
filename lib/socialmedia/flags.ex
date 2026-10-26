defmodule Socialmedia.Flags do
  @moduledoc """
  Node roles, set from env in config/runtime.exs:

  * `CONTENT=true`  - this node runs Claude + the renderer (your Mac). False on prod.
  * `PUBLISH=true`  - this node may post to Instagram (prod only). When false,
    approved posts are marked published as a dry run and nothing leaves the box.
  * `PRIMARY=true` - this node owns the schedule: planner, expirer, S3 sync
    import, admin approvals. True on prod; false on a Mac that only makes content.

  The two talk only through S3 (see `Socialmedia.Content`).
  """
  def content?, do: Application.get_env(:socialmedia, :content, false)
  def publish?, do: Application.get_env(:socialmedia, :publish, false)
  def primary?, do: Application.get_env(:socialmedia, :primary, true)
end
