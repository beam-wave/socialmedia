defmodule SocialmediaWeb.ResultFormTest do
  use SocialmediaWeb.ConnCase, async: false
  use Oban.Testing, repo: Socialmedia.Repo
  import Phoenix.LiveViewTest
  import Socialmedia.Fixtures
  alias Socialmedia.Posts
  alias Socialmedia.Workers.Produce

  setup do
    ch = channel(%{skill: "mid-innings", template_dir: "mid.innings", base_data: %{}})

    fx =
      insert_post(ch, %{
        post_type: "fixture",
        data: %{
          "teams" => %{
            "IND" => %{"code" => "IND", "name" => "India", "color" => "#1f5fd1"},
            "AUS" => %{"code" => "AUS", "name" => "Australia", "color" => "#d9a400"}
          },
          "posts" => [
            %{"team1" => "IND", "team2" => "AUS", "watch" => [%{"name" => "Virat Kohli"}]}
          ]
        }
      })

    result =
      insert_post(ch, %{
        post_type: "result",
        status: "planned",
        data: nil,
        slide_paths: [],
        parent_id: fx.id
      })

    %{result: result}
  end

  test "the form offers the fixture's teams and builds the post without Claude", %{
    conn: conn,
    result: result
  } do
    {:ok, view, _} = live(conn, ~p"/posts/#{result.id}")

    assert has_element?(view, "#facts-form select option[value=IND]")
    assert has_element?(view, "#fixture-players option[value='Virat Kohli']")

    view
    |> form("#facts-form",
      facts: %{
        innings: %{
          "0" => %{team: "IND", runs: "200", wkts: "5", overs: "20.0"},
          "1" => %{team: "AUS", runs: "170", wkts: "10", overs: "19.2"}
        },
        pom: "Virat Kohli",
        pom_figures: "90 (50)"
      }
    )
    |> render_submit()

    post = Posts.get_post!(result.id)
    assert post.status == "creating"
    assert %{"posts" => [%{"result" => "*India* beat Australia by 30 runs"}]} = post.data
    assert_enqueued(worker: Produce, args: %{post_id: result.id, render_only: true})
  end

  test "a bad score keeps the form and shows why", %{conn: conn, result: result} do
    {:ok, view, _} = live(conn, ~p"/posts/#{result.id}")

    html =
      view
      |> form("#facts-form",
        facts: %{
          innings: %{
            "0" => %{team: "IND", runs: "lots", wkts: "5", overs: "20.0"},
            "1" => %{team: "AUS", runs: "170", wkts: "10", overs: "19.2"}
          },
          pom: "Virat Kohli"
        }
      )
      |> render_submit()

    assert html =~ "Innings 1: runs must be a whole number."
    assert has_element?(view, "#facts-form input[value=lots]")
    assert Posts.get_post!(result.id).status == "planned"
  end
end
