#!/usr/bin/env python3
"""Local study portal. Standard-library only; records live in SQLite."""
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from urllib.parse import urlparse, unquote
from datetime import datetime, timezone
import argparse
import json
import mimetypes
import sqlite3
import uuid
import re

ROOT = Path(__file__).resolve().parent
STATIC = ROOT / 'dist'
DATA = ROOT / 'storage'

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
