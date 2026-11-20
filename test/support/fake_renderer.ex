defmodule Socialmedia.FakeRenderer do
  @moduledoc false
  # Stands in for Content.Renderer in tests: writes two small "slides"
  def render(_channel, data, out) do
    File.mkdir_p!(out)

    slides =
      for n <- ["r-01-result.jpg", "r-02-answers.jpg"] do
        path = Path.join(out, n)
        File.write!(path, "jpg")
        path
      end

    send(self(), {:rendered, data})
    {:ok, %{slides: slides, caption: "result caption"}}
  end
end
