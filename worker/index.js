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

// ---- ranking engine (mirrors dist/portal.js: topicScore/reviewScore/dailyPlan) ----
const dayKey = () => new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/London', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date());
const parseDay = (s) => new Date(s + 'T12:00:00Z');
const plusDays = (s, n) => { const d = parseDay(s); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10); };
function weekDate(sem, w) { if (sem === 1) return plusDays('2026-09-21', (w - 1) * 7); return plusDays('2027-01-25', (w - 1) * 7 + (w > 8 ? 14 : 0)); }
function assessWindow(a) { if (a.id === 'm-exam') return ['2027-05-04', '2027-05-14']; const start = weekDate(a.sem, a.week); return a.day === null ? [start, plusDays(start, 4)] : [plusDays(start, a.day), plusDays(start, a.day)]; }
function progressOf(state, id) { return state.progress[id] || { status: 'new', checks: [], notes: '' }; }
function covered(state, t) { const p = progressOf(state, t.id); const checks = new Set(p.checks || []); return t.content.reduce((n, _, i) => n + (checks.has(i) ? 1 : 0), 0); }
function confidenceOf(state, code) { return (state.settings.diagnostic || {})[code] ?? 1; }
function modPriorityOf(state, code) { return (state.settings.priorities || {})[code] ?? 1; }
function topicConfidenceOf(state, t) { const p = progressOf(state, t.id); return p.confidence ?? confidenceOf(state, t.module); }
function estMinutes(t) { return Math.max(15, Math.min(60, (t.content.length || 3) * 4)); }
function daysUntil(dateStr) { return Math.round((parseDay(dateStr) - parseDay(dayKey())) / 864e5); }
function nextAssessmentFor(plan, state, code) {
  const scored = plan.assessments.filter(a => a.module === code).map(a => { const p = progressOf(state, 'assessment-' + a.id); if (p.submitted) return null; const end = p.due || assessWindow(a)[1]; return { a, date: end }; }).filter(Boolean);
  scored.sort((x, y) => x.date.localeCompare(y.date));
  return scored[0] || null;
}
function allSessions(state, timetable) {
  const events = [...(timetable.events || [])];
  for (const e of state.entries) {
    if (e.category !== 'event' || e.resolved) continue;
    const until = e.repeat === 'weekly' ? e.until : e.date;
    for (let d = e.date, n = 0; d <= until && n < 60; d = plusDays(d, 7), n++) {
      const offset = (d >= '2026-10-25' && d < '2027-03-28') ? '+00:00' : '+01:00';
      events.push({ module: e.topic, start: `${d}T${e.startTime}:00${offset}` });
    }
  }
  return events;
}
function nextSessionFor(state, timetable, code, now) {
  const matches = allSessions(state, timetable).filter(e => e.module === code && e.start >= now).sort((x, y) => x.start.localeCompare(y.start));
  return matches[0] || null;
}
function assessmentBoost(plan, state, timetable, t, score, reason, now) {
  const near = nextAssessmentFor(plan, state, t.module);
  if (near) { const d = daysUntil(near.date); if (d <= 21) { score += d <= 0 ? 42 : Math.max(0, 40 - d * 1.9); reason.push(d <= 0 ? `${near.a.title} deadline has passed — resolve or update it` : `${near.a.title} is due in ${d} day${d === 1 ? '' : 's'}`); } }
  const ns = nextSessionFor(state, timetable, t.module, now);
  if (ns) { const d = Math.floor((new Date(ns.start) - new Date(now)) / 864e5); if (d <= 2) { score += 16; reason.push(`your next ${t.module} session is ${d <= 0 ? 'today' : d === 1 ? 'tomorrow' : 'in ' + d + ' days'}`); } }
  return score;
}
function topicScore(plan, state, timetable, t, now) {
  const p = progressOf(state, t.id);
  if (p.known || p.status === 'solid') return null;
  if (p.snoozed && p.snoozed >= dayKey()) return null;
  const total = t.content.length || 1, done = covered(state, t), gap = 1 - done / total;
  let score = 8 * gap + 2;
  score *= [0.5, 1, 1.4, 2][p.priority ?? 1];
  score *= [0.55, 1, 1.3, 1.7][modPriorityOf(state, t.module)];
  score += [14, 7, 3, 0][topicConfidenceOf(state, t)];
  const reason = [];
  score = assessmentBoost(plan, state, timetable, t, score, reason, now);
  if (done > 0 && done < total) reason.push(`${done} of ${total} content items already covered`);
  else if (done === 0) reason.push('not started yet');
  const pr = p.priority ?? 1;
  if (pr >= 2) reason.push('you flagged this as ' + ['low', 'normal', 'high', 'urgent'][pr].toLowerCase() + ' priority');
  if (topicConfidenceOf(state, t) <= 1) reason.push('you rated your confidence here as low');
  return { topic: t, score, reason, minutes: estMinutes(t), kind: 'learn' };
}
function reviewScore(plan, state, timetable, t, now) {
  const p = progressOf(state, t.id);
  if (p.known || p.status !== 'solid') return null;
  if (!p.reviewDue || p.reviewDue > dayKey()) return null;
  const overdue = daysUntil(p.reviewDue);
  let score = 6 + Math.min(20, Math.max(0, -overdue) * 0.6);
  score *= [0.5, 1, 1.4, 2][p.priority ?? 1];
  score *= [0.55, 1, 1.3, 1.7][modPriorityOf(state, t.module)];
  const reviews = p.reviews || 1;
  const reason = [overdue < 0 ? `review was due ${-overdue} day${overdue === -1 ? '' : 's'} ago` : 'review is due today', `marked solid, reviewed ${reviews} time${reviews === 1 ? '' : 's'}`];
  score = assessmentBoost(plan, state, timetable, t, score, reason, now);
  return { topic: t, score, reason, minutes: Math.max(10, Math.round(estMinutes(t) * 0.4)), kind: 'review' };
}
function bestNext(plan, state, timetable, now, limit = 30) { return plan.topics.map(t => topicScore(plan, state, timetable, t, now)).filter(Boolean).sort((a, b) => b.score - a.score).slice(0, limit); }
function reviewQueue(plan, state, timetable, now, limit = 15) { return plan.topics.map(t => reviewScore(plan, state, timetable, t, now)).filter(Boolean).sort((a, b) => b.score - a.score).slice(0, limit); }
function dailyPlan(plan, state, timetable, now) {
  const budget = state.settings.dailyMinutes || 120;
  const picks = [...bestNext(plan, state, timetable, now), ...reviewQueue(plan, state, timetable, now)].sort((a, b) => b.score - a.score);
  const result = []; let used = 0;
  for (const item of picks) { if (result.length && used + item.minutes > budget) continue; result.push(item); used += item.minutes; if (used >= budget) break; }
  if (!result.length && picks.length) result.push(picks[0]);
  return { plan: result, used, budget };
}
function streakDays(state) {
  const days = new Set(state.entries.filter(e => ['study', 'reflection', 'task'].includes(e.type) && ((e.minutes || 0) > 0 || e.type !== 'task')).map(e => e.date));
  let n = 0, d = dayKey();
  if (!days.has(d)) d = plusDays(d, -1);
  while (days.has(d)) { n++; d = plusDays(d, -1); }
  return n;
}
function weekMinutes(state) {
  const monday = plusDays(dayKey(), -((parseDay(dayKey()).getUTCDay() + 6) % 7));
  return state.entries.filter(e => e.type !== 'task' && e.date >= monday && e.date <= plusDays(monday, 6)).reduce((n, e) => n + (e.minutes || 0), 0);
}
function nextPayload(plan, state, timetable) {
  const now = new Date().toISOString();
  const { plan: picks, used, budget } = dailyPlan(plan, state, timetable, now);
  const ser = (item) => ({ id: item.topic.id, module: item.topic.module, title: item.topic.title, reason: item.reason, minutes: item.minutes, kind: item.kind });
  const done = plan.topics.reduce((n, t) => n + covered(state, t), 0);
  const total = plan.topics.reduce((n, t) => n + t.content.length, 0);
  const openTasks = state.entries.filter(e => e.type === 'task' && !e.resolved && e.category !== 'event').length;
  return { generatedAt: now, top: picks[0] ? ser(picks[0]) : null, plan: picks.map(ser), planUsedMinutes: used, dailyTarget: budget, streak: streakDays(state), weekMinutes: weekMinutes(state), coverage: { done, total }, openTasks };
}

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
        if (url.pathname === '/api/next') {
          const state = await readState(env.DB);
          const [planRes, timetableRes] = await Promise.all([
            env.ASSETS.fetch(new Request(url.origin + '/plan.json')),
            env.ASSETS.fetch(new Request(url.origin + '/timetable.json')),
          ]);
          const plan = await planRes.json();
          const timetable = await timetableRes.json();
          return json(nextPayload(plan, state, timetable));
        }
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
