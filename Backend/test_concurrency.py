import sqlite3
from contextlib import closing
import tempfile
import threading
import time
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch
from fastapi import HTTPException
from . import server
from .operations import copy_database

class ConcurrencyTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.path=Path(self.temp.name)/'db.sqlite3';self.dbpatch=patch.object(server,'DB',str(self.path));self.dbpatch.start()
        with server.db() as db:
            db.execute('INSERT INTO purchases(id,owner,provider,model,remote,created) VALUES(?,?,?,?,?,?)',('purchase','owner','stripe','oneTime','cs_fixture',time.time()))
    def tearDown(self):self.dbpatch.stop();self.temp.cleanup()
    def event(self,ident='evt_fixture'):return {'id':ident,'type':'checkout.session.completed','data':{'object':{'id':'cs_fixture'}}}
    def test_duplicate_webhook_concurrent_and_repeated_callback(self):
        started=threading.Event();release=threading.Event();calls=[]
        def verify(owner):calls.append(owner);started.set();release.wait(2);return {'state':'free'}
        with patch.object(server,'reconcile',side_effect=verify),ThreadPoolExecutor(2) as pool:
            first=pool.submit(server.process_stripe_event,self.event());self.assertTrue(started.wait(2))
            with self.assertRaises(HTTPException):server.process_stripe_event(self.event())
            release.set();self.assertTrue(first.result()['received']);self.assertTrue(server.process_stripe_event(self.event())['duplicate'])
        self.assertEqual(calls,['owner'])
    def test_delayed_webhook_outage_retry_and_restart_persistence(self):
        with patch.object(server,'reconcile',side_effect=HTTPException(503,'offline')):
            with self.assertRaises(HTTPException):server.process_stripe_event(self.event())
        with server.db() as db:
            row=db.execute('SELECT attempts,payload,completed FROM provider_events').fetchone();self.assertEqual(row[0],1);self.assertIsNone(row[2]);db.execute('UPDATE provider_events SET retry_at=0')
        with patch.object(server,'reconcile',return_value={'state':'pro'}):self.assertEqual(server.retry_events()['completed'],1)
        # New connections retain completion after backend restart; no in-memory dedup dependency.
        with closing(sqlite3.connect(self.path)) as db:self.assertIsNotNone(db.execute('SELECT completed FROM provider_events').fetchone()[0])
    def test_simultaneous_refresh_and_revocation_fencing(self):
        started=threading.Event();release=threading.Event()
        def state(*args,**kwargs):started.set();release.wait(2);return 'pro',None
        with patch.object(server,'provider_state',side_effect=state),ThreadPoolExecutor(2) as pool:
            first=pool.submit(server.reconcile,'owner');self.assertTrue(started.wait(2))
            with self.assertRaises(HTTPException):server.reconcile('owner')
            with server.db() as db:db.execute('UPDATE purchases SET blocked=1')
            release.set()
            with self.assertRaises(HTTPException):first.result()
        with server.db() as db:self.assertEqual(db.execute('SELECT COUNT(*) FROM entitlement_snapshots').fetchone()[0],0)
    def test_duplicate_checkout_preserves_provider_idempotency(self):
        started=threading.Event();release=threading.Event();keys=[]
        def create(**kwargs):keys.append(kwargs['idempotency_key']);started.set();release.wait(2);return SimpleNamespace(id='cs_new',url='https://checkout.stripe.test/fixture')
        with patch.object(server,'account',return_value='new-owner'),patch.object(server,'offers',return_value=[{'id':'stripe:oneTime','provider':'stripe','model':'oneTime'}]),patch.object(server,'reconcile',return_value={'state':'free'}),patch.dict(server.os.environ,{'PUBLIC_URL':'https://backend.test','STRIPE_PRICE_ID':'fixture-price'}),patch.object(server.stripe.checkout.Session,'create',side_effect=create),ThreadPoolExecutor(2) as pool:
            first=pool.submit(server.checkout,{'offer':'stripe:oneTime'},'fixture');self.assertTrue(started.wait(2))
            with self.assertRaises(HTTPException):server.checkout({'offer':'stripe:oneTime'},'fixture')
            release.set();result=first.result();self.assertEqual(server.checkout({'offer':'stripe:oneTime'},'fixture'),result)
        self.assertEqual(len(keys),1)
    def test_indexed_routing_historical_references_and_backup_restore(self):
        server.record_reference('stripe','purchase','ch_historic')
        with server.db() as db:
            self.assertEqual(server.event_purchases('stripe',{'data':{'object':{'id':'ch_historic'}}},db)[0]['id'],'purchase')
        backup=Path(self.temp.name)/'backup';restore=Path(self.temp.name)/'restore';copy_database(self.path,backup);copy_database(backup,restore)
        with closing(sqlite3.connect(restore)) as db:self.assertEqual(db.execute('SELECT COUNT(*) FROM purchases').fetchone()[0],1)
        self.assertEqual(backup.stat().st_mode & 0o777,0o600)
        with self.assertRaises(ValueError):copy_database(self.path,backup)
    def test_dispute_after_prior_subscription_routes_only_owner(self):
        with server.db() as db:
            db.execute("UPDATE purchases SET model='subscription'")
            db.execute('INSERT INTO purchases(id,owner,provider,model,remote,created) VALUES(?,?,?,?,?,?)',('unrelated','other','stripe','subscription','cs_other',time.time()))
        server.record_reference('stripe','purchase','ch_fixture')
        event={'id':'evt_dispute','type':'charge.dispute.created','data':{'object':{'id':'dp_fixture','charge':'ch_fixture'}}}
        with patch.object(server.stripe.Charge,'retrieve',return_value=SimpleNamespace(customer='customer')),patch.object(server.stripe.checkout.Session,'retrieve',return_value=SimpleNamespace(customer='customer')),patch.object(server,'reconcile',return_value={'state':'subscriptionExpired'}) as reconcile:
            self.assertTrue(server.process_stripe_event(event)['received']);self.assertTrue(server.process_stripe_event(event)['duplicate']);reconcile.assert_called_once_with('owner')
        with server.db() as db:
            self.assertEqual(db.execute("SELECT blocked FROM purchases WHERE id='purchase'").fetchone()[0],1)
            self.assertEqual(db.execute("SELECT blocked FROM purchases WHERE id='unrelated'").fetchone()[0],0)
    def test_schema_migration_and_unknown_newer_schema_refused(self):
        with server.db() as db:self.assertEqual(db.execute('PRAGMA user_version').fetchone()[0],2)
        with closing(sqlite3.connect(self.path)) as db:db.execute('PRAGMA user_version=99')
        try:
            with self.assertRaises(RuntimeError):
                with server.db():pass
        finally:
            with closing(sqlite3.connect(self.path)) as db:db.execute('PRAGMA user_version=2')
    def test_minimal_event_does_not_persist_contact_fields(self):
        event=self.event();event['data']['object']['customer_email']='private@example.test';event['data']['object']['metadata']={'purchase':'purchase','private':'secret'}
        minimal=server.minimal_event('stripe',event)
        self.assertNotIn('customer_email',minimal['data']['object']);self.assertEqual(minimal['data']['object']['metadata'],{'purchase':'purchase'})
    def test_lease_renewal_and_expired_worker_recovery(self):
        with server.operation_lease('fixture',seconds=0.15):
            time.sleep(0.25)
            with self.assertRaises(HTTPException):
                with server.operation_lease('fixture'):pass
        with server.db() as db:db.execute('INSERT INTO operation_leases VALUES(?,?,?)',('fixture','dead-worker',time.time()-1))
        with server.operation_lease('fixture'):pass
