defmodule Socialmedia.ProduceFailuresTest do
  use Socialmedia.DataCase, async: true
  import Socialmedia.Fixtures
  alias Socialmedia.Posts
  alias Socialmedia.Workers.ProduceFailures

  defp job(post),
    do: %Oban.Job{worker: "Socialmedia.Workers.Produce", args: %{"post_id" => post.id}}

  test "a discarded Produce job fails its post with the reason" do
    post = insert_post(channel(), %{status: "creating"})
    meta = %{state: :discard, job: job(post), reason: %RuntimeError{message: "boom"}}

    ProduceFailures.handle_event([:oban, :job, :exception], %{}, meta, nil)

    assert %{status: "failed", error: "Making it failed: boom"} = Posts.get_post!(post.id)
  end

  test "a job that will be retried leaves the post creating" do
    post = insert_post(channel(), %{status: "creating"})
    meta = %{state: :failure, job: job(post), reason: %RuntimeError{message: "boom"}}

    ProduceFailures.handle_event([:oban, :job, :exception], %{}, meta, nil)

    assert Posts.get_post!(post.id).status == "creating"
  end

  test "other workers are ignored" do
    post = insert_post(channel(), %{status: "creating"})
    meta = %{state: :discard, job: %{job(post) | worker: "Other"}, reason: :x}
    ProduceFailures.handle_event([:oban, :job, :exception], %{}, meta, nil)
    assert Posts.get_post!(post.id).status == "creating"
  end
end
