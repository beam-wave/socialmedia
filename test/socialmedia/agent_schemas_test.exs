defmodule Socialmedia.AgentSchemasTest do
  use ExUnit.Case, async: true

  # A broken schema only shows up when Create runs Claude, so check them all here
  test "every channel skill has a schema that loads" do
    for skill <- ~w(motivation2live puree-heartz spotlight-startups mid-innings bollyvibe) do
      assert {:ok, _json, _schema} = Socialmedia.Agent.load_schema(skill), "schema for #{skill}"
    end
  end
end
