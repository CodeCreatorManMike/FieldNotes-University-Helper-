# Field Notes University Helper
An ambient macOS companion that reads your calendar and coursework, then decides — not just displays — what you should be doing right now.

## Running locally on your Mac

Double-click `Start Study Portal.command`, or:

```bash
python3 server.py
```

Open http://127.0.0.1:8765/. Data lives in `storage/study.sqlite3`, never leaves the machine.

## Deploying to Cloudflare (so it works from your phone too)

`worker/index.js` is a byte-for-byte port of `server.py`'s API (`/api/state`, `/api/save`, `/api/import`, `/api/export`, same validation rules) running on a Cloudflare Worker, serving `dist/` as static assets and storing records in D1 instead of local SQLite. The Mac app above keeps working unchanged — this is a separate, optional deployment.

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
