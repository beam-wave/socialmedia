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

  # Graph stub for a channel with an EAA token: carousel + reel, trending audio available.
  # `audio_ok?` false makes Instagram refuse the track.
  defp stub_graph(test_pid, audio_ok? \\ true) do
    Req.Test.stub(Socialmedia.Instagram.Graph, fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      form = URI.decode_query(body)
      path = conn.request_path |> String.replace(~r"^/v\d+\.\d+", "")
      send(test_pid, {conn.method, path, form, conn.query_params})

      case {conn.method, path} do
        {"GET", "/17841/content_publishing_limit"} ->
          Req.Test.json(conn, %{"data" => [%{"quota_usage" => 1}]})

        {"GET", "/ig_audio"} ->
          Req.Test.json(conn, %{
            "audio" => [%{"audio_id" => "555", "title" => "Trend", "display_artist" => "DJ"}]
          })

        {"POST", "/17841/media"} when is_map_key(form, "audio_configuration") and not audio_ok? ->
          conn
          |> Plug.Conn.put_status(400)
          |> Req.Test.json(%{"error" => %{"message" => "audio not allowed", "code" => 100}})

        {"POST", "/17841/media"} ->
          kind = if form["media_type"] == "REELS", do: "r", else: "c"
          Req.Test.json(conn, %{"id" => "#{kind}-#{System.unique_integer([:positive])}"})

        {"GET", "/" <> c} when binary_part(c, 0, 2) in ["c-", "r-"] ->
          Req.Test.json(conn, %{"status_code" => "FINISHED"})

        {"POST", "/17841/media_publish"} ->
          id = if String.starts_with?(form["creation_id"], "r-"), do: "reel1", else: "m1"
          Req.Test.json(conn, %{"id" => id})

        {"GET", "/" <> id} ->
          Req.Test.json(conn, %{"permalink" => "https://instagram.com/p/#{id}"})
      end
    end)
  end

  defp both(p) do
    {:ok, _} = Channels.update_channel(p.channel, %{access_token: "EAAtoken"})

    p
    |> Ecto.Changeset.change(
      formats: ["post", "reel"],
      video_path: "content/1/1/reel.mp4",
      cover_path: "content/1/1/reel-cover.jpg"
    )
    |> Socialmedia.Repo.update!()
  end

  test "post and reel: both go out, the reel with a trending track", %{post: p} do
    p = both(p)
    stub_graph(self())

    assert :ok = perform_job(Publish, %{post_id: p.id})
    post = Posts.get_post!(p.id)
    assert post.status == "published"
    assert {post.ig_media_id, post.reel_media_id} == {"m1", "reel1"}
    assert post.reel_permalink == "https://instagram.com/p/reel1"
    assert post.reel_audio == %{"audio_id" => "555", "title" => "Trend", "artist" => "DJ"}

    assert_received {"GET", "/ig_audio", _, %{"audio_type" => "music", "user_id" => "17841"}}

    assert_received {"POST", "/17841/media",
                     %{
                       "media_type" => "REELS",
                       "video_url" => "/local-storage/test/content/1/1/reel.mp4",
                       "share_to_feed" => "true",
                       "audio_configuration" => audio
                     }, _}

    assert %{"audio_id" => "555"} = Jason.decode!(audio)
  end

  test "a retry after the post went out only publishes the reel", %{post: p} do
    p = both(p) |> Ecto.Changeset.change(ig_media_id: "m0") |> Socialmedia.Repo.update!()
    stub_graph(self())

    assert :ok = perform_job(Publish, %{post_id: p.id})
    post = Posts.get_post!(p.id)
    assert {post.ig_media_id, post.reel_media_id} == {"m0", "reel1"}
    refute_received {"POST", "/17841/media", %{"is_carousel_item" => _}, _}
  end

  test "if Instagram refuses the track, the reel goes out silent", %{post: p} do
    p = both(p)
    stub_graph(self(), false)

    assert :ok = perform_job(Publish, %{post_id: p.id})
    post = Posts.get_post!(p.id)
    assert post.reel_media_id == "reel1" and is_nil(post.reel_audio)
  end

  test "an IG… token skips the Audio API", %{post: p} do
    p = both(p)
    {:ok, _} = Channels.update_channel(p.channel, %{access_token: "IGtoken"})
    stub_graph(self())

    assert :ok = perform_job(Publish, %{post_id: p.id})
    refute_received {"GET", "/ig_audio", _, _}
    assert Posts.get_post!(p.id).reel_media_id == "reel1"
  end

  test "a rejected post is never published", %{post: p} do
    {:ok, _} = Posts.reject(p)
    assert {:cancel, _} = perform_job(Publish, %{post_id: p.id})
  end
end
