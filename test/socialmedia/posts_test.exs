defmodule Socialmedia.PostsTest do
  use Socialmedia.DataCase, async: true
  use Oban.Testing, repo: Socialmedia.Repo
  import Socialmedia.Fixtures
  alias Socialmedia.{Posts, Content}
  alias Socialmedia.Workers.{Publish, Expirer}

  test "approve schedules a publish job at the slot" do
    p = insert_post(channel())
    assert {:ok, approved} = Posts.approve(p)
    assert approved.status == "approved"
    assert_enqueued(worker: Publish, args: %{post_id: p.id}, scheduled_at: p.scheduled_at)
  end

  test "approve is refused once the slot has passed" do
    p =
      insert_post(channel(), %{
        scheduled_at: DateTime.utc_now() |> DateTime.add(-60) |> DateTime.truncate(:second)
      })

    assert {:error, :slot_passed} = Posts.approve(p)
  end

  test "unapprove cancels the publish job" do
    {:ok, p} = insert_post(channel()) |> Posts.approve()
    assert {:ok, %{status: "needs_review"}} = Posts.unapprove(p)
    refute_enqueued(worker: Publish, args: %{post_id: p.id})
  end

  test "expirer rejects anything not approved by slot time and keeps approved posts" do
    ch = channel()
    past = DateTime.utc_now() |> DateTime.add(-60) |> DateTime.truncate(:second)
    review = insert_post(ch, %{scheduled_at: past})
    planned = insert_post(ch, %{scheduled_at: past, status: "planned", data: nil})
    approved = insert_post(ch, %{scheduled_at: past, status: "approved"})

    Expirer.expire(DateTime.utc_now())

    assert Posts.get_post!(review.id).status == "rejected"
    assert Posts.get_post!(review.id).reject_reason == "not_approved_in_time"
    assert Posts.get_post!(planned.id).status == "rejected"
    assert Posts.get_post!(approved.id).status == "approved"
  end

  test "editing data asks for a re-render, editing caption goes back to review" do
    {:ok, p} = insert_post(channel()) |> Posts.approve()

    assert {:ok, %{status: "needs_review", caption: "new"}} =
             Posts.update_content(p, %{caption: "new"})

    p = Posts.get_post!(p.id)

    assert {:ok, %{status: "render_requested"}} =
             Posts.update_content(p, %{data: %{"quotes" => [%{"quote" => "y"}]}})
  end

  test "regenerate bumps the revision and puts the post back in the plan" do
    p = insert_post(channel())
    assert {:ok, p} = Posts.regenerate(p, "warmer")
    assert p.status == "planned" and p.admin_note == "warmer" and p.gen_rev == 2

    assert [%{post_id: id, kind: "generate", rev: 2, admin_note: "warmer"}] =
             Content.pending_work()

    assert id == p.id
  end

  test "schedule saves caption and new time, then approves" do
    p = insert_post(channel())
    at = DateTime.utc_now() |> DateTime.add(7200) |> DateTime.truncate(:second)
    assert {:ok, p} = Posts.schedule(p, %{caption: "edited", scheduled_at: at})
    assert p.status == "approved" and p.caption == "edited" and p.scheduled_at == at
    assert_enqueued(worker: Publish, args: %{post_id: p.id}, scheduled_at: at)
  end

  test "reschedule moves an approved post's publish job" do
    {:ok, p} = insert_post(channel()) |> Posts.approve()
    at = DateTime.utc_now() |> DateTime.add(9000) |> DateTime.truncate(:second)
    assert {:ok, %{scheduled_at: ^at}} = Posts.reschedule(p, at)
    assert_enqueued(worker: Publish, args: %{post_id: p.id}, scheduled_at: at)
    assert {:error, :time_passed} = Posts.reschedule(p, DateTime.add(DateTime.utc_now(), -60))
  end
end
