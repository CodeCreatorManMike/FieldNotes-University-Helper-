#!/usr/bin/env python3
"""Local study portal. Standard-library only; records live in SQLite."""
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from urllib.parse import urlparse, unquote
from datetime import datetime, date, timedelta, timezone
from zoneinfo import ZoneInfo
import argparse
import json
import mimetypes
import sqlite3
import uuid
import re

ROOT = Path(__file__).resolve().parent
STATIC = ROOT / 'dist'
DATA = ROOT / 'storage'
LONDON = ZoneInfo('Europe/London')
PLAN = json.loads((ROOT / 'data' / 'plan.json').read_text())
TIMETABLE = json.loads((STATIC / 'timetable.json').read_text())

def connect():
    db = sqlite3.connect(DATA / 'study.sqlite3', timeout=10)
    db.row_factory = sqlite3.Row
    return db

def initialize():
    DATA.mkdir(parents=True, exist_ok=True)
    with connect() as db:
        db.execute('PRAGMA journal_mode=WAL')
        db.execute('CREATE TABLE IF NOT EXISTS records (kind TEXT NOT NULL, id TEXT NOT NULL, payload TEXT NOT NULL, PRIMARY KEY(kind,id))')

def state():
    result = {'version': 1, 'progress': {}, 'entries': [], 'settings': {}}
    with connect() as db:
        for row in db.execute('SELECT kind,id,payload FROM records ORDER BY rowid'):
            item = json.loads(row['payload'])
            if row['kind'] == 'progress': result['progress'][row['id']] = item
            elif row['kind'] == 'entry': result['entries'].append(item)
            elif row['kind'] == 'settings': result['settings'] = item
    return result

def validate_record(kind, data):
    if not isinstance(data, dict): raise ValueError('Expected an object.')
    if kind == 'progress':
        if data.get('status', 'new') not in ('new', 'learning', 'solid'): raise ValueError('Unknown progress status.')
        if not isinstance(data.get('checks', []), list) or not all(isinstance(x, int) and not isinstance(x, bool) and x >= 0 for x in data.get('checks', [])): raise ValueError('Invalid exercise checks.')
        for key in ('notes', 'code', 'due', 'updated'):
            if key in data and not isinstance(data[key], str): raise ValueError('Invalid progress field: ' + key)
        if 'confidence' in data and (type(data['confidence']) is not int or not 0 <= data['confidence'] <= 3): raise ValueError('Invalid confidence.')
        if 'reviews' in data and (type(data['reviews']) is not int or not 0 <= data['reviews'] <= 100000): raise ValueError('Invalid reviews.')
        if 'quiz' in data and (type(data['quiz']) is not int or not 0 <= data['quiz'] <= 10): raise ValueError('Invalid quiz answer.')
        if data.get('due'):
            try: datetime.strptime(data['due'], '%Y-%m-%d')
            except ValueError: raise ValueError('Invalid deadline date.')
        if data.get('time') and (not isinstance(data['time'], str) or not re.fullmatch(r'(?:[01]\d|2[0-3]):[0-5]\d', data['time'])): raise ValueError('Invalid deadline time.')
        if 'submitted' in data and type(data['submitted']) is not bool: raise ValueError('Invalid submitted flag.')
        if 'url' in data and not isinstance(data['url'], str): raise ValueError('Invalid assessment link.')
        if 'priority' in data and (type(data['priority']) is not int or not 0 <= data['priority'] <= 3): raise ValueError('Invalid priority.')
        if 'known' in data and type(data['known']) is not bool: raise ValueError('Invalid known flag.')
        if data.get('snoozed'):
            try: datetime.strptime(data['snoozed'], '%Y-%m-%d')
            except ValueError: raise ValueError('Invalid snooze date.')
        if data.get('reviewDue'):
            try: datetime.strptime(data['reviewDue'], '%Y-%m-%d')
            except ValueError: raise ValueError('Invalid review date.')
    elif kind == 'entry':
        if data.get('type') not in ('study', 'error', 'question', 'reflection', 'task'): raise ValueError('Unknown log type.')
        if not isinstance(data.get('text'), str) or not data['text'].strip(): raise ValueError('Write a note before saving.')
        if type(data.get('minutes', 0)) is not int or not 0 <= data.get('minutes', 0) <= 1440: raise ValueError('Minutes must be between 0 and 1440.')
        if not isinstance(data.get('date'), str): raise ValueError('Date is required.')
        try: datetime.strptime(data['date'], '%Y-%m-%d')
        except ValueError: raise ValueError('Use a valid date.')
        if 'topic' in data and not isinstance(data['topic'], str): raise ValueError('Invalid topic.')
        if 'resolved' in data and not isinstance(data['resolved'], bool): raise ValueError('Invalid resolved flag.')
        if 'detail' in data and not isinstance(data['detail'],str): raise ValueError('Invalid task details.')
        if data.get('category') == 'event':
            for key in ('startTime','endTime'):
                if not isinstance(data.get(key),str) or not re.fullmatch(r'(?:[01]\d|2[0-3]):[0-5]\d',data[key]): raise ValueError('A valid session time is required.')
            if data['endTime'] <= data['startTime']: raise ValueError('Session end must follow start.')
            if data.get('repeat') not in ('once','weekly'): raise ValueError('Invalid repeat setting.')
            if not isinstance(data.get('location',''),str): raise ValueError('Invalid location.')
            if not '2026-09-01' <= data['date'] <= '2027-08-31': raise ValueError('Session must be within this academic year.')
            if data['repeat'] == 'weekly':
                try: datetime.strptime(data.get('until',''), '%Y-%m-%d')
                except (TypeError,ValueError): raise ValueError('A valid repeat-until date is required.')
                if not data['date'] <= data['until'] <= '2027-08-31': raise ValueError('Repeat-until must be after the first date and within this academic year.')
    elif kind == 'settings':
        if 'dailyMinutes' in data and (type(data['dailyMinutes']) is not int or not 15 <= data['dailyMinutes'] <= 480): raise ValueError('Daily target must be 15–480 minutes.')
        if 'diagnostic' in data and (not isinstance(data['diagnostic'], dict) or not all(type(v) is int and 0 <= v <= 3 for v in data['diagnostic'].values())): raise ValueError('Invalid diagnostic scores.')
        if 'priorities' in data and (not isinstance(data['priorities'], dict) or not all(type(v) is int and 0 <= v <= 3 for v in data['priorities'].values())): raise ValueError('Invalid module priorities.')
        if 'timetableUrl' in data and not isinstance(data['timetableUrl'],str): raise ValueError('Invalid timetable link.')
    else: raise ValueError('Unknown record type.')
    if len(json.dumps(data)) > 250000: raise ValueError('This record is too large.')
    return data

# ---- ranking engine (mirrors dist/portal.js: topicScore/reviewScore/dailyPlan) ----
# Kept in sync by hand; data/plan.json is generated once from dist/plan.js and rarely
# needs regenerating (only when modules/topics/assessments change), via:
#   node -e "global.window={};eval(require('fs').readFileSync('dist/plan.js','utf8'));require('fs').writeFileSync('data/plan.json',JSON.stringify(window.PLAN))"

def today_str(): return datetime.now(LONDON).strftime('%Y-%m-%d')
def parse_d(s): return date.fromisoformat(s)
def plus_days(s, n): return (parse_d(s) + timedelta(days=n)).isoformat()
def monday_of(s):
    d = parse_d(s)
    return (d - timedelta(days=d.weekday())).isoformat()

def week_date(sem, w):
    if sem == 1: return plus_days('2026-09-21', (w - 1) * 7)
    return plus_days('2027-01-25', (w - 1) * 7 + (14 if w > 8 else 0))

def assess_window(a):
    if a['id'] == 'm-exam': return ('2027-05-04', '2027-05-14')
    start = week_date(a['sem'], a['week'])
    if a.get('day') is None: return (start, plus_days(start, 4))
    return (plus_days(start, a['day']), plus_days(start, a['day']))

def topic_progress(state, tid): return state['progress'].get(tid, {'status': 'new', 'checks': [], 'notes': ''})
def covered(state, t):
    checks = set(topic_progress(state, t['id']).get('checks') or [])
    return sum(1 for i in range(len(t['content'])) if i in checks)
def confidence(state, code): return (state['settings'].get('diagnostic') or {}).get(code, 1)
def mod_priority(state, code): return (state['settings'].get('priorities') or {}).get(code, 1)
def topic_confidence(state, t):
    p = topic_progress(state, t['id'])
    return p['confidence'] if p.get('confidence') is not None else confidence(state, t['module'])
def est_minutes(t): return max(15, min(60, (len(t['content']) or 3) * 4))

def next_assessment_for(state, code):
    best = None
    for a in PLAN['assessments']:
        if a['module'] != code: continue
        p = topic_progress(state, 'assessment-' + a['id'])
        if p.get('submitted'): continue
        end = p['due'] if p.get('due') else assess_window(a)[1]
        if best is None or end < best[1]: best = (a, end)
    return best

def all_sessions(state):
    events = list(TIMETABLE.get('events', []))
    for e in state['entries']:
        if e.get('category') != 'event' or e.get('resolved'): continue
        until = e['until'] if e.get('repeat') == 'weekly' else e['date']
        cur, n = e['date'], 0
        while cur <= until and n < 60:
            offset = '+00:00' if '2026-10-25' <= cur < '2027-03-28' else '+01:00'
            events.append({'module': e.get('topic'), 'start': f"{cur}T{e['startTime']}:00{offset}"})
            cur, n = plus_days(cur, 7), n + 1
    return events

def next_session_for(state, code, now):
    matches = sorted((e for e in all_sessions(state) if e.get('module') == code and e['start'] >= now), key=lambda e: e['start'])
    return matches[0] if matches else None

def assessment_boost(state, t, score, reason, now):
    near = next_assessment_for(state, t['module'])
    if near:
        a, end = near
        d = (parse_d(end) - parse_d(today_str())).days
        if d <= 21:
            score += 42 if d <= 0 else max(0, 40 - d * 1.9)
            reason.append(f"{a['title']} deadline has passed — resolve or update it" if d <= 0 else f"{a['title']} is due in {d} day{'' if d == 1 else 's'}")
    ns = next_session_for(state, t['module'], now)
    if ns:
        d = (datetime.fromisoformat(ns['start']) - datetime.now(LONDON)).days
        if d <= 2:
            score += 16
            reason.append(f"your next {t['module']} session is " + ('today' if d <= 0 else 'tomorrow' if d == 1 else f'in {d} days'))
    return score

def topic_score(state, t, now):
    p = topic_progress(state, t['id'])
    if p.get('known') or p.get('status') == 'solid': return None
    if p.get('snoozed') and p['snoozed'] >= today_str(): return None
    total = len(t['content']) or 1
    done = covered(state, t)
    gap = 1 - done / total
    score = 8 * gap + 2
    score *= [0.5, 1, 1.4, 2][p.get('priority', 1)]
    score *= [0.55, 1, 1.3, 1.7][mod_priority(state, t['module'])]
    score += [14, 7, 3, 0][topic_confidence(state, t)]
    reason = []
    score = assessment_boost(state, t, score, reason, now)
    if 0 < done < total: reason.append(f"{done} of {total} content items already covered")
    elif done == 0: reason.append('not started yet')
    pr = p.get('priority', 1)
    if pr >= 2: reason.append('you flagged this as ' + ['low', 'normal', 'high', 'urgent'][pr].lower() + ' priority')
    if topic_confidence(state, t) <= 1: reason.append('you rated your confidence here as low')
    return {'topic': t, 'score': score, 'reason': reason, 'minutes': est_minutes(t), 'kind': 'learn'}

def review_score(state, t, now):
    p = topic_progress(state, t['id'])
    if p.get('known') or p.get('status') != 'solid': return None
    if not p.get('reviewDue') or p['reviewDue'] > today_str(): return None
    overdue = (parse_d(p['reviewDue']) - parse_d(today_str())).days
    score = 6 + min(20, max(0, -overdue) * 0.6)
    score *= [0.5, 1, 1.4, 2][p.get('priority', 1)]
    score *= [0.55, 1, 1.3, 1.7][mod_priority(state, t['module'])]
    reviews = p.get('reviews', 1)
    reason = [(f"review was due {-overdue} day{'' if overdue == -1 else 's'} ago" if overdue < 0 else 'review is due today'),
              f"marked solid, reviewed {reviews} time{'' if reviews == 1 else 's'}"]
    score = assessment_boost(state, t, score, reason, now)
    return {'topic': t, 'score': score, 'reason': reason, 'minutes': max(10, round(est_minutes(t) * 0.4)), 'kind': 'review'}

def best_next(state, now, limit=30):
    out = [r for r in (topic_score(state, t, now) for t in PLAN['topics']) if r]
    out.sort(key=lambda r: -r['score'])
    return out[:limit]

def review_queue(state, now, limit=15):
    out = [r for r in (review_score(state, t, now) for t in PLAN['topics']) if r]
    out.sort(key=lambda r: -r['score'])
    return out[:limit]

def daily_plan(state, now):
    budget = state['settings'].get('dailyMinutes', 120)
    picks = best_next(state, now) + review_queue(state, now)
    picks.sort(key=lambda r: -r['score'])
    plan, used = [], 0
    for item in picks:
        if plan and used + item['minutes'] > budget: continue
        plan.append(item); used += item['minutes']
        if used >= budget: break
    if not plan and picks: plan.append(picks[0])
    return plan, used, budget

def streak_days(state):
    days = {e['date'] for e in state['entries'] if e.get('type') in ('study', 'reflection', 'task') and ((e.get('minutes', 0) or 0) > 0 or e.get('type') != 'task')}
    n, d = 0, today_str()
    if d not in days: d = plus_days(d, -1)
    while d in days: n += 1; d = plus_days(d, -1)
    return n

def week_minutes(state):
    start = monday_of(today_str())
    return sum(e.get('minutes', 0) or 0 for e in state['entries'] if e.get('type') != 'task' and start <= e.get('date', '') <= plus_days(start, 6))

def next_payload(state):
    now = datetime.now(LONDON).isoformat()
    plan, used, budget = daily_plan(state, now)
    def ser(item):
        t = item['topic']
        return {'id': t['id'], 'module': t['module'], 'title': t['title'], 'reason': item['reason'], 'minutes': item['minutes'], 'kind': item['kind']}
    done = sum(covered(state, t) for t in PLAN['topics'])
    total = sum(len(t['content']) for t in PLAN['topics'])
    open_tasks = sum(1 for e in state['entries'] if e.get('type') == 'task' and not e.get('resolved') and e.get('category') != 'event')
    return {
        'generatedAt': now,
        'top': ser(plan[0]) if plan else None,
        'plan': [ser(i) for i in plan],
        'planUsedMinutes': used,
        'dailyTarget': budget,
        'streak': streak_days(state),
        'weekMinutes': week_minutes(state),
        'coverage': {'done': done, 'total': total},
        'openTasks': open_tasks,
    }

class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        if args and str(args[1] if len(args) > 1 else '').startswith(('4','5')): super().log_message(fmt, *args)

    def valid_host(self):
        return self.headers.get('Host') in (f'127.0.0.1:{self.server.server_port}', f'localhost:{self.server.server_port}')

    def respond(self, status, data, attachment=None):
        content = json.dumps(data, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header('Content-Type','application/json; charset=utf-8')
        self.send_header('Content-Length',str(len(content)))
        self.send_header('Cache-Control','no-store')
        self.send_header('X-Content-Type-Options','nosniff')
        if attachment: self.send_header('Content-Disposition',f'attachment; filename="{attachment}"')
        self.end_headers()
        self.wfile.write(content)

    def do_GET(self):
        if not self.valid_host(): return self.respond(403, {'error':'Open the portal using its localhost address.'})
        path = urlparse(self.path).path
        try:
            if path == '/api/state': return self.respond(200,state())
            if path == '/api/next': return self.respond(200,next_payload(state()))
            if path == '/api/export': return self.respond(200,state(), 'study-backup-'+datetime.now().strftime('%Y%m%d-%H%M%S')+'.json')
            if path.startswith('/api/'): return self.respond(404,{'error':'Unknown endpoint.'})
            file = (STATIC / unquote(path).lstrip('/')).resolve() if path != '/' else STATIC / 'index.html'
            if not file.is_relative_to(STATIC.resolve()) or not file.is_file(): return self.respond(404,{'error':'File not found.'})
            content = file.read_bytes()
            self.send_response(200)
            self.send_header('Content-Type',(mimetypes.guess_type(str(file))[0] or 'application/octet-stream') + ('; charset=utf-8' if file.suffix in ('.html','.js','.css','.txt','.json') else ''))
            self.send_header('Content-Length',str(len(content)))
            self.send_header('Cache-Control','no-cache')
            self.send_header('X-Content-Type-Options','nosniff')
            self.send_header('Content-Security-Policy',"default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'")
            self.end_headers(); self.wfile.write(content)
        except (sqlite3.Error, OSError): self.respond(503,{'error':'Storage is unavailable. Your unsaved input is still on this page; try again.'})

    def do_POST(self):
        if not self.valid_host(): return self.respond(403,{'error':'Invalid host.'})
        origin = self.headers.get('Origin')
        if origin and origin not in (f'http://127.0.0.1:{self.server.server_port}',f'http://localhost:{self.server.server_port}'):
            return self.respond(403,{'error':'Requests must come from the local portal.'})
        if self.headers.get('Content-Type','').split(';')[0] != 'application/json': return self.respond(415,{'error':'JSON is required.'})
        try:
            length = int(self.headers.get('Content-Length','0'))
            if length <= 0 or length > 8_000_000: raise ValueError('Request is empty or too large.')
            data = json.loads(self.rfile.read(length))
            path = urlparse(self.path).path
            if path == '/api/save':
                if not isinstance(data,dict): raise ValueError('Invalid request.')
                kind = data.get('kind'); record = validate_record(kind,data.get('record'))
                record_id = data.get('id') or (str(uuid.uuid4()) if kind == 'entry' else 'main')
                if not isinstance(record_id,str) or not 1 <= len(record_id) <= 120: raise ValueError('Invalid record ID.')
                if kind == 'settings': record_id = 'main'
                if kind == 'entry': record['id'] = record_id
                record['updated'] = datetime.now(timezone.utc).isoformat()
                with connect() as db: db.execute('INSERT INTO records VALUES (?,?,?) ON CONFLICT(kind,id) DO UPDATE SET payload=excluded.payload',(kind,record_id,json.dumps(record)))
                return self.respond(200,{'id':record_id,'record':record})
            if path == '/api/import':
                if not isinstance(data,dict) or data.get('version') != 1: raise ValueError('This is not a supported study backup.')
                if not isinstance(data.get('progress'),dict) or not isinstance(data.get('entries'),list): raise ValueError('Backup is missing records.')
                rows=[]
                for key,record in data['progress'].items():
                    if not isinstance(key,str) or not 1 <= len(key) <= 120: raise ValueError('Invalid topic ID.')
                    rows.append(('progress',key,json.dumps(validate_record('progress',record))))
                ids=set()
                for record in data['entries']:
                    validate_record('entry',record)
                    key=record.get('id')
                    if not isinstance(key,str) or not 1 <= len(key) <= 120 or key in ids: raise ValueError('Invalid or duplicate log ID.')
                    ids.add(key);rows.append(('entry',key,json.dumps(record)))
                rows.append(('settings','main',json.dumps(validate_record('settings',data.get('settings',{})))))
                backup = DATA / ('before-restore-'+datetime.now().strftime('%Y%m%d-%H%M%S-%f')+'.json')
                backup.write_text(json.dumps(state(),ensure_ascii=False,indent=2))
                with connect() as db:
                    db.execute('DELETE FROM records')
                    db.executemany('INSERT INTO records VALUES (?,?,?)',rows)
                return self.respond(200,{'ok':True,'backup':backup.name})
            return self.respond(404,{'error':'Unknown endpoint.'})
        except (ValueError,TypeError,KeyError) as error: return self.respond(400,{'error':str(error)})
        except (sqlite3.Error,OSError): return self.respond(503,{'error':'Could not save. Your input has been preserved; try again.'})

if __name__ == '__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--port',type=int,default=8765)
    parser.add_argument('--data-dir',type=Path,default=DATA)
    args=parser.parse_args(); DATA=args.data_dir.resolve()
    initialize()
    server=ThreadingHTTPServer(('127.0.0.1',args.port),Handler)
    print(f'Study portal: http://127.0.0.1:{server.server_port}',flush=True)
    print(f'Saved work: {DATA / "study.sqlite3"}',flush=True)
    try: server.serve_forever()
    except KeyboardInterrupt: server.server_close()
