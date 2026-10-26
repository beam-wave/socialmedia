defmodule Socialmedia.PublishTest do
  use Socialmedia.DataCase, async: false
  use Oban.Testing, repo: Socialmedia.Repo
  import Socialmedia.Fixtures
  alias Socialmedia.{Posts, Channels}
  alias Socialmedia.Workers.Publish

  setup do
    Application.put_env(:socialmedia, :public_base_url, "https://social.test")

    on_exit(fn -> Application.delete_env(:socialmedia, :public_base_url) end)

    ch = channel()

    {:ok, ch} =
      Channels.update_channel(ch, %{dry_run: false, ig_user_id: "17841", access_token: "tok"})

    slides = ["content/1/1/a.jpg", "content/1/1/b.jpg"]
    {:ok, p} = insert_post(ch, %{slide_paths: slides, caption: "hello"}) |> Posts.approve()
    %{post: p}
  end

  test "a dry-run channel never calls Instagram and marks a dry run", %{post: p} do
    {:ok, _} = Channels.update_channel(p.channel, %{dry_run: true})
    Req.Test.stub(Socialmedia.Instagram.Graph, fn _ -> raise "must not call Instagram" end)

    assert :ok = perform_job(Publish, %{post_id: p.id})
    post = Posts.get_post!(p.id)
    assert post.status == "published"
    assert post.agent_log =~ "Dry run"
  end

  test "publishes a carousel through the Graph API", %{post: p} do
    test_pid = self()

    Req.Test.stub(Socialmedia.Instagram.Graph, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      form = URI.decode_query(body)
      path = String.replace_prefix(conn.request_path, "/v23.0", "")
      send(test_pid, {conn.method, path, form})

      resp =
        case {conn.method, path} do
          {"GET", "/17841/content_publishing_limit"} ->
            %{"data" => [%{"quota_usage" => 1, "config" => %{"quota_total" => 100}}]}

          {"POST", "/17841/media"} ->
            %{"id" => "c-#{System.unique_integer([:positive])}"}

          {"GET", "/c-" <> _} ->
            %{"status_code" => "FINISHED"}

          {"POST", "/17841/media_publish"} ->
            %{"id" => "m1"}

          {"GET", "/m1"} ->
            %{"permalink" => "https://instagram.com/p/x"}
        end

      Req.Test.json(conn, resp)
    end)

    assert :ok = perform_job(Publish, %{post_id: p.id})
    post = Posts.get_post!(p.id)
    assert post.status == "published"
    assert post.ig_media_id == "m1"
    assert post.permalink == "https://instagram.com/p/x"

    assert_received {"POST", "/17841/media",
                     %{
                       "image_url" => "/local-storage/test/content/1/1/a.jpg",
                       "is_carousel_item" => "true"
                     }}

    assert_received {"POST", "/17841/media",
                     %{"image_url" => "/local-storage/test/content/1/1/b.jpg"}}

    assert_received {"POST", "/17841/media", %{"media_type" => "CAROUSEL", "caption" => "hello"}}
  end

  test "a rejected post is never published", %{post: p} do
    {:ok, _} = Posts.reject(p)
    assert {:cancel, _} = perform_job(Publish, %{post_id: p.id})
  end
end
