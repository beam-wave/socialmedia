defmodule Socialmedia.Workers.Planner do
  @moduledoc """
  Expands every active schedule into planned posts for the next `plan_days`
  days (in each channel's timezone). Idempotent: one post per (schedule, slot).
  Runs on the primary node only.
  """
  use Oban.Worker, queue: :planner, max_attempts: 3, unique: [period: 60]
  import Ecto.Query
  alias Socialmedia.{Channels, Posts, Repo}
  alias Socialmedia.Posts.Post
  alias Socialmedia.Channels.Schedule

  def enqueue, do: %{} |> new() |> Oban.insert()

  @impl Oban.Worker
  def perform(_job) do
    drop_orphaned_slots()
    now = DateTime.utc_now()
    days = Application.get_env(:socialmedia, :plan_days, 7)

    Channels.list_active_schedules()
    |> Enum.each(&plan_schedule(&1, now, days))
  end

  @doc "Planned posts for one schedule in the window [now, now + days)."
  def plan_schedule(%Schedule{channel: channel} = s, now \\ DateTime.utc_now(), days \\ 7) do
    for slot <- slots(s, channel.timezone, now, days) do
      Posts.ensure_planned(%{
        channel_id: channel.id,
        schedule_id: s.id,
        post_type: s.post_type,
        scheduled_at: slot,
        generate_at: DateTime.add(slot, -s.lead_hours * 3600)
      })
    end
  end

  @doc "UTC slot times for a schedule between now and now + days."
  def slots(%Schedule{weekdays: weekdays, time_of_day: time}, tz, now, days) do
    today = now |> DateTime.shift_zone!(tz) |> DateTime.to_date()
    horizon = DateTime.add(now, days * 86_400)

    for offset <- 0..days,
        date = Date.add(today, offset),
        Date.day_of_week(date) in weekdays,
        {:ok, local} <- [local_datetime(date, time, tz)],
        utc = DateTime.shift_zone!(local, "Etc/UTC") |> DateTime.truncate(:second),
        DateTime.compare(utc, now) == :gt,
        DateTime.compare(utc, horizon) == :lt,
        do: utc
  end

  defp local_datetime(date, time, tz) do
    case DateTime.new(date, Time.truncate(time, :second), tz) do
      {:ok, dt} -> {:ok, dt}
      {:ambiguous, first, _} -> {:ok, first}
      {:gap, _, after_gap} -> {:ok, after_gap}
      error -> error
    end
  end

  @doc """
  When a slot is edited or switched off, future posts nobody has worked on yet
  (still `planned`) are removed so the planner can re-create the right ones.
  """
  def drop_orphaned_slots do
    now = DateTime.utc_now()

    orphans =
      from p in Post,
        left_join: s in assoc(p, :schedule),
        join: c in assoc(p, :channel),
        where: p.status == "planned" and p.scheduled_at > ^now,
        where: is_nil(s.id) or not s.active or not c.active,
        select: p.id

    Repo.delete_all(from p in Post, where: p.id in subquery(orphans))
  end

  @doc "Called after a schedule edit: drop its untouched future posts, then plan again."
  def replan(%Schedule{} = s) do
    now = DateTime.utc_now()

    Repo.delete_all(
      from p in Post,
        where: p.schedule_id == ^s.id and p.status == "planned" and p.scheduled_at > ^now
    )

    enqueue()
  end
end
