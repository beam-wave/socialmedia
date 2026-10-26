defmodule SocialmediaWeb.AdminComponents do
  @moduledoc "Monochrome building blocks for the admin panel."
  use Phoenix.Component
  import SocialmediaWeb.CoreComponents, only: [icon: 1]

  @status %{
    "planned" => {"Needs result", "border border-dashed hairline muted", "hero-pencil-square"},
    "creating" => {"Creating", "border border-dashed hairline muted", "hero-sparkles"},
    "uploaded" => {"In S3", "border hairline muted", "hero-cloud-arrow-up"},
    "needs_review" =>
      {"Ready to schedule", "bg-base-content text-base-100 font-semibold", "hero-eye"},
    "approved" => {"Scheduled", "border border-base-content font-medium", "hero-check"},
    "publishing" => {"Posting", "border border-base-content font-medium", "hero-arrow-up-tray"},
    "published" => {"Live", "surface muted", "hero-check-circle"},
    "failed" =>
      {"Failed", "border-2 border-base-content font-semibold", "hero-exclamation-triangle"},
    "rejected" => {"Rejected", "faint line-through", "hero-x-mark"}
  }

  def status_label(status), do: @status |> Map.get(status, {status, "", nil}) |> elem(0)

  attr :status, :string, required: true
  attr :class, :string, default: nil

  def status_badge(assigns) do
    {label, cls, icon} =
      Map.get(@status, assigns.status, {assigns.status, "border hairline", nil})

    assigns = assign(assigns, label: label, cls: cls, icon_name: icon)

    ~H"""
    <span class={[
      "inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[11px] leading-4 whitespace-nowrap",
      @cls,
      @class
    ]}>
      <.icon :if={@icon_name} name={@icon_name} class="size-3" />
      {@label}
    </span>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :href, :string, default: nil
  attr :strong, :boolean, default: false

  def stat(assigns) do
    ~H"""
    <.link
      navigate={@href}
      class={[
        "block rounded-lg border px-4 py-3 transition-colors",
        if(@strong, do: "border-base-content", else: "hairline"),
        @href && "row-hover"
      ]}
    >
      <div class="text-2xl font-semibold tabular-nums">{@value}</div>
      <div class="text-xs muted mt-0.5">{@label}</div>
    </.link>
    """
  end

  attr :tabs, :list, required: true, doc: "[{label, path, active?}]"

  def tabs(assigns) do
    ~H"""
    <nav class="flex gap-6 border-b hairline text-sm">
      <.link
        :for={{label, path, active} <- @tabs}
        patch={path}
        class={[
          "-mb-px border-b-2 pb-2.5 transition-colors",
          if(active,
            do: "border-base-content font-medium",
            else: "border-transparent muted hover:text-base-content"
          )
        ]}
      >
        {label}
      </.link>
    </nav>
    """
  end

  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  slot :actions

  def page_header(assigns) do
    ~H"""
    <div class="flex flex-wrap items-end justify-between gap-4">
      <div>
        <h1 class="text-xl font-semibold tracking-tight">{@title}</h1>
        <p :if={@subtitle} class="text-sm muted mt-1">{@subtitle}</p>
      </div>
      <div class="flex items-center gap-2">{render_slot(@actions)}</div>
    </div>
    """
  end

  attr :text, :string, required: true
  slot :inner_block

  def empty(assigns) do
    ~H"""
    <div class="rounded-lg border border-dashed hairline px-6 py-10 text-center text-sm muted">
      {@text}
      <div :if={@inner_block != []} class="mt-3">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  @doc "Local time label for a UTC datetime in a timezone."
  def local(%DateTime{} = dt, tz, fmt \\ "%a %d %b · %H:%M"),
    do: dt |> DateTime.shift_zone!(tz) |> Calendar.strftime(fmt)

  def weekday_names, do: ~w(Mon Tue Wed Thu Fri Sat Sun)

  def post_type_label("quote"), do: "Quote"
  def post_type_label("top5"), do: "Top 5"
  def post_type_label("fixture"), do: "Match day"
  def post_type_label("result"), do: "Result"
  def post_type_label("movie"), do: "Movie"
  def post_type_label(other), do: other

  @doc "Presigned URL of a slide in S3 for <img src> (valid 1 hour)."
  def slide_src(key), do: Socialmedia.Storage.url(key, 3600)
end

defmodule SocialmediaWeb.PostText do
  @moduledoc "One-line description of a post's content for lists."

  def title(%{data: nil}), do: nil

  def title(%{data: d}) do
    cond do
      q = first(d, "quotes") -> clean(q["quote"])
      m = first(d, "movies") -> m["title"]
      p = first(d, "posts") -> "#{p["team1"]} v #{p["team2"]} · #{p["match"]}"
      d["title"] -> clean(d["title"]) <> if(d["domain"], do: " (#{d["domain"]})", else: "")
      true -> nil
    end
  end

  defp first(d, k) do
    case d[k] do
      [x | _] when is_map(x) -> x
      _ -> nil
    end
  end

  defp clean(nil), do: nil
  defp clean(s), do: String.replace(s, "*", "")
end
