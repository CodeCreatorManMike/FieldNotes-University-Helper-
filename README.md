# Field Notes University Helper
An ambient macOS companion that reads your calendar and coursework, then decides — not just displays — what you should be doing right now.

## Running locally on your Mac

Double-click `Start Study Portal.command`, or:

```bash
python3 server.py
```

Open http://127.0.0.1:8765/. Data lives in `storage/study.sqlite3`, never leaves the machine.

## The island (macOS menu-bar-free companion)

`mac/FieldnotesIsland` is a small native Swift app that lives at the top-left corner of your screen — not in the Dock, not in the menu bar.

**Always on:** a small colored pill sits docked in the corner at all times — its dot is green when you're on track, amber when something's due in a day or two, red when a deadline's passed or due today. Glanceable state without opening anything.

**Hover to expand:** move your mouse to the top-left edge (or onto the pill itself) and it grows into a glass panel: the six main pages (Today, Modules, Week, Tasks, Journal, Settings) as one-click links into the web app, plus a live "up next" card — same priority/deadline/calendar-aware ranking engine as the web app's `#focus` queue, hover it for the full reasoning. Below that: today's coverage, day streak, and a progress bar against your daily minutes target. Move away and it shrinks back to the pill.

**Act without leaving the panel:** "Snooze 2d" and "Know it" on the up-next card call the same `/api/save` endpoint the web app uses (fetching and merging the current record first, same as `portal.js` does — the server replaces whole records, it doesn't merge). A "Quick add a task…" field at the bottom does the same for new tasks. Right-click anywhere on the pill or panel for Refresh now / Launch at login / Quit.

**Notifications:** best-effort local alerts (needs the `.app` bundle below — a loose binary can't reliably get notification authorization) for a deadline that's passed or due within a day, and once when you hit your daily minutes target. Each fires once per state, not once per 45-second poll.

It talks to the same local server as the web app, over `/api/next` (`server.py`) — a single JSON endpoint summarising the ranked queue, today's plan, streak and coverage, so the island doesn't need to reimplement the web UI. Nothing here reads your screen or any other app; it only polls your mouse position (no Accessibility permission needed) and calls local HTTP endpoints already used by the web UI.

Run it:
```bash
cd mac/FieldnotesIsland
swift run                      # debug build, quits when you close the terminal
# or, for the real thing — an actual double-clickable app, notifications and
# login-item support all need this instead of the loose binary above:
./build.sh                      # builds FieldnotesIsland.app
open FieldnotesIsland.app
```

Launch at login is built in now — right-click the pill or panel → "Launch at login" (uses `SMAppService`, macOS 13+; only works from the `.app` bundle). `com.fieldnotes.island.plist` is still here as a manual `launchctl` fallback if you'd rather not rely on that:
```bash
launchctl load ~/Library/LaunchAgents/com.fieldnotes.island.plist   # after copying it there and fixing the path
```

Point it at a different backend (e.g. a deployed Cloudflare Worker, once you're using one — see below) by setting `FIELDNOTES_URL` before launching, or in the plist's `EnvironmentVariables`:
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
