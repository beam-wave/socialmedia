defmodule Socialmedia.MadeForTest do
  use Socialmedia.DataCase, async: true
  import Socialmedia.Fixtures
  alias Socialmedia.Channels

  # 2026-11-20 07:00 IST
  @now ~U[2026-11-20 01:30:00Z]

  defp ist(date, time),
    do: DateTime.new!(date, time, "Asia/Kolkata") |> DateTime.shift_zone!("Etc/UTC")

  test "first post takes the next default time: today if it's still ahead" do
    ch = channel(%{default_post_time: ~T[08:00:00]})
    assert Channels.made_for(ch, nil, @now) == ist(~D[2026-11-20], ~T[08:00:00])
  end

  test "too close or passed: tomorrow" do
    ch = channel(%{default_post_time: ~T[07:15:00]})
    assert Channels.made_for(ch, nil, @now) == ist(~D[2026-11-21], ~T[07:15:00])
  end

  test "next posts go on the day after the latest one" do
    ch = channel(%{default_post_time: ~T[21:00:00]})
    insert_post(ch, %{scheduled_at: ist(~D[2026-11-23], ~T[21:00:00])})
    insert_post(ch, %{scheduled_at: ist(~D[2026-11-21], ~T[09:00:00])})
    assert Channels.made_for(ch, nil, @now) == ist(~D[2026-11-24], ~T[21:00:00])
  end

  test "failed and rejected posts don't hold a day; old posts don't pull it back" do
    ch = channel(%{default_post_time: ~T[18:00:00]})
    insert_post(ch, %{status: "failed", scheduled_at: ist(~D[2026-11-25], ~T[18:00:00])})
    insert_post(ch, %{status: "rejected", scheduled_at: ist(~D[2026-11-26], ~T[18:00:00])})
    insert_post(ch, %{status: "published", scheduled_at: ist(~D[2026-11-10], ~T[18:00:00])})
    assert Channels.made_for(ch, nil, @now) == ist(~D[2026-11-20], ~T[18:00:00])
  end

  test "a given day (match day) uses the channel time, noon when unset" do
    assert Channels.made_for(channel(), ~D[2026-11-28], @now) == ist(~D[2026-11-28], ~T[12:00:00])
  end
end
