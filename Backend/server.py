"""Sandbox-first reference service. Run behind HTTPS with rate limits; see PAYMENTS.md."""
import json
import logging
import functools
import threading
import os
import base64
import hashlib
import hmac
from urllib.parse import urlencode
import sqlite3
import uuid
import time
from contextlib import contextmanager
from datetime import datetime, timezone, timedelta
from decimal import Decimal

import httpx
import jwt
import stripe
from fastapi import FastAPI, Header, HTTPException, Request
from starlette.concurrency import run_in_threadpool
from fastapi.responses import PlainTextResponse, RedirectResponse, JSONResponse
try:
    from .protections import RequestBounds
except ImportError:
    from protections import RequestBounds
try:
    from .entitlements import aggregate
    from .providers import provider_state
except ImportError:  # Render may launch from Backend/.
    from entitlements import aggregate
    from providers import provider_state

logger=logging.getLogger("akito.backend")
app = FastAPI()
app.add_middleware(RequestBounds)
stripe.default_http_client=stripe.RequestsClient(timeout=20)
stripe.max_network_retries=1
@app.exception_handler(stripe.StripeError)
async def stripe_failure(request, error):
    logger.warning(json.dumps({"operation":"stripe","status":"unavailable","error":type(error).__name__}))
    return JSONResponse({"detail":"Payment provider unavailable; retry safely"},status_code=503,headers={"Retry-After":"5"})

stripe.api_key = os.getenv("STRIPE_SECRET_KEY", "")
DB = os.getenv("PAYMENTS_DB", "payments.sqlite3")
PP = "https://api-m.paypal.com" if os.getenv("PAYPAL_LIVE") == "true" else "https://api-m.sandbox.paypal.com"

def env(key):
    value = os.getenv(key, "")
    if not value:
        raise HTTPException(503, "Service not configured")
    return value

@contextmanager
def db():
    connection = sqlite3.connect(DB, timeout=20)
    connection.row_factory = sqlite3.Row
    try:
        connection.execute("PRAGMA busy_timeout=20000")
        connection.execute("PRAGMA journal_mode=WAL")
        connection.execute("PRAGMA foreign_keys=ON")
        if connection.execute("PRAGMA user_version").fetchone()[0]>2: raise RuntimeError("Database schema is newer than this backend")
        connection.execute("BEGIN IMMEDIATE")
        connection.execute("CREATE TABLE IF NOT EXISTS purchases (id TEXT PRIMARY KEY, owner TEXT NOT NULL, provider TEXT NOT NULL, model TEXT NOT NULL, remote TEXT, blocked INTEGER NOT NULL DEFAULT 0, created REAL NOT NULL, checkout_url TEXT)")
        connection.execute("CREATE UNIQUE INDEX IF NOT EXISTS remote_purchase ON purchases(provider,remote)")
        connection.execute("CREATE TABLE IF NOT EXISTS entitlement_snapshots (owner TEXT PRIMARY KEY, payload TEXT NOT NULL, updated TEXT NOT NULL)")
        connection.execute("CREATE INDEX IF NOT EXISTS owner_purchases ON purchases(owner,provider,model,created)")
        connection.execute("CREATE TABLE IF NOT EXISTS deletion_requests (owner TEXT PRIMARY KEY, requested REAL NOT NULL, status TEXT NOT NULL DEFAULT 'pending')")
        connection.execute("CREATE TABLE IF NOT EXISTS provider_events (provider TEXT NOT NULL, event TEXT NOT NULL, received REAL NOT NULL, completed REAL, PRIMARY KEY(provider,event))")
        connection.execute("CREATE TABLE IF NOT EXISTS operation_leases (key TEXT PRIMARY KEY, token TEXT NOT NULL, expires REAL NOT NULL)")
        connection.execute("CREATE TABLE IF NOT EXISTS provider_references (provider TEXT NOT NULL, remote TEXT NOT NULL, purchase TEXT NOT NULL, PRIMARY KEY(provider,remote,purchase))")
        connection.execute("CREATE INDEX IF NOT EXISTS reference_purchase ON provider_references(purchase)")
        columns={row[1] for row in connection.execute("PRAGMA table_info(provider_events)")}
        for name, definition in [("payload","TEXT"),("attempts","INTEGER NOT NULL DEFAULT 0"),("retry_at","REAL NOT NULL DEFAULT 0"),("error","TEXT")]:
            if name not in columns: connection.execute("ALTER TABLE provider_events ADD COLUMN "+name+" "+definition)
        connection.execute("CREATE INDEX IF NOT EXISTS pending_events ON provider_events(completed,retry_at)")
        connection.execute("PRAGMA user_version=2")
        connection.commit()
        yield connection
        connection.commit()
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()

def account(authorization):
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(401, "Sign in required")
    try:
        token = authorization[7:]
        key = jwt.PyJWKClient(env("OIDC_JWKS_URL"), timeout=10).get_signing_key_from_jwt(token)
        claims = jwt.decode(token, key.key, algorithms=["RS256"], audience=env("OIDC_AUDIENCE"), issuer=env("OIDC_ISSUER"), options={"require": ["exp", "iat", "sub", "iss", "aud"]})
        return claims["iss"] + "|" + claims["sub"]
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(401, "Session expired or invalid")

def call(method, url, **kwargs):
    try:
        result = httpx.request(method, url, timeout=20, **kwargs)
        result.raise_for_status()
        return result.json()
    except Exception:
        raise HTTPException(503, "Payment provider unavailable")

def paypal(method, path, payload=None, request_id=None):
    token = call("POST", PP + "/v1/oauth2/token", auth=(env("PAYPAL_CLIENT_ID"), env("PAYPAL_CLIENT_SECRET")), data={"grant_type": "client_credentials"})["access_token"]
    headers = {"Authorization": "Bearer " + token}
    if request_id:
        headers["PayPal-Request-Id"] = request_id
    return call(method, PP + path, headers=headers, **({"json": payload} if payload is not None else {}))

def offers():
    result = []
    for provider in ("stripe", "paypal"):
        for model in ("oneTime", "subscription"):
            switch = "ENABLE_ONE_TIME" if model == "oneTime" else "ENABLE_SUBSCRIPTION"
            key = ("STRIPE_PRICE_ID" if model == "oneTime" else "STRIPE_SUBSCRIPTION_PRICE_ID") if provider == "stripe" else ("PAYPAL_AMOUNT" if model == "oneTime" else "PAYPAL_PLAN_ID")
            if os.getenv(switch, "false") == "true" and os.getenv(key) and os.getenv("STRIPE_SECRET_KEY" if provider == "stripe" else "PAYPAL_CLIENT_SECRET"):
                result.append({"id": provider + ":" + model, "provider": provider, "model": model, "label": "One-time PRO — view price at checkout" if model == "oneTime" else "PRO subscription — view terms at checkout"})
    return result

@contextmanager
def operation_lease(key,seconds=300):
    token=str(uuid.uuid4())
    with db() as connection:
        connection.execute("BEGIN IMMEDIATE")
        row=connection.execute("SELECT expires FROM operation_leases WHERE key=?",(key,)).fetchone()
        if row and row[0]>time.time(): raise HTTPException(503,"Operation in progress; retry shortly")
        connection.execute("INSERT OR REPLACE INTO operation_leases VALUES(?,?,?)",(key,token,time.time()+seconds))
    stopped=threading.Event()
    def renew():
        while not stopped.wait(max(0.05,seconds/3)):
            try:
                with db() as connection: connection.execute("UPDATE operation_leases SET expires=? WHERE key=? AND token=?",(time.time()+seconds,key,token))
            except Exception: logger.error(json.dumps({"operation":"lease_renewal","status":"failed"}))
    worker=threading.Thread(target=renew,daemon=True);worker.start()
    try: yield token
    finally:
        stopped.set();worker.join(timeout=2)
        with db() as connection: connection.execute("DELETE FROM operation_leases WHERE key=? AND token=?",(key,token))

def minimal_event(provider,event):
    clean={"id":event.get("id")}
    if provider=="stripe":
        clean["type"]=event.get("type")
        obj=event.get("data",{}).get("object",{})
        clean["data"]={"object":{key:obj[key] for key in ["id","customer","charge","subscription","payment_intent","client_reference_id"] if key in obj}}
        clean["data"]["object"]["metadata"]={"purchase":obj.get("metadata",{}).get("purchase")}
    else:
        clean["event_type"]=event.get("event_type")
        obj=event.get("resource",{})
        clean["resource"]={key:obj[key] for key in ["id","billing_agreement_id","sale_id","dispute_id","custom_id"] if key in obj}
        clean["resource"]["supplementary_data"]={"related_ids":{key:value for key,value in obj.get("supplementary_data",{}).get("related_ids",{}).items() if key in ["order_id","capture_id","authorization_id"] and isinstance(value,str)}}
    return clean

def event_operation(provider):
    def decorate(function):
        @functools.wraps(function)
        def execute(event):
            ident=event.get("id")
            if not isinstance(ident,str) or not ident or len(ident)>256: raise HTTPException(400,"Invalid event identifier")
            event=minimal_event(provider,event)
            with operation_lease("event:"+provider+":"+ident):
                if event_completed(provider,ident): return {"received":True,"duplicate":True}
                # Persist authenticated events before work; failures are retried from this durable inbox.
                with db() as connection:
                    connection.execute("UPDATE provider_events SET payload=?,attempts=attempts+1 WHERE provider=? AND event=?",(json.dumps(event),provider,ident))
                try:
                    result=function(event)
                    logger.info(json.dumps({"operation":"webhook","provider":provider,"event":ident,"status":"completed"}))
                    return result
                except Exception as error:
                    with db() as connection:
                        attempts=connection.execute("SELECT attempts FROM provider_events WHERE provider=? AND event=?",(provider,ident)).fetchone()[0]
                        connection.execute("UPDATE provider_events SET retry_at=?,error=? WHERE provider=? AND event=?",(time.time()+min(3600,2**min(attempts,10)),type(error).__name__,provider,ident))
                    logger.warning(json.dumps({"operation":"webhook","provider":provider,"event":ident,"status":"retry","error":type(error).__name__}))
                    raise
        return execute
    return decorate

def record_reference(provider,purchase,remote):
    if not isinstance(remote,str) or not remote: return
    with db() as connection: connection.execute("INSERT OR IGNORE INTO provider_references VALUES(?,?,?)",(provider,remote,purchase))

def event_purchases(provider,event,connection):
    obj=event.get("data",{}).get("object",{}) if provider=="stripe" else event.get("resource",{})
    refs={obj.get(key) for key in ["id","customer","charge","subscription","payment_intent","billing_agreement_id","sale_id"] if isinstance(obj.get(key),str)}
    related=obj.get("supplementary_data",{}).get("related_ids",{})
    refs.update(value for value in related.values() if isinstance(value,str))
    refs.update(value for value in event.get("routing_refs",[]) if isinstance(value,str))
    purchase=obj.get("client_reference_id") or obj.get("custom_id") or obj.get("metadata",{}).get("purchase")
    found={}
    for remote in refs:
        for row in connection.execute("SELECT * FROM purchases WHERE provider=? AND (remote=? OR id IN (SELECT purchase FROM provider_references WHERE provider=? AND remote=?))",(provider,remote,provider,remote)): found[row["id"]]=row
    if isinstance(purchase,str):
        for row in connection.execute("SELECT * FROM purchases WHERE provider=? AND id=?",(provider,purchase)): found[row["id"]]=row
    if not found: raise HTTPException(503,"Event reference not linked yet; retry/operator review required")
    return list(found.values())

def retry_events(limit=100):
    with db() as connection: rows=connection.execute("SELECT provider,payload FROM provider_events WHERE completed IS NULL AND payload IS NOT NULL AND retry_at<=? ORDER BY received LIMIT ?",(time.time(),limit)).fetchall()
    result={"completed":0,"pending":0}
    for row in rows:
        try:
            (process_stripe_event if row["provider"]=="stripe" else process_paypal_event)(json.loads(row["payload"]))
            result["completed"]+=1
        except Exception: result["pending"]+=1
    return result

@app.get("/offers")
def catalog():
    return offers()

@app.post("/login/start")
def login_start():
    data = call("POST", env("OIDC_DEVICE_URL"), data={"client_id": env("OIDC_CLIENT_ID"), "audience": env("OIDC_AUDIENCE"), "scope": "openid profile"})
    return {"deviceCode": data["device_code"], "userCode": data["user_code"], "verificationURL": data.get("verification_uri_complete", data["verification_uri"]), "interval": data.get("interval", 5), "expiresIn": data["expires_in"]}

@app.post("/login/poll")
def login_poll(body: dict):
    try:
        response = httpx.post(env("OIDC_TOKEN_URL"), data={"client_id": env("OIDC_CLIENT_ID"), "device_code": body.get("deviceCode", ""), "grant_type": "urn:ietf:params:oauth:grant-type:device_code"}, timeout=20)
        data = response.json()
        if data.get("error") == "slow_down":
            return {"token": None, "interval": 10}
        if data.get("error") == "authorization_pending":
            return {"token": None}
        response.raise_for_status()
        account("Bearer " + data["access_token"])
        return {"token": data["access_token"]}
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(401, "Sign-in failed")


def web_state(offer="paypal:oneTime"):
    payload = json.dumps(
        {"offer": offer, "exp": int(time.time()) + 900},
        separators=(",", ":")
    ).encode()
    encoded = base64.urlsafe_b64encode(payload).decode().rstrip("=")
    signature = hmac.new(
        env("OIDC_WEB_CLIENT_SECRET").encode(),
        encoded.encode(),
        hashlib.sha256
    ).digest()
    signed = base64.urlsafe_b64encode(signature).decode().rstrip("=")
    return encoded + "." + signed


def read_web_state(value):
    try:
        encoded, supplied = value.split(".", 1)
        expected = base64.urlsafe_b64encode(
            hmac.new(
                env("OIDC_WEB_CLIENT_SECRET").encode(),
                encoded.encode(),
                hashlib.sha256
            ).digest()
        ).decode().rstrip("=")

        if not hmac.compare_digest(supplied, expected):
            raise ValueError("invalid signature")

        padded = encoded + "=" * (-len(encoded) % 4)
        payload = json.loads(base64.urlsafe_b64decode(padded))

        if payload["exp"] < int(time.time()):
            raise ValueError("expired")

        return payload
    except Exception:
        raise HTTPException(400, "Invalid or expired sign-in request")


@app.get("/auth/login")
def web_login():
    callback = env("PUBLIC_URL").rstrip("/") + "/auth/callback"
    params = {
        "response_type": "code",
        "client_id": env("OIDC_WEB_CLIENT_ID"),
        "redirect_uri": callback,
        "scope": "openid profile",
        "audience": env("OIDC_AUDIENCE"),
        "state": web_state(),
    }
    authorize = env("OIDC_ISSUER").rstrip("/") + "/authorize?" + urlencode(params)
    return RedirectResponse(authorize, status_code=302)


@app.get("/auth/callback")
def web_callback(code: str = "", state: str = "", error: str = ""):
    if error:
        raise HTTPException(401, "Sign-in cancelled or failed")
    if not code or not state:
        raise HTTPException(400, "Missing authorization response")

    signed = read_web_state(state)
    callback = env("PUBLIC_URL").rstrip("/") + "/auth/callback"

    token = call(
        "POST",
        env("OIDC_ISSUER").rstrip("/") + "/oauth/token",
        data={
            "grant_type": "authorization_code",
            "client_id": env("OIDC_WEB_CLIENT_ID"),
            "client_secret": env("OIDC_WEB_CLIENT_SECRET"),
            "code": code,
            "redirect_uri": callback,
        },
    )

    access_token = token.get("access_token")
    if not access_token:
        raise HTTPException(401, "Sign-in failed")

    result = checkout(
        {"offer": signed["offer"]},
        authorization="Bearer " + access_token
    )
    return RedirectResponse(result["url"], status_code=302)


@app.post("/checkout")
def checkout(body: dict, authorization: str = Header(default="")):
    owner = account(authorization)
    offer = next((x for x in offers() if x["id"] == body.get("offer")), None)
    if not offer:
        raise HTTPException(400, "Offer unavailable")
    if reconcile(owner)["state"] in ("pro", "subscriptionActive"):
        raise HTTPException(409, "Membership already active")
    provider, model = offer["provider"], offer["model"]
    with db() as connection:
        connection.execute("BEGIN IMMEDIATE")
        # Reuse the same provider idempotency key on retry, including ambiguous timeouts.
        previous = connection.execute("SELECT * FROM purchases WHERE owner=? AND provider=? AND model=? AND created>? ORDER BY created DESC LIMIT 1", (owner, provider, model, time.time() - 21600)).fetchone()
        if previous and previous["checkout_url"]:
            return {"id": previous["id"], "url": previous["checkout_url"]}
        ident = previous["id"] if previous else str(uuid.uuid4())
        if not previous:
            connection.execute("INSERT INTO purchases(id,owner,provider,model,created) VALUES(?,?,?,?,?)", (ident, owner, provider, model, time.time()))
    with operation_lease("checkout:"+ident):
        with db() as connection:
            ready=connection.execute("SELECT checkout_url FROM purchases WHERE id=?",(ident,)).fetchone()
            if ready and ready[0]: return {"id":ident,"url":ready[0]}
        back = env("PUBLIC_URL") + "/return"
        if provider == "stripe":
            session = stripe.checkout.Session.create(mode="payment" if model == "oneTime" else "subscription", line_items=[{"price": env("STRIPE_PRICE_ID" if model == "oneTime" else "STRIPE_SUBSCRIPTION_PRICE_ID"), "quantity": 1}], client_reference_id=ident, metadata={"purchase": ident}, success_url=back, cancel_url=back, idempotency_key=ident)
            remote, url = session.id, session.url
        elif model == "oneTime":
            order = paypal("POST", "/v2/checkout/orders", {"intent": "CAPTURE", "purchase_units": [{"custom_id": ident, "payee": {"merchant_id": env("PAYPAL_MERCHANT_ID")}, "amount": {"currency_code": env("PAYPAL_CURRENCY"), "value": env("PAYPAL_AMOUNT")}}], "payment_source": {"paypal": {"experience_context": {"return_url": back, "cancel_url": back, "user_action": "PAY_NOW", "shipping_preference": "NO_SHIPPING"}}}}, ident)
            remote = order["id"]
            url = next(x["href"] for x in order["links"] if x["rel"] in ("approve", "payer-action"))
        else:
            subscription = paypal("POST", "/v1/billing/subscriptions", {"plan_id": env("PAYPAL_PLAN_ID"), "custom_id": ident, "application_context": {"return_url": back, "cancel_url": back, "user_action": "SUBSCRIBE_NOW"}}, ident)
            remote = subscription["id"]
            url = next(x["href"] for x in subscription["links"] if x["rel"] == "approve")
        with db() as connection:
            connection.execute("UPDATE purchases SET remote=?,checkout_url=? WHERE id=?", (remote, url, ident))
        return {"id": ident, "url": url}


def reconcile(owner):
    key="refresh:"+hashlib.sha256(owner.encode()).hexdigest()
    with operation_lease(key) as token:
        return reconcile_owned(owner,lease=(key,token))

def reconcile_owned(owner,lease=None):
    with db() as connection:
        rows = connection.execute("SELECT * FROM purchases WHERE owner=?", (owner,)).fetchall()
    try:
        now = datetime.now(timezone.utc)
        result = aggregate([provider_state(row, stripe, paypal, record=lambda remote,row=row:record_reference(row["provider"],row["id"],remote)) for row in rows], now)
        with db() as connection:
            connection.execute("BEGIN IMMEDIATE")
            if lease:
                active=connection.execute("SELECT token,expires FROM operation_leases WHERE key=?",(lease[0],)).fetchone()
                if not active or active[0]!=lease[1] or active[1]<=time.time(): raise HTTPException(503,"Verification lease expired; retry")
            current=connection.execute("SELECT id,blocked FROM purchases WHERE owner=?",(owner,)).fetchall()
            if {(row["id"],row["blocked"]) for row in current}!={(row["id"],row["blocked"]) for row in rows}: raise HTTPException(503,"Purchase changed during verification; retry")
            connection.execute("INSERT OR REPLACE INTO entitlement_snapshots VALUES(?,?,?)", (owner, json.dumps(result), now.isoformat()))
        return result
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(503, "Verification unavailable")

@app.get("/entitlement")
def entitlement(authorization: str = Header(default="")):
    return reconcile(account(authorization))

@app.post("/restore")
@app.post("/verify")
@app.post("/subscription")
def refresh(authorization: str = Header(default="")):
    return reconcile(account(authorization))

@app.post("/manage")
def manage(authorization: str = Header(default="")):
    owner = account(authorization)
    with db() as connection:
        rows = connection.execute("SELECT * FROM purchases WHERE owner=? AND model='subscription' AND remote IS NOT NULL ORDER BY rowid DESC", (owner,)).fetchall()
    if not rows:
        raise HTTPException(404, "No subscription")
    row = rows[0]
    if row["provider"] == "stripe":
        session = stripe.checkout.Session.retrieve(row["remote"])
        if not session.customer:
            raise HTTPException(409, "Checkout pending")
        portal = stripe.billing_portal.Session.create(customer=session.customer, return_url=env("PUBLIC_URL") + "/return")
        return {"id": row["id"], "url": portal.url}
    return {"id": row["id"], "url": "https://www.paypal.com/myaccount/autopay/" if os.getenv("PAYPAL_LIVE") == "true" else "https://www.sandbox.paypal.com/myaccount/autopay/"}

@app.get("/return", response_class=PlainTextResponse)
def returned():
    return "Return to Akito Station and choose Restore / Refresh purchase. This page does not confirm payment."

@app.post("/webhooks/stripe")
async def stripe_webhook(request: Request):
    raw = await request.body()
    return await run_in_threadpool(handle_stripe_event,raw,dict(request.headers))

def handle_stripe_event(raw,headers):
    try:
        event = stripe.Webhook.construct_event(raw, headers.get("stripe-signature", ""), env("STRIPE_WEBHOOK_SECRET"))
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(400, "Invalid signature")
    return process_stripe_event(event)

@event_operation("stripe")
def process_stripe_event(event):
    if event_completed("stripe",event.get("id")):
        return {"received": True, "duplicate": True}
    # Re-fetch current provider state, so replayed/out-of-order notifications cannot grant stale access.
    with db() as connection:
        rows = event_purchases("stripe",event,connection)
        obj = event["data"]["object"]
        if event["type"] in ("charge.refunded", "charge.dispute.created"):
            charge_id = obj["id"] if event["type"] == "charge.refunded" else obj["charge"]
            charge = stripe.Charge.retrieve(charge_id)
            # Conservatively suspend subscriptions for this customer for manual review.
            for row in rows:
                session = stripe.checkout.Session.retrieve(row["remote"])
                if row["model"] == "subscription" and charge.customer and session.customer == charge.customer:
                    connection.execute("UPDATE purchases SET blocked=1 WHERE id=?", (row["id"],))
    for owner in {row["owner"] for row in rows}:
        reconcile(owner)
    complete_event("stripe",event["id"])
    return {"received": True}

@app.post("/webhooks/paypal")
async def paypal_webhook(request: Request):
    event = await request.json()
    return await run_in_threadpool(handle_paypal_event,event,dict(request.headers))

def handle_paypal_event(event,headers):
    verified = paypal("POST", "/v1/notifications/verify-webhook-signature", {"auth_algo": headers.get("paypal-auth-algo"), "cert_url": headers.get("paypal-cert-url"), "transmission_id": headers.get("paypal-transmission-id"), "transmission_sig": headers.get("paypal-transmission-sig"), "transmission_time": headers.get("paypal-transmission-time"), "webhook_id": env("PAYPAL_WEBHOOK_ID"), "webhook_event": event})
    if verified.get("verification_status") != "SUCCESS":
        raise HTTPException(400, "Invalid signature")
    return process_paypal_event(event)

@event_operation("paypal")
def process_paypal_event(event):
    if event_completed("paypal",event.get("id")):
        return {"received": True, "duplicate": True}
    resource = event.get("resource", {})
    event=dict(event)
    if event.get("event_type")=="CUSTOMER.DISPUTE.CREATED":
        dispute=paypal("GET","/v1/customer/disputes/"+resource["dispute_id"])
        event["routing_refs"]=[item.get("seller_transaction_id") for item in dispute.get("disputed_transactions",[]) if item.get("seller_transaction_id")]
        if len(event["routing_refs"])>50: raise HTTPException(503,"Dispute routing exceeds automatic limit; operator review required")
        for transaction in list(event["routing_refs"]):
            with db() as connection:
                known=connection.execute("SELECT 1 FROM provider_references WHERE provider='paypal' AND remote=?",(transaction,)).fetchone()
            if not known:
                sale=paypal("GET","/v1/payments/sale/"+transaction)
                if sale.get("billing_agreement_id"): event["routing_refs"].append(sale["billing_agreement_id"])
    if event.get("event_type") in ("PAYMENT.SALE.REFUNDED","PAYMENT.SALE.REVERSED") and not resource.get("billing_agreement_id") and resource.get("sale_id"):
        sale=paypal("GET","/v1/payments/sale/"+resource["sale_id"])
        event["routing_refs"]=[sale.get("billing_agreement_id")] if sale.get("billing_agreement_id") else []
    with db() as connection:
        rows = event_purchases("paypal",event,connection)
        if event.get("event_type") in ("PAYMENT.SALE.REFUNDED", "PAYMENT.SALE.REVERSED"):
            subscription_id = resource.get("billing_agreement_id")
            if not subscription_id and resource.get("sale_id"):
                sale = paypal("GET", "/v1/payments/sale/" + resource["sale_id"])
                subscription_id = sale.get("billing_agreement_id")
            if not subscription_id:
                # Do not acknowledge an unrouteable revocation; alert operator and retry.
                raise HTTPException(503, "Refund requires operator reconciliation")
            connection.execute("UPDATE purchases SET blocked=1 WHERE provider='paypal' AND remote=?", (subscription_id,))
    if event.get("event_type") == "CUSTOMER.DISPUTE.CREATED":
        dispute = paypal("GET", "/v1/customer/disputes/" + resource["dispute_id"])
        transaction_ids = {item.get("seller_transaction_id") for item in dispute.get("disputed_transactions", [])}
        with db() as connection:
            for row in rows:
                if row["model"] == "oneTime":
                    order = paypal("GET", "/v2/checkout/orders/" + row["remote"])
                    captures = {capture["id"] for unit in order.get("purchase_units", []) for capture in unit.get("payments", {}).get("captures", [])}
                    if transaction_ids & captures:
                        connection.execute("UPDATE purchases SET blocked=1 WHERE id=?", (row["id"],))
                else:
                    for transaction_id in transaction_ids - {None}:
                        sale = paypal("GET", "/v1/payments/sale/" + transaction_id)
                        if sale.get("billing_agreement_id") == row["remote"]:
                            connection.execute("UPDATE purchases SET blocked=1 WHERE id=?", (row["id"],))
    for owner in {row["owner"] for row in rows}:
        reconcile(owner)
    complete_event("paypal",event["id"])
    return {"received": True}

@app.get("/health")
def health():
    with db() as connection:
        connection.execute("SELECT 1").fetchone()
    return {"status": "ok"}

@app.get("/health/readiness")
def readiness():
    with db() as connection:
        version=connection.execute("PRAGMA user_version").fetchone()[0]
        pending=connection.execute("SELECT COUNT(*),MIN(received) FROM provider_events WHERE completed IS NULL").fetchone()
    return {"status":"ok","schema":version,"deploymentSHA":os.getenv("AKITO_DEPLOYMENT_SHA","unrecorded"),"version":os.getenv("AKITO_BACKEND_VERSION","unrecorded"),"pendingEvents":pending[0],"oldestPendingSeconds":max(0,int(time.time()-pending[1])) if pending[1] else 0}

@app.post("/account/deletion-request")
def deletion_request(authorization: str = Header(default="")):
    owner = account(authorization)
    with db() as connection:
        connection.execute("INSERT OR IGNORE INTO deletion_requests(owner,requested) VALUES(?,?)", (owner,time.time()))
    return {"status": "pending", "message": "Request recorded for operator review. This does not cancel a subscription or issue a refund. Provider and identity deletion require separate review."}

def event_completed(provider, ident):
    if not isinstance(ident,str) or not ident or len(ident)>256:
        raise HTTPException(400, "Invalid event identifier")
    with db() as connection:
        row=connection.execute("SELECT completed FROM provider_events WHERE provider=? AND event=?", (provider,ident)).fetchone()
        if row and row["completed"] is not None:
            return True
        connection.execute("INSERT OR IGNORE INTO provider_events(provider,event,received) VALUES(?,?,?)", (provider,ident,time.time()))
    return False

def complete_event(provider, ident):
    with db() as connection:
        connection.execute("UPDATE provider_events SET completed=? WHERE provider=? AND event=?", (time.time(),provider,ident))
