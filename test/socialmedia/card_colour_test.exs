defmodule Socialmedia.CardColourTest do
  use ExUnit.Case, async: true
  alias Socialmedia.Agent
  alias Socialmedia.Content.Work

  @colours ~w(butter mint lilac sky coral)

  defp work(recent),
    do: %Work{
      kind: "generate",
      post_id: 1,
      post_type: "quote",
      scheduled_at: ~U[2026-11-02 15:30:00Z],
      series_number: 7,
      channel: %{
        handle: "@puree_heartz",
        skill: "puree-heartz",
        timezone: "Asia/Kolkata",
        base_data: %{}
      },
      recent: recent
    }

  test "each post gets one of the five colours, never the last post's" do
    last = [%{"quotes" => [%{"theme" => "mint"}]}]

    for _ <- 1..50 do
      c = Agent.pick_colour(%{skill: "puree-heartz", base_data: %{}}, work(last))
      assert c in @colours and c != "mint"
    end
  end

  test "the colour lands on the quote, whatever the agent sent" do
    data = Agent.assemble(work([]), %{"quotes" => [%{"quote" => "q", "theme" => "blush"}]})
    q = hd(data["quotes"])
    assert q["theme"] in @colours and q["number"] == "07"
  end

  test "a channel can set its own list" do
    assert Agent.pick_colour(
             %{skill: "puree-heartz", base_data: %{"themes" => ["sky"]}},
             work([])
           ) == "sky"
  end

  test "motivation posts get one of its six palettes, never the last one" do
    ch = %{handle: "@m", skill: "motivation2live", timezone: "Asia/Kolkata", base_data: %{}}
    w = %{work([%{"quotes" => [%{"theme" => "volt"}]}]) | channel: ch}

    for _ <- 1..50 do
      c = Agent.pick_colour(ch, w)
      assert c in ~w(ivory midnight forest volt cobalt sand) and c != "volt"
    end

    data = Agent.assemble(w, %{"quotes" => [%{"quote" => "q"}]})
    assert hd(data["quotes"])["theme"] in ~w(ivory midnight forest cobalt sand)
  end
end
