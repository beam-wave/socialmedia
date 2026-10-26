defmodule SocialmediaWeb.ChannelCreateTest do
  use SocialmediaWeb.ConnCase, async: false
  use Oban.Testing, repo: Socialmedia.Repo
  import Phoenix.LiveViewTest
  import Socialmedia.Fixtures
  alias Socialmedia.{Channels, Repo}
  alias Socialmedia.Posts.Post
  alias Socialmedia.Workers.Produce

  test "a quote is created without picking a time", %{conn: conn} do
    ch = channel()
    {:ok, view, _html} = live(conn, ~p"/channels/#{ch.id}")

    refute has_element?(view, "#create-form input[type=date]")
    view |> form("#create-form", create: %{post_type: "quote"}) |> render_submit()

    assert [%Post{status: "creating", post_type: "quote"} = post] = Repo.all(Post)
    assert post.scheduled_at == Channels.made_for(ch)
    assert_enqueued(worker: Produce, args: %{post_id: post.id})
  end

  test "a fixture is created for the chosen match day", %{conn: conn} do
    ch = channel(%{skill: "mid-innings", template_dir: "mid.innings", base_data: %{}})
    {:ok, view, _html} = live(conn, ~p"/channels/#{ch.id}")

    assert has_element?(view, "#create-form input[type=date]")
    day = DateTime.now!(ch.timezone) |> DateTime.to_date() |> Date.add(3)

    view
    |> form("#create-form", create: %{post_type: "fixture", date: Date.to_iso8601(day)})
    |> render_submit()

    assert [%Post{post_type: "fixture", scheduled_at: at}] = Repo.all(Post)
    assert at == Channels.made_for(ch, day)
  end

  test "a match day in the past is refused", %{conn: conn} do
    ch = channel(%{skill: "mid-innings", template_dir: "mid.innings", base_data: %{}})
    {:ok, view, _html} = live(conn, ~p"/channels/#{ch.id}")

    view
    |> form("#create-form", create: %{post_type: "fixture", date: "2020-01-01"})
    |> render_submit()

    assert Repo.all(Post) == []
  end
end
