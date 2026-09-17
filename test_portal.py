"""Focused storage/API checks; temporary database only."""
import tempfile
import unittest
from pathlib import Path
from threading import Thread
from urllib.request import Request, urlopen
from urllib.error import HTTPError
import json
import server

class PortalTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp=tempfile.TemporaryDirectory(prefix='fieldnotes-test-')
        server.DATA=Path(cls.temp.name)
        server.initialize()
        cls.http=server.ThreadingHTTPServer(('127.0.0.1',0),server.Handler)
        cls.thread=Thread(target=cls.http.serve_forever,daemon=True);cls.thread.start()
        cls.base=f'http://127.0.0.1:{cls.http.server_port}'
    @classmethod
    def tearDownClass(cls):
        cls.http.shutdown();cls.http.server_close();cls.temp.cleanup()
    def call(self,path,data=None,origin=None):
        headers={'Content-Type':'application/json'}
        if origin:headers['Origin']=origin
        req=Request(self.base+path,data=json.dumps(data).encode() if data is not None else None,headers=headers)
        with urlopen(req) as r:return json.load(r)
    def test_roundtrip(self):
        self.call('/api/save',{'kind':'progress','id':'p-functions','record':{'checks':[1,3],'notes':'Return values & <examples>','status':'learning'}})
        self.call('/api/save',{'kind':'progress','id':'assessment-p-test','record':{'checks':[0],'due':'2026-12-10','time':'11:00','submitted':False}})
        record={'type':'task','topic':'COMP4004','text':'Week 1 practical','date':'2026-09-24','minutes':45,'resolved':False}
        saved=self.call('/api/save',{'kind':'entry','record':record})
        record.update(id=saved['id'],resolved=True)
        self.call('/api/save',{'kind':'entry','id':saved['id'],'record':record})
        self.call('/api/save',{'kind':'settings','record':{'dailyMinutes':120,'timetableUrl':'https://cloud.timeedit.net/uk_obu/web/students/'}})
        backup=self.call('/api/export');server.initialize()
        self.assertEqual(self.call('/api/state'),backup)
        self.call('/api/import',backup)
        self.assertEqual(self.call('/api/state'),backup)
        self.assertEqual(len(list(server.DATA.glob('before-restore-*.json'))),1)
        self.assertTrue(next(e for e in backup['entries'] if e['id']==saved['id'])['resolved'])
    def test_invalid_import_is_atomic(self):
        before=self.call('/api/state')
        invalid={'version':1,'progress':{},'entries':[{'type':'task','text':'bad'}],'settings':{}}
        with self.assertRaises(HTTPError) as e:self.call('/api/import',invalid)
        self.assertEqual(e.exception.code,400)
        self.assertEqual(self.call('/api/state'),before)
    def test_cross_origin_rejected(self):
        with self.assertRaises(HTTPError) as e:self.call('/api/save',{},'https://example.com')
        self.assertEqual(e.exception.code,403)
    def test_invalid_session_rejected(self):
        with self.assertRaises(HTTPError):self.call('/api/save',{'kind':'entry','record':{'type':'task','text':'Broken session','date':'2026-09-22','category':'event','minutes':0}})
    def test_sources_and_entrypoint(self):
        for path in ['/','/portal.js','/plan.js','/portal.css','/sources.json','/timetable.json']:
            with urlopen(self.base+path) as r:self.assertEqual(r.status,200)
        self.assertEqual(len(self.call('/sources.json')),59)
        self.assertEqual(len(self.call('/timetable.json')['events']),35)

if __name__=='__main__':unittest.main()
