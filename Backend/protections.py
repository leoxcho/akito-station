"""Bound incoming bodies before JSON/provider work; per-worker basic peer rate limit.
Deploy behind a trusted reverse proxy with shared/global rate controls as well.
No bearer tokens, payloads or personal identifiers are logged here.
"""
import time
import asyncio
from collections import OrderedDict
from starlette.responses import JSONResponse

class RequestBounds:
    def __init__(self, app, max_body=1024*1024, requests_per_minute=120, max_peers=4096, body_timeout=15):
        self.app=app; self.max_body=max_body; self.limit=requests_per_minute; self.max_peers=max_peers
        self.peers=OrderedDict();self.body_timeout=body_timeout
    async def __call__(self, scope, receive, send):
        if scope['type']!='http':
            return await self.app(scope,receive,send)
        peer=(scope.get('client') or ('unknown',0))[0]
        now=time.monotonic(); start,count=self.peers.pop(peer,(now,0))
        if now-start>=60: start,count=now,0
        self.peers[peer]=(start,count+1)
        if len(self.peers)>self.max_peers: self.peers.popitem(last=False)
        if count>=self.limit:
            return await JSONResponse({'detail':'Request limit reached'},429,headers={'Retry-After':'60'})(scope,receive,send)
        headers=dict(scope.get('headers',[]))
        try:
            if int(headers.get(b'content-length',b'0'))>self.max_body:
                return await JSONResponse({'detail':'Request body too large'},413)(scope,receive,send)
        except ValueError:
            return await JSONResponse({'detail':'Invalid content length'},400)(scope,receive,send)
        chunks=[]; size=0
        while True:
            try: message=await asyncio.wait_for(receive(),timeout=self.body_timeout)
            except asyncio.TimeoutError:
                return await JSONResponse({'detail':'Request body timeout'},408)(scope,receive,send)
            if message['type']=='http.disconnect': return
            size+=len(message.get('body',b''))
            if size>self.max_body:
                return await JSONResponse({'detail':'Request body too large'},413)(scope,receive,send)
            chunks.append(message.get('body',b''))
            if not message.get('more_body'): break
        delivered=False
        async def bounded_receive():
            nonlocal delivered
            if not delivered:
                delivered=True
                return {'type':'http.request','body':b''.join(chunks),'more_body':False}
            return await receive()
        await self.app(scope,bounded_receive,send)
