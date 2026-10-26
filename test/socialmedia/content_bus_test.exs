defmodule Socialmedia.ContentBusTest do
  use Socialmedia.DataCase, async: false
  use Oban.Testing, repo: Socialmedia.Repo
  import Socialmedia.Fixtures
  alias Socialmedia.{Content, Posts, Repo, Storage}
  alias Socialmedia.Posts.Post
  alias Socialmedia.Workers.Produce

  setup do
    File.rm_rf!(Socialmedia.Storage.Local.root())
    :ok
  end

  defp hours(n), do: DateTime.utc_now() |> DateTime.add(n * 3600) |> DateTime.truncate(:second)

  defp slide_file(name) do
    path = Path.join(System.tmp_dir!(), name)
    File.write!(path, "jpeg-bytes-" <> name)
    path
  end

  defp made(post, slides \\ ["s-01.jpg", "s-02.jpg"]) do
    {:ok, post} =
      Content.upload(post, %{
        data: %{"quotes" => [%{"quote" => "q"}]},
        caption: "cap",
        sources: [%{"url" => "https://example.com"}],
        notes: "n",
        slides: Enum.map(slides, &slide_file/1)
      })

    post
  end

  test "each click creates one post and queues one Produce job" do
    ch = channel()

    assert {:ok, post} = Content.create(ch, %{post_type: "quote", scheduled_at: hours(5)})
    assert post.status == "creating" and post.content_key
    assert_enqueued(worker: Produce, args: %{post_id: post.id})

    {:ok, other} = Content.create(ch, %{post_type: "quote", scheduled_at: hours(29)})
    assert length(all_enqueued(worker: Produce)) == 2
    refute other.content_key == post.content_key
  end

  test "upload puts slides then the manifest in S3; pulling here makes it ready to schedule" do
    {:ok, post} = Content.create(channel(), %{post_type: "quote", scheduled_at: hours(5)})
    post = made(post)

    assert post.status == "uploaded"
    key = post.content_key
    assert post.slide_paths == ["content/#{key}/s-01.jpg", "content/#{key}/s-02.jpg"]
    assert {:ok, "jpeg-bytes-s-01.jpg"} = Storage.get(hd(post.slide_paths))
    assert [%{"key" => ^key, "caption" => "cap"}] = Content.manifests()

    assert Content.pull_all() == 1
    post = Posts.get_post!(post.id)
    assert post.status == "needs_review" and post.caption == "cap"
    assert Content.manifests() == []
    assert Repo.aggregate(Post, :count) == 1
  end

  test "pulling on another machine creates the post from the manifest" do
    ch = channel()
    {:ok, post} = Content.create(ch, %{post_type: "quote", scheduled_at: hours(5)})
    post = made(post)
    # the other machine's database doesn't have it
    Repo.delete!(post)

    [m] = Content.manifests()
    assert {:ok, pulled} = Content.pull(m)
    assert pulled.content_key == post.content_key
    assert pulled.status == "needs_review" and pulled.channel_id == ch.id
    assert pulled.slide_paths == post.slide_paths
    assert pulled.sources == [%{"url" => "https://example.com"}]
    assert pulled.scheduled_at == post.scheduled_at
  end

  test "a pulled post whose time has passed gets time for review" do
    {:ok, post} = Content.create(channel(), %{post_type: "quote", scheduled_at: hours(5)})
    post = made(post)
    Repo.delete!(post)
    [m] = Content.manifests()

    {:ok, pulled} = Content.pull(%{m | "scheduled_at" => DateTime.to_iso8601(hours(-2))})
    assert DateTime.diff(pulled.scheduled_at, DateTime.utc_now()) in 3500..3600
  end

  test "a post already scheduled here is kept when pulled again" do
    {:ok, post} = Content.create(channel(), %{post_type: "quote", scheduled_at: hours(5)})
    post = made(post)
    Content.pull_all()
    {:ok, _} = Posts.approve(Posts.get_post!(post.id))

    # regenerated on another machine and uploaded again
    :ok =
      Storage.put_json(Content.manifest_key(post.content_key), %{
        key: post.content_key,
        channel: post.channel.handle,
        post_type: "quote",
        scheduled_at: post.scheduled_at,
        caption: "newer",
        slides: post.slide_paths
      })

    [m] = Content.manifests()
    assert {:ok, :kept} = Content.pull(m)
    assert %{status: "approved", caption: "cap"} = Posts.get_post!(post.id)
    assert Content.manifests() == []
  end

  test "regenerating replaces the previous slides" do
    {:ok, post} = Content.create(channel(), %{post_type: "quote", scheduled_at: hours(5)})
    post = made(post, ["s-01.jpg", "s-02.jpg"])
    {:ok, post} = Posts.regenerate(post, "again")
    post = made(post, ["s-01.jpg"])

    assert post.slide_paths == ["content/#{post.content_key}/s-01.jpg"]
    assert {:ok, ["content/" <> _]} = Storage.list("content/#{post.content_key}/")
  end

  test "delete drops the manifest and slides without importing" do
    {:ok, post} = Content.create(channel(), %{post_type: "quote", scheduled_at: hours(5)})
    post = made(post)

    [m] = Content.manifests()
    :ok = Content.delete(m)

    assert Content.manifests() == []
    assert {:ok, []} = Storage.list("content/#{post.content_key}/")
    assert %{status: "rejected", reject_reason: "deleted_from_s3"} = Posts.get_post!(post.id)
  end

  test "a manifest for an unknown channel stays in S3" do
    {:ok, post} = Content.create(channel(), %{post_type: "quote", scheduled_at: hours(5)})
    made(post)
    [m] = Content.manifests()

    assert {:error, "no channel @nope here"} = Content.pull(%{m | "channel" => "@nope"})
    assert [_] = Content.manifests()
  end

  test "Produce waits while another post is being made" do
    p = insert_post(channel(), %{status: "creating"})

    # another server holds the lock
    holder =
      Task.async(fn ->
        {:ok, conn} = Postgrex.start_link(Keyword.drop(Repo.config(), [:pool]))
        Postgrex.query!(conn, "SELECT pg_advisory_lock(727001)", [])

        receive do
          :done -> Postgrex.query!(conn, "SELECT pg_advisory_unlock(727001)", [])
        end
      end)

    Process.sleep(100)
    assert {:snooze, 30} = perform_job(Produce, %{post_id: p.id})
    send(holder.pid, :done)
    Task.await(holder)
  end

  test "Produce only runs for a post that is being created" do
    p = insert_post(channel(), %{status: "needs_review"})
    assert {:cancel, _} = perform_job(Produce, %{post_id: p.id})
  end
end
