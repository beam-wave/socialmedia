# Seeds the five channels and a starting set of slots (times in IST).
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
    base_data: %{"theme" => "cobalt"},
    slots: [
      %{post_type: "top5", weekdays: [1], time_of_day: ~T[11:00:00], lead_hours: 48}
    ]
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
      "series_start" => %{"date" => "2026-10-26", "n" => 1}
    },
    slots: [
      %{
        post_type: "quote",
        weekdays: Enum.to_list(1..7),
        time_of_day: ~T[21:00:00],
        lead_hours: 36
      }
    ]
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
      "series_start" => %{"date" => "2026-10-26", "n" => 42}
    },
    slots: [
      %{
        post_type: "quote",
        weekdays: Enum.to_list(1..7),
        time_of_day: ~T[06:00:00],
        lead_hours: 36
      }
    ]
  },
  %{
    name: "Mid Innings",
    handle: "@mid.innings",
    skill: "mid-innings",
    template_dir: "mid.innings",
    base_data: %{"theme" => "floodlight", "format" => "post"},
    slots: [
      %{
        post_type: "fixture",
        weekdays: Enum.to_list(1..7),
        time_of_day: ~T[12:00:00],
        lead_hours: 10,
        extra_instructions: "Skip if there is no India, ICC or IPL/WPL match today."
      },
      %{
        post_type: "result",
        weekdays: Enum.to_list(1..7),
        time_of_day: ~T[23:45:00],
        lead_hours: 1,
        extra_instructions: "Result of today's featured match. Skip if it hasn't finished."
      }
    ]
  },
  %{
    name: "Bollyvibe",
    handle: "@bollyvibe",
    skill: "bollyvibe",
    template_dir: "bollyvibe",
    base_data: %{"theme" => "marquee", "format" => "post"},
    slots: [
      %{post_type: "movie", weekdays: [2, 5], time_of_day: ~T[18:00:00], lead_hours: 48}
    ]
  }
]

for %{slots: slots} = attrs <- channels do
  case Channels.get_channel_by_handle(attrs.handle) do
    nil ->
      {:ok, ch} =
        attrs
        |> Map.delete(:slots)
        |> Map.put(:timezone, "Asia/Kolkata")
        |> Channels.create_channel()

      for s <- slots, do: {:ok, _} = Channels.create_schedule(Map.put(s, :channel_id, ch.id))
      IO.puts("created #{ch.handle} with #{length(slots)} slot(s)")

    ch ->
      IO.puts("exists #{ch.handle}")
  end
end
