# Content desk

Phoenix LiveView app that plans, writes, renders, reviews and publishes posts for five Instagram channels:
@spotlight.startups, @puree_heartz, @_motivation2live__, @mid.innings and @bollyvibe.

- **Writing** uses the local Claude Code CLI (`claude -p`) on your subscription, so no API key is needed. There is one agent with one skill per channel (`agent/.claude/skills/*`) and a JSON schema per channel (`agent/schemas/*`).
- **Rendering** uses the channel studios (`channels/<dir>/template.html`), driven by Playwright through `renderer/render.js`. It produces 1080×1350 JPEGs at quality 100 plus the caption. The JPEGs are stored in S3.
- **Publishing** goes straight to the Instagram Graph API (Instagram API with Instagram Login).
- **Only scheduled posts go live.** The admin reviews each post in **Content**, edits the caption and time, and schedules it. Anything not scheduled by its time is rejected.

## How the pieces fit

Prod and your Mac never connect to each other. Everything goes through the private S3 bucket **`socialmedia-dravya`** (ap-south-1), under a prefix per environment (`prod/`, `dev/`).

```
   PROD (PRIMARY=true PUBLISH=true)             S3 socialmedia-dravya/<prefix>/            MAC (PRIMARY=false CONTENT=true)
 ┌──────────────────────────────┐                                                       ┌──────────────────────────────┐
 │ Planner: 7 days of slots     │── every 2 min ──▶ plan.json ──── every 3 min ────────▶│ ContentPoller reads plan     │
 │ SyncBus: import + plan       │                                                       │ Produce: claude -p → data    │
 │ Content list: edit, schedule │◀── import ────── inbox/<id>-<rev>.json ◀── upload ────│          render.js → JPEG q100│
 │ Publish → Instagram API      │── presigned URL ▶ content/<id>/<rev>/*.jpg ◀──────────│                              │
 │ Expirer: drop unscheduled    │                                                       └──────────────────────────────┘
 └──────────────────────────────┘
```

1. **Prod** plans posts from the slots and writes `plan.json`: every post whose writing time has come, plus re-render requests. Each one carries its `gen_rev`.
2. **The Mac** reads `plan.json` and runs Claude and the renderer for each item it hasn't delivered yet. It uploads the slides to `content/<post_id>/<rev>/` byte for byte, then writes `inbox/<post_id>-<rev>.json`. That manifest is written last, so it always points at complete uploads.
3. **Prod** imports the inbox. The post becomes *Ready to schedule*, and the slides of the previous revision are deleted. A manifest for an old revision (because you regenerated in the meantime) is discarded.
4. **The admin** opens **Content**, edits the caption and post time, and clicks **Schedule**. Publish runs at that time and hands Instagram 1-hour presigned S3 links. Anything not scheduled by its time is rejected automatically.

Prod's disk holds no images; only the DB and S3 do. Slides are JPEG at quality 100 (Instagram's API accepts only JPEG), about 500 KB each.

### Role flags (`.env`, see `.env.example`)

| Variable | Dev (one machine) | Mac → prod | Prod |
|---|---|---|---|
| `PRIMARY` (planner, sync import, admin, expirer) | `true` | `false` | `true` |
| `CONTENT` (Claude + renderer) | `true` | `true` | `false` |
| `PUBLISH` (post to Instagram) | `false` | `false` | `true` |
| `S3_PREFIX` | `dev` | `prod` | `prod` |

With `PUBLISH=false`, scheduled posts are marked published as a dry run and nothing is sent. Each channel also has its own **Dry run** switch.

S3 needs `S3_BUCKET`, `AWS_REGION`, `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` on both machines. The current keys belong to the `desirath-app` IAM user; a bucket policy gives it access to this bucket. A dedicated IAM user for this app would be cleaner.

## Local setup

```bash
docker compose up -d                      # Postgres 16 on :5432
mix setup                                 # deps, DB, migrations, seeds, assets
(cd renderer && npm install && npx playwright install chromium)
cp .env.example .env                      # PRIMARY+CONTENT, PUBLISH=false, S3_PREFIX=dev, add AWS keys
mix phx.server                            # http://localhost:4000
```

You also need Claude Code installed and logged in (`claude` on PATH). The app strips `ANTHROPIC_API_KEY` from the CLI's environment, so it always runs on your subscription.

To try a single channel without touching the queue:

```bash
mix agent.try @_motivation2live__ quote
mix agent.try @mid.innings fixture 2026-10-28T12:00
mix agent.try @bollyvibe movie --note "pick a November release"
```

## Admin panel

- **Content** is the main working page. It shows:
  - posts *Ready to schedule*, each with its slides, an editable caption, a date/time picker, and **Schedule** / Reject
  - *Scheduled* posts, which you can move or unschedule
  - failures, with Try again
  - what's still waiting for the Mac
- **This week:** a grid of every channel × 8 days.
- **Channel → Week / Slots / Settings:** the channel's posts by day, its posting slots, and its configuration. Each slot has a post type, days, time, how many hours ahead it's written, and agent instructions.
- **Post:** slides, caption (2200-char counter), time, agent notes, sources to fact-check, regenerate with a note, edit the slide JSON (the Mac re-renders), schedule / unschedule / reject / publish now.
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

1. On the server: Erlang/Elixir, Postgres, and a reverse proxy with HTTPS for the admin panel (Caddy: `social.example.com { reverse_proxy localhost:4000 }`). Node, Chromium and Claude are **not** needed.
2. Set env vars:
   - `PRIMARY=true`, `CONTENT=false`, `PUBLISH=true`, `S3_PREFIX=prod`
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
4. On the Mac, set `PRIMARY=false CONTENT=true PUBLISH=false S3_PREFIX=prod` and run `mix phx.server`. From then on the Mac only makes content; you review and schedule on prod.

## Tests

```bash
mix test
```

The suite covers:
- planning (timezones, idempotency, re-plan)
- the S3 bus (plan → deliver → import, stale revisions, skips, re-render cleanup), using the folder storage adapter
- schedule and reschedule, and the expirer
- Claude CLI parsing and timeout, using a fake binary
- Graph API publishing, using `Req.Test` stubs
- the guarantee that `PUBLISH=false` never calls Instagram
