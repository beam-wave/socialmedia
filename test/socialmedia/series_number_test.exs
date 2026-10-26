defmodule Socialmedia.SeriesNumberTest do
  use Socialmedia.DataCase, async: false
  use Oban.Testing, repo: Socialmedia.Repo
  import Socialmedia.Fixtures
  alias Socialmedia.{Agent, Content, Posts, Repo}
  alias Socialmedia.Content.Work

  setup do
    File.rm_rf!(Socialmedia.Storage.Local.root())
    :ok
  end

  defp hours(n), do: DateTime.utc_now() |> DateTime.add(n * 3600) |> DateTime.truncate(:second)

  defp create(ch),
    do: Content.create(ch, %{post_type: "quote", scheduled_at: hours(5)}) |> elem(1)

  test "each post takes the next number, starting from series_start" do
    ch = channel()
    assert Enum.map(1..3, fn _ -> create(ch).series_number end) == [42, 43, 44]
  end

  test "a rejected last post frees its number" do
    ch = channel()
    _ = create(ch)
    last = create(ch)
    {:ok, _} = Posts.reject(last)
    assert create(ch).series_number == 43
  end

  test "channels without a series get no number" do
    ch = channel(%{base_data: %{"theme" => "x"}})
    assert create(ch).series_number == nil
  end

  test "the agent and the slide data use the post's number" do
    ch = channel()
    _ = create(ch)
    post = create(ch) |> Repo.preload([:channel, :schedule, :parent])
    w = Work.from_post(post, "generate", [])

    assert Agent.build_prompt(w) =~ "Day 43 of 365"
    data = Agent.assemble(w, %{"quotes" => [%{"quote" => "q"}]})
    assert hd(data["quotes"])["day"] == 43
    refute Map.has_key?(data, "series_start")
  end

  test "regenerating keeps the number; a pull carries it" do
    ch = channel()
    post = create(ch)
    file = Path.join(System.tmp_dir!(), "sn-#{post.id}.jpg")
    File.write!(file, "jpg")
    {:ok, post} = Content.upload(post, %{data: %{}, caption: "c", slides: [file]})
    {:ok, again} = Posts.regenerate(post)
    assert again.series_number == 42

    {:ok, _} = Content.upload(again, %{data: %{}, caption: "c", slides: [file]})
    Repo.delete!(again)
    [m] = Content.manifests()
    {:ok, pulled} = Content.pull(m)
    assert pulled.series_number == 42
  end
end
