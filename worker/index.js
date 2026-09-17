/**
 * Cloudflare Worker port of server.py. Same API contract (/api/state,
 * /api/export, /api/save, /api/import), same validation rules, D1 instead
 * of a local SQLite file, static assets served through the ASSETS binding.
 * Put a Cloudflare Access policy in front of this Worker's route — it does
 * not gate access itself.
 */
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const TIME_RE = /^(?:[01]\d|2[0-3]):[0-5]\d$/;

function isPlainObject(x) { return typeof x === 'object' && x !== null && !Array.isArray(x); }
function isDateStr(s) { if (typeof s !== 'string' || !DATE_RE.test(s)) return false; const d = new Date(s + 'T00:00:00Z'); return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === s; }

function validateRecord(kind, data) {
  if (!isPlainObject(data)) throw new Error('Expected an object.');
  if (kind === 'progress') {
    if (!['new', 'learning', 'solid'].includes(data.status ?? 'new')) throw new Error('Unknown progress status.');
    const checks = data.checks ?? [];
    if (!Array.isArray(checks) || !checks.every(x => Number.isInteger(x) && x >= 0)) throw new Error('Invalid exercise checks.');
    for (const key of ['notes', 'code', 'due', 'updated']) if (key in data && typeof data[key] !== 'string') throw new Error('Invalid progress field: ' + key);
    if ('confidence' in data && !(Number.isInteger(data.confidence) && data.confidence >= 0 && data.confidence <= 3)) throw new Error('Invalid confidence.');
    if ('reviews' in data && !(Number.isInteger(data.reviews) && data.reviews >= 0 && data.reviews <= 100000)) throw new Error('Invalid reviews.');
    if ('quiz' in data && !(Number.isInteger(data.quiz) && data.quiz >= 0 && data.quiz <= 10)) throw new Error('Invalid quiz answer.');
    if (data.due && !isDateStr(data.due)) throw new Error('Invalid deadline date.');
    if (data.time && (typeof data.time !== 'string' || !TIME_RE.test(data.time))) throw new Error('Invalid deadline time.');
    if ('submitted' in data && typeof data.submitted !== 'boolean') throw new Error('Invalid submitted flag.');
    if ('url' in data && typeof data.url !== 'string') throw new Error('Invalid assessment link.');
    if ('priority' in data && !(Number.isInteger(data.priority) && data.priority >= 0 && data.priority <= 3)) throw new Error('Invalid priority.');
    if ('known' in data && typeof data.known !== 'boolean') throw new Error('Invalid known flag.');
    if (data.snoozed && !isDateStr(data.snoozed)) throw new Error('Invalid snooze date.');
    if (data.reviewDue && !isDateStr(data.reviewDue)) throw new Error('Invalid review date.');
  } else if (kind === 'entry') {
    if (!['study', 'error', 'question', 'reflection', 'task'].includes(data.type)) throw new Error('Unknown log type.');
    if (typeof data.text !== 'string' || !data.text.trim()) throw new Error('Write a note before saving.');
    const minutes = data.minutes ?? 0;
    if (!Number.isInteger(minutes) || minutes < 0 || minutes > 1440) throw new Error('Minutes must be between 0 and 1440.');
    if (typeof data.date !== 'string') throw new Error('Date is required.');
    if (!isDateStr(data.date)) throw new Error('Use a valid date.');
    if ('topic' in data && typeof data.topic !== 'string') throw new Error('Invalid topic.');
    if ('resolved' in data && typeof data.resolved !== 'boolean') throw new Error('Invalid resolved flag.');
    if ('detail' in data && typeof data.detail !== 'string') throw new Error('Invalid task details.');
    if (data.category === 'event') {
      for (const key of ['startTime', 'endTime']) if (typeof data[key] !== 'string' || !TIME_RE.test(data[key])) throw new Error('A valid session time is required.');
      if (data.endTime <= data.startTime) throw new Error('Session end must follow start.');
      if (!['once', 'weekly'].includes(data.repeat)) throw new Error('Invalid repeat setting.');
      if (typeof (data.location ?? '') !== 'string') throw new Error('Invalid location.');
      if (!(data.date >= '2026-09-01' && data.date <= '2027-08-31')) throw new Error('Session must be within this academic year.');
      if (data.repeat === 'weekly') {
        if (!isDateStr(data.until)) throw new Error('A valid repeat-until date is required.');
        if (!(data.date <= data.until && data.until <= '2027-08-31')) throw new Error('Repeat-until must be after the first date and within this academic year.');
      }
    }
  } else if (kind === 'settings') {
    if ('dailyMinutes' in data && !(Number.isInteger(data.dailyMinutes) && data.dailyMinutes >= 15 && data.dailyMinutes <= 480)) throw new Error('Daily target must be 15–480 minutes.');
    if ('diagnostic' in data && (!isPlainObject(data.diagnostic) || !Object.values(data.diagnostic).every(v => Number.isInteger(v) && v >= 0 && v <= 3))) throw new Error('Invalid diagnostic scores.');
    if ('priorities' in data && (!isPlainObject(data.priorities) || !Object.values(data.priorities).every(v => Number.isInteger(v) && v >= 0 && v <= 3))) throw new Error('Invalid module priorities.');
    if ('timetableUrl' in data && typeof data.timetableUrl !== 'string') throw new Error('Invalid timetable link.');
  } else {
    throw new Error('Unknown record type.');
  }
  if (JSON.stringify(data).length > 250000) throw new Error('This record is too large.');
  return data;
}

async function readState(db) {
  const result = { version: 1, progress: {}, entries: [], settings: {} };
  const { results } = await db.prepare('SELECT kind,id,payload FROM records ORDER BY rowid').all();
  for (const row of results) {
    const item = JSON.parse(row.payload);
    if (row.kind === 'progress') result.progress[row.id] = item;
    else if (row.kind === 'entry') result.entries.push(item);
    else if (row.kind === 'settings') result.settings = item;
  }
  return result;
}

function json(data, status = 200, extra = {}) {
  return new Response(JSON.stringify(data, null, extra.attachment ? 2 : undefined), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff', ...(extra.attachment ? { 'Content-Disposition': `attachment; filename="${extra.attachment}"` } : {}) },
  });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    try {
      if (request.method === 'GET') {
        if (url.pathname === '/api/state') return json(await readState(env.DB));
        if (url.pathname === '/api/export') {
          const stamp = new Date().toISOString().replace(/[-:]/g, '').replace('T', '-').slice(0, 15);
          return json(await readState(env.DB), 200, { attachment: `study-backup-${stamp}.json` });
        }
        if (url.pathname.startsWith('/api/')) return json({ error: 'Unknown endpoint.' }, 404);
        return env.ASSETS.fetch(request);
      }
      if (request.method === 'POST') {
        const origin = request.headers.get('Origin');
        if (origin && origin !== url.origin) return json({ error: 'Requests must come from this app.' }, 403);
        if ((request.headers.get('Content-Type') || '').split(';')[0] !== 'application/json') return json({ error: 'JSON is required.' }, 415);
        const length = Number(request.headers.get('Content-Length') || '0');
        if (length <= 0 || length > 8_000_000) return json({ error: 'Request is empty or too large.' }, 400);
        let data;
        try { data = await request.json(); } catch { return json({ error: 'Invalid JSON.' }, 400); }
        if (url.pathname === '/api/save') {
          if (!isPlainObject(data)) return json({ error: 'Invalid request.' }, 400);
          let record;
          try { record = validateRecord(data.kind, data.record); } catch (e) { return json({ error: e.message }, 400); }
          let recordId = data.id || (data.kind === 'entry' ? crypto.randomUUID() : 'main');
          if (typeof recordId !== 'string' || recordId.length < 1 || recordId.length > 120) return json({ error: 'Invalid record ID.' }, 400);
          if (data.kind === 'settings') recordId = 'main';
          if (data.kind === 'entry') record.id = recordId;
          record.updated = new Date().toISOString();
          await env.DB.prepare('INSERT INTO records (kind,id,payload) VALUES (?,?,?) ON CONFLICT(kind,id) DO UPDATE SET payload=excluded.payload').bind(data.kind, recordId, JSON.stringify(record)).run();
          return json({ id: recordId, record });
        }
        if (url.pathname === '/api/import') {
          if (!isPlainObject(data) || data.version !== 1) return json({ error: 'This is not a supported study backup.' }, 400);
          if (!isPlainObject(data.progress) || !Array.isArray(data.entries)) return json({ error: 'Backup is missing records.' }, 400);
          try {
            const rows = [];
            for (const [key, record] of Object.entries(data.progress)) {
              if (typeof key !== 'string' || key.length < 1 || key.length > 120) throw new Error('Invalid topic ID.');
              rows.push(['progress', key, JSON.stringify(validateRecord('progress', record))]);
            }
            const ids = new Set();
            for (const record of data.entries) {
              validateRecord('entry', record);
              const key = record.id;
              if (typeof key !== 'string' || key.length < 1 || key.length > 120 || ids.has(key)) throw new Error('Invalid or duplicate log ID.');
              ids.add(key); rows.push(['entry', key, JSON.stringify(record)]);
            }
            rows.push(['settings', 'main', JSON.stringify(validateRecord('settings', data.settings || {}))]);
            const stmts = [env.DB.prepare('DELETE FROM records'), ...rows.map(([kind, id, payload]) => env.DB.prepare('INSERT INTO records (kind,id,payload) VALUES (?,?,?)').bind(kind, id, payload))];
            await env.DB.batch(stmts);
            return json({ ok: true, backup: 'Use `wrangler d1 time-travel` to recover the pre-restore state; D1 has no on-disk backup file here.' });
          } catch (e) { return json({ error: e.message }, 400); }
        }
        return json({ error: 'Unknown endpoint.' }, 404);
      }
      return json({ error: 'Method not allowed.' }, 405);
    } catch (e) {
      return json({ error: 'Storage is unavailable. Your unsaved input is still on this page; try again.' }, 503);
    }
  },
};
