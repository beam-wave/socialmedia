defmodule Socialmedia.ContentBusTest do
  use Socialmedia.DataCase, async: false
  import Socialmedia.Fixtures
  alias Socialmedia.{Content, Posts, Storage}
  alias Socialmedia.Content.Work

  setup do
    File.rm_rf!(Socialmedia.Storage.Local.root())
    :ok
  end

  defp due_post(attrs \\ %{}) do
    past = DateTime.utc_now() |> DateTime.add(-10) |> DateTime.truncate(:second)

    insert_post(
      channel(),
      Map.merge(%{status: "planned", data: nil, slide_paths: [], generate_at: past}, attrs)
    )
  end

  defp slide_file(name) do
    path = Path.join(System.tmp_dir!(), name)
    File.write!(path, "jpeg-bytes-" <> name)
    path
  end

  test "prod publishes plan.json, Mac delivers, prod imports into review" do
    p = due_post()

    # prod
    assert {:ok, 1} = Content.publish_plan()

    # Mac
    assert {:ok, [%Work{post_id: id, rev: 1, kind: "generate"} = w]} = Content.read_plan()
    assert id == p.id
    refute Content.delivered?(w)

    :ok =
      Content.deliver(w, %{
        data: %{"quotes" => [%{"quote" => "q"}]},
        caption: "cap",
        sources: [],
        notes: "n",
        slides: [slide_file("s-01.jpg"), slide_file("s-02.jpg")]
      })

    assert Content.delivered?(w)

    # prod
    assert Content.import_inbox() == 1
    post = Posts.get_post!(p.id)
    assert post.status == "needs_review"
    assert post.caption == "cap"
    assert post.slide_paths == ["content/#{p.id}/1/s-01.jpg", "content/#{p.id}/1/s-02.jpg"]
    assert {:ok, "jpeg-bytes-s-01.jpg"} = Storage.get(hd(post.slide_paths))
    assert {:ok, []} = Storage.list("inbox/")

    # nothing left to do
    assert {:ok, 0} = Content.publish_plan()
  end

  test "a manifest for an old revision is dropped" do
    p = due_post()
    {:ok, 1} = Content.publish_plan()
    {:ok, [w]} = Content.read_plan()

    # admin regenerates before the Mac delivers rev 1
    {:ok, _} = Posts.regenerate(Posts.get_post!(p.id), "again")
    :ok = Content.deliver(w, %{data: %{}, caption: "old", slides: [slide_file("o.jpg")]})

    assert Content.import_inbox() == 0
    assert %{status: "planned", gen_rev: 2} = Posts.get_post!(p.id)
    assert {:ok, []} = Storage.list("inbox/")
  end

  test "agent skips arrive as failures with the reason" do
    p = due_post()
    {:ok, _} = Content.publish_plan()
    {:ok, [w]} = Content.read_plan()
    :ok = Content.deliver_failure(w, "no match today", true)

    Content.import_inbox()
    assert %{status: "failed", error: "Agent skipped: no match today"} = Posts.get_post!(p.id)
  end

  test "re-render replaces the previous revision's slides" do
    p = due_post()
    {:ok, _} = Content.publish_plan()
    {:ok, [w]} = Content.read_plan()
    :ok = Content.deliver(w, %{data: %{"a" => 1}, caption: "c", slides: [slide_file("v1.jpg")]})
    Content.import_inbox()

    {:ok, post} = Posts.update_content(Posts.get_post!(p.id), %{data: %{"a" => 2}})
    assert post.status == "render_requested" and post.gen_rev == 2

    {:ok, _} = Content.publish_plan()
    {:ok, [w2]} = Content.read_plan()
    assert w2.kind == "render" and w2.rev == 2 and w2.data == %{"a" => 2}
    :ok = Content.deliver(w2, %{data: %{"a" => 2}, caption: "c2", slides: [slide_file("v2.jpg")]})
    Content.import_inbox()

    post = Posts.get_post!(p.id)
    assert post.slide_paths == ["content/#{p.id}/2/v2.jpg"]
    assert {:error, :not_found} = Storage.get("content/#{p.id}/1/v1.jpg")
  end
end
