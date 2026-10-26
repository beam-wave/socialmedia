defmodule SocialmediaWeb.PostLive.Show do
  @moduledoc "Review one post: slides, caption, data, sources. Approve, reject, regenerate."
  use SocialmediaWeb, :live_view
  import SocialmediaWeb.AdminComponents
  alias Socialmedia.Posts
  alias Socialmedia.Posts.Post
  alias SocialmediaWeb.PostText

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok, socket |> assign(slide: 0) |> load(Posts.get_post!(id))}
  end

  defp linked(post) do
    post = Socialmedia.Repo.preload(post, [:parent, :child])
    {post.parent, post.child}
  end

  alias Socialmedia.Content.Matches

  defp build_facts_form(%{parent: parent} = post) do
    post = %{post | parent: parent}
    facts = post.facts || Matches.blank_facts(post)
    teams = (parent && parent.data && parent.data["teams"]) || %{}
    team_opts = Enum.map(teams, fn {code, t} -> {t["name"] || code, code} end)
    %{facts: facts, team_opts: team_opts}
  end

  defp load(socket, post) do
    {parent, child} = linked(post)

    assign(socket,
      post: post,
      parent: parent,
      child: child,
      facts: if(Matches.needs_facts?(post), do: build_facts_form(%{post | parent: parent})),
      page_title:
        "#{post.channel.handle} · #{local(post.scheduled_at, post.channel.timezone, "%a %d %b %H:%M")}",
      caption: post.caption || "",
      data_json: if(post.data, do: Jason.encode!(post.data, pretty: true), else: ""),
      json_error: nil,
      slide: min(socket.assigns[:slide] || 0, max(length(post.slide_paths) - 1, 0))
    )
  end

  defp reload(socket), do: load(socket, Posts.get_post!(socket.assigns.post.id))

  @impl true
  def handle_info({:post_updated, %{id: id}}, %{assigns: %{post: %{id: id}}} = socket),
    do: {:noreply, reload(socket)}

  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def handle_event("approve", _, socket),
    do: act(socket, &Posts.approve/1, "Scheduled. Goes live at its time.")

  def handle_event("unapprove", _, socket), do: act(socket, &Posts.unapprove/1, "Back in review")

  def handle_event("reject", _, socket),
    do: act(socket, &Posts.reject/1, "Rejected. It won't be posted.")

  def handle_event("restore", _, socket), do: act(socket, &Posts.restore/1, "Restored")

  def handle_event("publish_now", _, socket),
    do: act(socket, &Posts.publish_now/1, "Publishing now…")

  def handle_event("regenerate", %{"note" => note}, socket) do
    note = if String.trim(note) == "", do: nil, else: note

    act(
      socket,
      &Posts.regenerate(&1, note),
      "Writing it again. The new version is uploaded to S3 when done."
    )
  end

  def handle_event("save_facts", %{"facts" => f}, socket) do
    innings =
      f
      |> Map.get("innings", %{})
      |> Enum.sort_by(fn {k, _} -> String.to_integer(k) end)
      |> Enum.map(&elem(&1, 1))
      |> Enum.reject(&(String.trim(&1["score"] || "") == ""))

    facts = %{
      "summary" => String.trim(f["summary"] || ""),
      "pom" => String.trim(f["pom"] || ""),
      "innings" => innings
    }

    cond do
      innings == [] ->
        {:noreply, put_flash(socket, :error, "Add at least one innings score.")}

      facts["pom"] == "" ->
        {:noreply, put_flash(socket, :error, "Add the player of the match.")}

      true ->
        act(
          socket,
          &Posts.enter_facts(&1, facts),
          "Saved. Claude is writing the result post."
        )
    end
  end

  def handle_event("move", %{"at" => at}, socket) do
    post = socket.assigns.post

    case SocialmediaWeb.ContentLive.parse_local(at, post.channel.timezone) do
      {:ok, at} -> act(socket, &Posts.reschedule(&1, at), "Moved")
      {:error, r} -> {:noreply, put_flash(socket, :error, explain(r))}
    end
  end

  def handle_event("slide", %{"i" => i}, socket),
    do: {:noreply, assign(socket, slide: String.to_integer(i))}

  def handle_event("caption_change", %{"caption" => c}, socket),
    do: {:noreply, assign(socket, caption: c)}

  def handle_event("save_caption", %{"caption" => c}, socket),
    do:
      act(
        socket,
        &Posts.update_content(&1, %{caption: c}),
        "Caption saved. Approve again when ready."
      )

  def handle_event("save_data", %{"data" => raw}, socket) do
    case Jason.decode(raw) do
      {:ok, data} when is_map(data) ->
        act(
          socket,
          &Posts.update_content(&1, %{data: data}),
          "Saved. Re-rendering the slides."
        )

      _ ->
        {:noreply, assign(socket, data_json: raw, json_error: "Not valid JSON")}
    end
  end

  defp act(socket, fun, ok_msg) do
    case fun.(socket.assigns.post) do
      {:ok, _} -> {:noreply, socket |> put_flash(:info, ok_msg) |> reload()}
      {:error, reason} -> {:noreply, put_flash(socket, :error, explain(reason))}
    end
  end

  defp explain(:slot_passed), do: "The slot time has passed."
  defp explain(:time_passed), do: "Pick a time in the future."
  defp explain(:bad_time), do: "That date/time isn't valid."

  defp explain(:not_reviewable),
    do: "This post can't be changed in its current state. Pull it first if it's in S3."

  defp explain(:not_approved), do: "Only approved posts can do that."
  defp explain(:final), do: "This post is already final."
  defp explain(other), do: inspect(other)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      nav_channels={@nav_channels}
      current_path={@current_path}
    >
      <div class="text-xs muted">
        <.link navigate={~p"/channels/#{@post.channel.id}"} class="hover:underline">
          ← {@post.channel.handle}
        </.link>
      </div>

      <div class="flex flex-wrap items-start justify-between gap-4">
        <div>
          <div class="flex items-center gap-2">
            <.status_badge status={@post.status} />
            <span class="text-xs muted">{post_type_label(@post.post_type)}</span>
          </div>
          <h1 class="text-xl font-semibold tracking-tight mt-1.5">
            {PostText.title(@post) || "Not written yet"}
          </h1>
          <form
            :if={@post.status not in ~w(published publishing rejected)}
            phx-submit="move"
            class="flex flex-wrap items-center gap-2 mt-2 text-sm"
          >
            <span class="muted">Goes live</span>
            <input
              type="datetime-local"
              name="at"
              value={
                @post.scheduled_at
                |> DateTime.shift_zone!(@post.channel.timezone)
                |> Calendar.strftime("%Y-%m-%dT%H:%M")
              }
              class="input input-sm mono"
              aria-label="Post at"
            />
            <span class="muted">{@post.channel.timezone}</span>
            <button class="btn btn-xs btn-ghost">Move</button>
            <span :if={@post.channel.dry_run} class="muted">· dry-run channel</span>
          </form>
          <p :if={@post.status in ~w(published publishing rejected)} class="text-sm muted mt-1">
            {local(@post.scheduled_at, @post.channel.timezone, "%A %d %B, %H:%M")} ({@post.channel.timezone})
          </p>
        </div>
        <.actions post={@post} />
      </div>

      <div
        :if={@parent || @child}
        class="text-sm rounded-lg border hairline px-3 py-2 flex items-center gap-2"
      >
        <.icon name="hero-link" class="size-4 muted" />
        <span :if={@parent}>
          Scores the predictions from the
          <.link navigate={~p"/posts/#{@parent.id}"} class="underline">match-day post</.link>
          ({status_label(@parent.status)})
        </span>
        <span :if={@child}>
          Result post:
          <.link navigate={~p"/posts/#{@child.id}"} class="underline">
            {local(@child.scheduled_at, @post.channel.timezone, "%a %d %b · %H:%M")}
          </.link>
          ({status_label(@child.status)}){if @child.status == "planned",
            do: " · enter the result there to write it"}
        </span>
      </div>

      <.facts_form
        :if={@facts && @post.status not in ~w(published publishing rejected)}
        post={@post}
        facts={@facts}
      />

      <div :if={@post.error} class="rounded-lg border-2 border-base-content px-4 py-3 text-sm">
        <div class="font-semibold flex items-center gap-1.5">
          <.icon name="hero-exclamation-triangle" class="size-4" /> Problem
        </div>
        <p class="mt-1 whitespace-pre-wrap break-words">{@post.error}</p>
      </div>

      <div :if={@post.permalink} class="text-sm">
        Live on Instagram:
        <a href={@post.permalink} target="_blank" rel="noopener" class="underline">
          {@post.permalink}
        </a>
      </div>

      <div class="grid lg:grid-cols-[minmax(0,420px)_1fr] gap-8 items-start">
        <section class="space-y-3">
          <div
            :if={@post.slide_paths == []}
            class="slide-thumb w-full rounded-lg border border-dashed hairline grid place-items-center text-sm muted"
          >
            {case @post.status do
              "creating" -> "Being made…"
              "planned" -> "Enter the match result to write it"
              _ -> "No slides yet"
            end}
          </div>
          <img
            :if={@post.slide_paths != []}
            src={slide_src(Enum.at(@post.slide_paths, @slide))}
            class="slide-thumb w-full rounded-lg border hairline"
            alt={"Slide #{@slide + 1}"}
          />
          <div :if={length(@post.slide_paths) > 1} class="flex gap-2 overflow-x-auto pb-1">
            <button
              :for={{path, i} <- Enum.with_index(@post.slide_paths)}
              phx-click="slide"
              phx-value-i={i}
              class={[
                "shrink-0 rounded border-2 transition-colors",
                if(i == @slide,
                  do: "border-base-content",
                  else: "border-transparent opacity-60 hover:opacity-100"
                )
              ]}
              aria-label={"Show slide #{i + 1}"}
            >
              <img src={slide_src(path)} class="slide-thumb w-14 rounded-sm" alt="" />
            </button>
          </div>
        </section>

        <section class="space-y-6 min-w-0">
          <form phx-change="caption_change" phx-submit="save_caption" class="space-y-2">
            <div class="flex items-center justify-between">
              <label for="caption" class="text-sm font-semibold">Caption</label>
              <span class={[
                "text-xs tabular-nums",
                if(String.length(@caption) > 2200, do: "font-semibold", else: "muted")
              ]}>
                {String.length(@caption)} / 2200
              </span>
            </div>
            <textarea
              id="caption"
              name="caption"
              rows="12"
              phx-debounce="300"
              disabled={
                !Post.reviewable?(@post) or is_nil(@post.data) or
                  @post.status in ~w(creating uploaded)
              }
              class="textarea w-full text-sm leading-relaxed"
            >{@caption}</textarea>
            <button
              :if={
                Post.reviewable?(@post) and @post.data && @post.status not in ~w(creating uploaded) &&
                  @caption != (@post.caption || "")
              }
              class="btn btn-sm btn-outline"
            >
              Save caption
            </button>
          </form>

          <div :if={@post.agent_log} class="space-y-1">
            <h3 class="text-sm font-semibold">Agent notes</h3>
            <p class="text-sm muted whitespace-pre-wrap">{@post.agent_log}</p>
          </div>

          <div :if={@post.sources != []} class="space-y-1">
            <h3 class="text-sm font-semibold">Sources · check the facts</h3>
            <ul class="text-sm space-y-0.5">
              <li :for={s <- @post.sources} class="truncate">
                <a href={s["url"]} target="_blank" rel="noopener" class="underline underline-offset-2">
                  {s["title"] || s["url"]}
                </a>
              </li>
            </ul>
          </div>

          <form
            :if={Post.reviewable?(@post) and @post.status not in ~w(planned creating)}
            phx-submit="regenerate"
            class="rounded-lg border hairline p-3 space-y-2"
          >
            <label for="note" class="text-sm font-semibold">Write it again</label>
            <textarea
              id="note"
              name="note"
              rows="2"
              placeholder="Optional note for the agent, e.g. warmer tone, different startup, use the Hindi title…"
              class="textarea w-full text-sm"
            ></textarea>
            <button
              class="btn btn-sm btn-outline"
              data-confirm="Replace this post with a new version?"
            >
              <.icon name="hero-arrow-path" class="size-4" /> Regenerate
            </button>
          </form>

          <details :if={@post.data} class="rounded-lg border hairline">
            <summary class="cursor-pointer px-3 py-2 text-sm font-semibold">
              Slide data (JSON)
            </summary>
            <form phx-submit="save_data" class="p-3 pt-0 space-y-2">
              <textarea
                name="data"
                rows="18"
                class="textarea w-full mono text-xs"
                disabled={!Post.reviewable?(@post)}
              >{@data_json}</textarea>
              <p :if={@json_error} class="text-xs font-semibold">{@json_error}</p>
              <button :if={Post.reviewable?(@post)} class="btn btn-sm btn-outline">
                Save and re-render
              </button>
            </form>
          </details>
        </section>
      </div>
    </Layouts.app>
    """
  end

  attr :post, :map, required: true
  attr :facts, :map, required: true

  defp facts_form(assigns) do
    ~H"""
    <form phx-submit="save_facts" class="rounded-lg border-2 border-base-content p-4 space-y-4">
      <div class="flex flex-wrap items-baseline justify-between gap-2">
        <h2 class="font-semibold">Match result</h2>
        <span class="text-xs muted">
          {if @post.facts,
            do: "Edit and save to have Claude rewrite it.",
            else: "Type what happened. Claude writes the post and scores the predictions."}
        </span>
      </div>

      <label class="block text-sm">
        <span class="block mb-1 font-medium">Summary</span>
        <textarea
          name="facts[summary]"
          rows="2"
          class="textarea w-full text-sm"
          placeholder="India won by 6 wickets with 9 balls left. Kohli anchored the chase."
        >{@facts.facts["summary"]}</textarea>
      </label>

      <div class="grid md:grid-cols-2 gap-4">
        <fieldset
          :for={{inn, i} <- Enum.with_index(@facts.facts["innings"] || [])}
          class="rounded-md border hairline p-3 space-y-2"
        >
          <legend class="px-1 text-xs uppercase tracking-wider muted">Innings {i + 1}</legend>
          <label class="block text-xs">
            <span class="block muted mb-1">Batting team</span>
            <select name={"facts[innings][#{i}][team]"} class="select select-sm w-full">
              <option
                :for={{label, code} <- @facts.team_opts}
                value={code}
                selected={code == inn["team"]}
              >
                {label}
              </option>
            </select>
          </label>
          <label class="block text-xs">
            <span class="block muted mb-1">Score</span>
            <input
              name={"facts[innings][#{i}][score]"}
              value={inn["score"]}
              class="input input-sm w-full mono"
              placeholder="184/7 (20)"
            />
          </label>
          <label class="block text-xs">
            <span class="block muted mb-1">Best batter</span>
            <input
              name={"facts[innings][#{i}][best_bat]"}
              value={inn["best_bat"]}
              class="input input-sm w-full"
              placeholder="Virat Kohli 78* (44)"
            />
          </label>
          <label class="block text-xs">
            <span class="block muted mb-1">Best bowler (fielding side)</span>
            <input
              name={"facts[innings][#{i}][best_bowl]"}
              value={inn["best_bowl"]}
              class="input input-sm w-full"
              placeholder="Jasprit Bumrah 3/24 (4)"
            />
          </label>
        </fieldset>
      </div>

      <div class="flex flex-wrap items-end gap-3">
        <label class="block text-sm flex-1 min-w-60">
          <span class="block mb-1 font-medium">Player of the match</span>
          <input
            name="facts[pom]"
            value={@facts.facts["pom"]}
            class="input input-sm w-full"
            placeholder="Virat Kohli 78* (44)"
          />
        </label>
        <button class="btn btn-sm btn-primary" phx-disable-with="Saving…">
          {if @post.facts, do: "Save and rewrite", else: "Save result"}
        </button>
      </div>
    </form>
    """
  end

  attr :post, :map, required: true

  defp actions(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-2">
      <%= case @post.status do %>
        <% "needs_review" -> %>
          <button
            phx-click="reject"
            class="btn btn-sm btn-ghost"
            data-confirm="Reject? It won't be posted."
          >
            Reject
          </button>
          <button phx-click="approve" class="btn btn-sm btn-primary">
            <.icon name="hero-check" class="size-4" /> Schedule
          </button>
        <% "approved" -> %>
          <button phx-click="unapprove" class="btn btn-sm btn-ghost">Back to review</button>
          <button
            phx-click="publish_now"
            class="btn btn-sm btn-outline"
            data-confirm="Post to Instagram right now instead of at the slot?"
          >
            Publish now
          </button>
        <% "rejected" -> %>
          <button phx-click="restore" class="btn btn-sm btn-outline">Restore</button>
        <% "uploaded" -> %>
          <span class="text-sm muted">In S3. Pull it on the Content page to schedule.</span>
          <.link navigate={~p"/content"} class="btn btn-sm btn-outline">Content</.link>
        <% s when s in ["planned", "failed", "creating"] -> %>
          <button phx-click="reject" class="btn btn-sm btn-ghost" data-confirm="Reject this post?">
            Reject
          </button>
          <button
            :if={s == "failed"}
            phx-click="regenerate"
            phx-value-note=""
            class="btn btn-sm btn-primary"
          >
            Try again
          </button>
        <% _ -> %>
      <% end %>
    </div>
    """
  end
end
