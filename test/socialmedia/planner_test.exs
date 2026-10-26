defmodule Socialmedia.PlannerTest do
  use Socialmedia.DataCase, async: true
  import Socialmedia.Fixtures
  alias Socialmedia.Workers.Planner
  alias Socialmedia.Posts.Post

  test "slots are expanded in the channel timezone within the window" do
    ch = channel()
    s = schedule(ch, %{weekdays: [1, 3], time_of_day: ~T[06:00:00]}) |> Repo.preload(:channel)
    # Sunday 25 Oct 2026, 20:00 IST
    now = ~U[2026-10-25 14:30:00Z]

    slots = Planner.slots(s, ch.timezone, now, 7)
    # Mon 26 06:00 IST = 00:30 UTC, Wed 28 06:00 IST
    assert slots == [~U[2026-10-26 00:30:00Z], ~U[2026-10-28 00:30:00Z]]
  end

  test "slots in the past today are skipped" do
    ch = channel()
    s = schedule(ch, %{time_of_day: ~T[06:00:00]}) |> Repo.preload(:channel)
    now = ~U[2026-10-26 02:00:00Z]
    refute ~U[2026-10-26 00:30:00Z] in Planner.slots(s, ch.timezone, now, 2)
  end

  test "planning is idempotent and sets generate_at from lead hours" do
    ch = channel()
    s = schedule(ch, %{lead_hours: 36}) |> Repo.preload(:channel)

    Planner.plan_schedule(s)
    Planner.plan_schedule(s)

    posts = Repo.all(Post)
    assert length(posts) in 7..8
    assert posts |> Enum.map(& &1.scheduled_at) |> Enum.uniq() |> length() == length(posts)

    for p <- posts do
      assert DateTime.diff(p.scheduled_at, p.generate_at) == 36 * 3600
      assert p.status == "planned"
    end
  end

  test "replan drops untouched posts of an edited slot" do
    ch = channel()
    s = schedule(ch) |> Repo.preload(:channel)
    Planner.plan_schedule(s)
    [first | _] = Repo.all(from p in Post, order_by: p.scheduled_at)
    Repo.update!(Ecto.Changeset.change(first, status: "needs_review"))

    Planner.replan(s)

    assert [%{status: "needs_review"}] = Repo.all(Post)
  end
end
