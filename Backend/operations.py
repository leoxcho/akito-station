"""Offline database backup/validation and bounded authenticated inbox retry worker.
Run as the backend service account. Never use raw file copy for a live WAL database.
"""
import argparse
from contextlib import closing
import json
import os
import sqlite3
from pathlib import Path

def copy_database(source,destination):
    source=Path(source);destination=Path(destination)
    if not source.is_file() or destination.exists(): raise ValueError('Existing source and new destination required')
    descriptor=os.open(destination,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600);os.close(descriptor)
    try:
        with closing(sqlite3.connect('file:'+str(source.resolve())+'?mode=ro',uri=True)) as src,closing(sqlite3.connect(destination)) as dst:
            src.backup(dst)
            if dst.execute('PRAGMA integrity_check').fetchone()[0]!='ok': raise ValueError('Database integrity validation failed')
    except Exception:
        destination.unlink(missing_ok=True);raise

def main():
    parser=argparse.ArgumentParser();parser.add_argument('action',choices=['backup','restore','retry-events','migrate']);parser.add_argument('--source');parser.add_argument('--destination');args=parser.parse_args()
    if args.action in ('backup','restore'):
        if not args.source or not args.destination: parser.error('source and new destination required')
        copy_database(args.source,args.destination);print(json.dumps({'status':'ok','operation':args.action}));return
    from . import server
    if args.action=='migrate':
        with server.db() as connection: print(json.dumps({'schema':connection.execute('PRAGMA user_version').fetchone()[0]}))
    else: print(json.dumps(server.retry_events()))
if __name__=='__main__':main()
