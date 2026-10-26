# Content desk

Phoenix LiveView app that writes, renders, reviews and publishes posts for five Instagram channels:
@spotlight.startups, @puree_heartz, @_motivation2live__, @mid.innings and @bollyvibe.

- **Writing** uses the local Claude Code CLI (`claude -p`) on your subscription, so no API key is needed. There is one agent with one skill per channel (`agent/.claude/skills/*`) and a JSON schema per channel (`agent/schemas/*`).
- **Rendering** uses the channel studios (`channels/<dir>/template.html`), driven by Playwright through `renderer/render.js`. It produces 1080×1350 JPEGs at quality 100 plus the caption. The JPEGs are stored in S3.
- **Publishing** goes straight to the Instagram Graph API (Instagram API with Instagram Login).
- **Only scheduled posts go live.** The admin reviews each post in **Content**, edits the caption and time, and schedules it. Anything not scheduled by its time is rejected.

## How the pieces fit

Every step is a button, and every machine runs the same app with the same settings. Content moves between machines only through the private S3 bucket **`socialmedia-dravya`** (ap-south-1), under `prod/`.

```
   ANY MACHINE WITH CLAUDE (your Mac)          S3 socialmedia-dravya/prod/            PROD (or the same Mac)
 ┌───────────────────────────────────┐                                         ┌──────────────────────────────┐
 │ Channel page → Create (one post)  │                                         │ Content → Pull / Delete      │
 │ Oban Produce job:                 │── content/<key>/*.jpg ─────────────────▶│ post is Ready to schedule    │
 │   claude -p → data                │── inbox/<key>.json (written last) ─────▶│ Schedule → Oban Publish job  │
 │   render.js → JPEG q100           │                                         │   at that time → Instagram   │
 └───────────────────────────────────┘                                         └──────────────────────────────┘
```

1. **Create.** On a channel page, pick the post type and when it goes live (for @mid.innings, the match day), add an optional note, and click **Create**. Each click makes one post: an Oban `Produce` job runs Claude, then the renderer, uploads the slides to `content/<key>/`, and writes the manifest `inbox/<key>.json` last, so a manifest always points at complete uploads. The `claude` queue runs one job at a time. The post shows as *In S3*.
2. **Pull.** On **Content**, the *In S3* list shows what's waiting. **Pull all** (or **Pull** on one) turns each manifest into a post that's *Ready to schedule* and removes the manifest. **Delete** removes a manifest and its slides without importing.
3. **Schedule.** Edit the caption and time, then click **Schedule**. That queues an Oban `Publish` job for that time, which hands Instagram 1-hour presigned S3 links. Anything not scheduled by its time is rejected automatically.

Each post has a `content_key` that is the same on every machine. Pulling on the machine that made the post, or pulling a version you regenerated, updates the same post. A post that's already scheduled or live is left alone.

@mid.innings: pick the match day and Create; Claude finds every relevant match that day (up to 6) in one run, and each becomes its own fixture post with its 3 predictions; name a match in the note to make only that one. Each fixture's result post is then added, timed from its match start. After the match, open it and enter both innings (batting team from a dropdown, runs, wickets, overs, best batter and bowler) and the player of the match with their performance. The app works out the winner, the margin and the prediction answers and renders it without Claude. Then Pull it like any other post. A fixture's time is moved to before the first ball if the match starts earlier.

Slots (Channel → Slots) give each post type its default time (the next matching day) and its agent instructions. Nothing is planned or written on its own.

The disk holds no images; only the DB and S3 do. Slides are JPEG at quality 100 (Instagram's API accepts only JPEG), about 500 KB each.

`.env` holds only the S3 settings (`S3_BUCKET`, `AWS_REGION`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`), plus the prod secrets on the server. The current keys belong to the `desirath-app` IAM user; a bucket policy gives it access to this bucket. A dedicated IAM user for this app would be cleaner.

Each channel has a **Dry run** switch: a dry-run channel's scheduled posts are marked published and nothing is sent to Instagram.

## Local setup

```bash
docker compose up -d                      # Postgres 16 on :5432
mix setup                                 # deps, DB, migrations, seeds, assets
(cd renderer && npm install && npx playwright install chromium)
cp .env.example .env                      # add the AWS keys
mix phx.server                            # http://localhost:4000
```

You also need Claude Code installed and logged in (`claude` on PATH). The app strips `ANTHROPIC_API_KEY` from the CLI's environment, so it always runs on your subscription.

### In Docker

The whole app (Elixir release, Node, Chromium and Claude Code) runs on http://localhost:4999, against the dev database and the S3 settings in `.env`:

```bash
docker compose up -d --build app
```

To create content in the container, run `claude setup-token` once on your Mac and add the token to `.env` as `CLAUDE_CODE_OAUTH_TOKEN=…`, then restart with `docker compose up -d app`.

To try a single channel without touching the queue:

```bash
mix agent.try @_motivation2live__ quote
mix agent.try @mid.innings fixture 2026-10-28T12:00
mix agent.try @bollyvibe movie --note "pick a November release"
```

## Admin panel

- **Content** is the main working page. It shows:
  - what's *In S3*, with **Pull all**, **Pull** and **Delete**
  - posts *Ready to schedule*, each with its slides, an editable caption, a date/time picker, and **Schedule** / Reject
  - *Scheduled* posts, which you can move or unschedule
  - failures, with Try again
  - what's being made on this machine
- **This week:** a grid of every channel × 8 days.
- **Channel → Week / Slots / Settings:** **Create** a post, the channel's posts by day, its slots, and its configuration. Each slot has a post type, days, time and agent instructions.
- **Post:** slides, caption (2200-char counter), time, agent notes, sources to fact-check, regenerate with a note, edit the slide JSON (re-renders here), schedule / unschedule / reject / publish now.
- **Jobs:** Oban Web at `/oban`.

## Instagram setup (once)

1. Make sure all five accounts are **Business or Creator** accounts.
2. On developers.facebook.com, create an app and add the **Instagram API with Instagram Login** product. Keep the app in Development mode.
3. Under App roles, add each account as an **Instagram tester**. Accept the invite in Instagram (Settings → Website permissions → Apps and websites).
4. Generate a token for each account in the app dashboard (the long-lived token is valid for 60 days).
5. Paste the token and the Instagram user id into the channel's Settings, then click **Test connection**.
6. Prod refreshes tokens weekly.

Instagram downloads each slide through a presigned S3 link, so neither machine needs a public URL for images.

## Deploying prod

1. On the server: Erlang/Elixir, Postgres, and a reverse proxy with HTTPS for the admin panel (Caddy: `social.example.com { reverse_proxy localhost:4000 }`). Node, Chromium and Claude are only needed if you also want to create posts there.
2. Set env vars:
   - the S3 vars
   - `ADMIN_USER`, `ADMIN_PASSWORD`
   - `CLOAK_KEY` (`openssl rand -base64 32`)
   - `DATABASE_URL`, `SECRET_KEY_BASE`, `PHX_HOST`
3. Build and start:
   ```bash
   MIX_ENV=prod mix do deps.get --only prod, compile, assets.deploy, ecto.migrate
   MIX_ENV=prod mix run priv/repo/seeds.exs
   PHX_SERVER=true MIX_ENV=prod mix phx.server   # or a release under systemd
   ```
4. On the Mac, run `mix phx.server` with the same S3 vars and create posts there. Pull and schedule them on prod. Instagram tokens are set only on prod, which also refreshes them weekly.

## Tests

```bash
mix test
```

The suite covers:
- create → upload → pull, pulling on another machine, stale and deleted manifests, regenerated slides, using the folder storage adapter
- the @mid.innings fixture → result flow
- schedule and reschedule, and the expirer
- Claude CLI parsing and timeout, using a fake binary
- Graph API publishing, using `Req.Test` stubs, and that a dry-run channel never calls Instagram
