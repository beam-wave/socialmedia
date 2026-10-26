# Seeds the five channels (timezone IST).
# Safe to re-run: existing channels (by handle) are left alone.
#
#     mix run priv/repo/seeds.exs

alias Socialmedia.Channels

channels = [
  %{
    name: "Spotlight Startups",
    handle: "@spotlight.startups",
    skill: "spotlight-startups",
    template_dir: "spotlight.startups",
    base_data: %{"theme" => "cobalt"}
  },
  %{
    name: "Puree Heartz",
    handle: "@puree_heartz",
    skill: "puree-heartz",
    template_dir: "puree_heartz",
    base_data: %{
      "theme" => "blush",
      "format" => "post",
      "lang" => "both",
      "signature" => "puree_heartz",
      "tags" =>
        "#puree_heartz #couplequotes #lovequotes #heartquotes #hindiquotes #shayari #dilsedil #relationshipgoals",
      "series_start" => %{"n" => 1}
    }
  },
  %{
    name: "Motivation 2 Live",
    handle: "@_motivation2live__",
    skill: "motivation2live",
    template_dir: "_motivation2live__",
    base_data: %{
      "theme" => "concrete",
      "format" => "post",
      "lang" => "both",
      "total_days" => 365,
      "tags" =>
        "#motivation #discipline #dailymotivation #hindimotivation #success #mindset #motivation2live",
      "series_start" => %{"n" => 1}
    }
  },
  %{
    name: "Mid Innings",
    handle: "@mid.innings",
    skill: "mid-innings",
    template_dir: "mid.innings",
    base_data: %{"theme" => "floodlight", "format" => "post"}
  },
  %{
    name: "Bollyvibe",
    handle: "@bollyvibe",
    skill: "bollyvibe",
    template_dir: "bollyvibe",
    base_data: %{"theme" => "marquee", "format" => "post"}
  }
]

for attrs <- channels do
  case Channels.get_channel_by_handle(attrs.handle) do
    nil ->
      {:ok, ch} =
        attrs
        |> Map.put(:timezone, "Asia/Kolkata")
        |> Channels.create_channel()

      IO.puts("created #{ch.handle}")

    ch ->
      IO.puts("exists #{ch.handle}")
  end
end
