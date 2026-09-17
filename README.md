# Field Notes University Helper
An ambient macOS companion that reads your calendar and coursework, then decides — not just displays — what you should be doing right now.

Three things live in this repo, all talking to the same data:
- **The web app** (`dist/` + `server.py`) — the full organiser: modules, week planner, tasks, journal, source library, settings.
- **The island** (`mac/FieldnotesIsland`) — a native macOS presence that's always on screen, showing the single most important thing to do right now without opening anything.
- **A Cloudflare Worker** (`worker/`) — optional, makes the same thing reachable from your phone.

## Running the web app locally

Double-click `Start Study Portal.command`, or:

```bash
python3 server.py
```

Open http://127.0.0.1:8765/. Data lives in `storage/study.sqlite3`, never leaves the machine.

### How "what's next" gets decided

Every topic gets a score from: its coverage gap (how much of it you haven't ticked off), a priority you can set per-topic and per-module, how confident you've rated yourself in that module (or that specific topic — an override), and how close its linked assessment deadline or next timetabled session is. Marking a topic solid schedules a spaced review (1/3/7/16/35/60/90 days later) that resurfaces it separately from new learning. The whole thing is one function, `dailyPlan()` in `dist/portal.js`, mirrored in `server.py` (`next_payload`) and `worker/index.js` (`nextPayload`) so the web UI, the island, and a deployed Worker all agree on the same answer. See `#focus` in the web app for the full ranked queue, or the "Calibrate this module" panel on any module page to tune it.

### Local snapshots vs. real Moodle pages

Most content in here (module guides, lecture notes, past papers) is a local text extract in `dist/sources/` — captured once, works offline, but goes stale and can't be logged into. The INDUCTION module page also has a "Live on Moodle" panel that links to actual hosted pages (the placements/opportunities course, its forum, Panopto recordings) instead of a snapshot — those came from a HAR capture of a real Moodle session (`dist/plan.js`, `INDUCTION.liveLinks`). To add real links for another module: log into Moodle, open dev tools → Network, browse the module's course page, export as HAR, then pull out the `mod/`/`course/` URLs the same way (see the git history on that file for the exact approach).

## The island (always-on macOS presence)

`mac/FieldnotesIsland` is a native Swift app — no Dock icon, no menu bar item, no window you can accidentally lose.

**Idle: a ring, top-right.** A small ring sits docked in the corner permanently. It fills as today's plan fills (minutes done / your daily target), colored green/amber/red by urgency (an assessment overdue or due today turns it red). Hover it for a native tooltip with the top task; click it to open that task; it's never in your way and never invisible — solid black disc + white mark, not a translucent material that can blend into the desktop behind it.

**Hover the top-right edge (or the ring) to expand** into a solid black panel: "MOST IMPORTANT RIGHT NOW" leads, large and legible, with an animated progress ring next to your coverage/streak/open-task stats, then the six pages (Today, Modules, Week, Tasks, Journal, Settings) as one-click links into the web app. Move away and it shrinks back to the ring.

**Act without leaving the panel:** "Snooze 2d" and "Know it" on the up-next card, and a "Quick add a task…" field, all call the same `/api/save` endpoint the web app uses — fetching and merging the current record first, since the server replaces whole records rather than merging them (same pattern `portal.js`'s own `save()` uses). Right-click the ring or panel for Refresh now / Launch at login / Quit.

**Notifications:** best-effort local alerts for a deadline that's passed or due within a day, and once when you hit your daily minutes target — each fires once per state, not once per 45-second poll. Needs the `.app` bundle (below) to actually get authorized.

It talks to the same server as the web app over one endpoint, `/api/next` — a JSON summary of the ranked queue, today's plan, streak and coverage. Nothing here reads your screen or any other app: it only polls your own mouse position (no Accessibility permission needed) and calls local HTTP endpoints the web UI already uses.

### Run it

```bash
cd mac/FieldnotesIsland
swift run                # debug build, quits when you close the terminal — fastest way to test a change
# for the real thing — notifications and login-item support need this, not the loose binary above:
./build.sh                # builds FieldnotesIsland.app
open FieldnotesIsland.app
```

**Auto-start at login** (so you don't have to re-launch it every time you're iterating on it):
```bash
mkdir -p ~/Library/LaunchAgents
sed "s#/Users/YOUR_USERNAME/Downloads/Oxford_Brookes_CLI_correct/FieldNotes#$PWD/../..#" \
  mac/FieldnotesIsland/com.fieldnotes.island.plist > ~/Library/LaunchAgents/com.fieldnotes.island.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.fieldnotes.island.plist
```
(run the `sed`/`launchctl` lines from the repo root). To pick up a change after rebuilding: `launchctl kickstart -k gui/$(id -u)/com.fieldnotes.island`. To stop it starting automatically: `launchctl bootout gui/$(id -u)/com.fieldnotes.island`. There's also a right-click → "Launch at login" toggle in the app itself (`SMAppService`) if you'd rather not touch `launchctl` directly — same effect, only works from the `.app` bundle.

Point it at a different backend (e.g. a deployed Cloudflare Worker, once you're using one — see below) via `FIELDNOTES_URL`, either before launching or in the plist's `EnvironmentVariables`:
```bash
FIELDNOTES_URL=https://your-worker.workers.dev swift run
```

## Deploying to Cloudflare (so it works from your phone too)

`worker/index.js` is a byte-for-byte port of `server.py`'s API (`/api/state`, `/api/save`, `/api/import`, `/api/export`, `/api/next`, same validation rules and same ranking engine) running on a Cloudflare Worker, serving `dist/` as static assets and storing records in D1 instead of local SQLite. The Mac app and the island above keep working unchanged — this is a separate, optional deployment, and the island can point at it instead of localhost via `FIELDNOTES_URL` once it's live, so the same "what should I be doing" view works from anywhere, not just this Mac.

1. Install the CLI and log in:
   ```bash
   npm install
   npx wrangler login
   ```
2. Create the D1 database and copy its `database_id` into `wrangler.toml`:
   ```bash
   npx wrangler d1 create fieldnotes
   ```
3. Apply the schema:
   ```bash
   npm run db:migrate:remote
   ```
4. Deploy:
   ```bash
   npm run deploy
   ```

Try it locally first with `npm run dev` (runs against a local D1 instance, no Cloudflare account needed) and `npm run db:migrate:local` to seed the schema there.

### Lock it down

This app holds your timetable, tasks and assessment notes — once deployed it's reachable by URL from anywhere. Put it behind **Cloudflare Access** before sharing the link with yourself:

1. Cloudflare dashboard → Zero Trust → Access → Applications → Add an application → Self-hosted.
2. Point it at your Worker's route/domain.
3. Add a policy allowing only your own email (one-time PIN login, or your existing identity provider).

The Worker itself does no authentication — Access sits in front of it and is free for individual use.
