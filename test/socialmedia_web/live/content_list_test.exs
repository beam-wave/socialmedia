defmodule SocialmediaWeb.ContentListTest do
  use SocialmediaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Socialmedia.Fixtures

  test "a post nobody scheduled stays listed after its time", %{conn: conn} do
    old = DateTime.utc_now() |> DateTime.add(-3 * 86_400) |> DateTime.truncate(:second)
    post = insert_post(channel(), %{status: "needs_review", scheduled_at: old})

    {:ok, view, _} = live(conn, ~p"/content")
    assert has_element?(view, "#ready-#{post.id}")
  end
end
