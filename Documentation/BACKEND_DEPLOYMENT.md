# Backend deployment and operations draft — no live changes performed

Canonical release backend is Backend/ in this source. Separate workspace Backend/ and the live Render deployment were not replaced. `requirements.lock` pins the complete observed local test environment; production must reproduce and verify it rather than treat local package versions as deployment evidence. Python/toolchain/platform and deployment commit belong in release metadata.

Use a clean venv: `python3 -m venv .venv`, `.venv/bin/pip install -r Backend/requirements.lock`, then `.venv/bin/python -m unittest Backend.test_entitlements Backend.test_providers Backend.test_login Backend.test_hardening`. Deploy `uvicorn Backend.server:app --host 0.0.0.0 --port "$PORT"` from canonical export. Review pins and security advisories before production. No secrets or .env files belong in the publication export.

## Persistence/migrations/backups

Configure PAYMENTS_DB on a persistent Render disk, never ephemeral application storage. Current SQLite schema is initialized additively: purchases, unique provider/remote index, owner lookup index, entitlement snapshots, deletion requests and provider event completion. Back up SQLite with its online backup API before deploying; keep encrypted, access-controlled backups under an owner-approved retention policy. Restore into a fresh temporary path, run integrity_check and fixture/historic-restore acceptance, then switch only after review. A filesystem copy during writes is not a verified backup. Document exact source SHA and migration schema state on deployment. Run one worker initially; concurrent/multi-instance persistence and a shared durable queue need further acceptance.

## Webhooks and retries

Verify Stripe/PayPal signatures before persisting event IDs. `(provider,event)` is unique; mark completion only after reconciliation. Failed attempts retain an incomplete row and return failure so providers can retry. Completed duplicates are acknowledged. Current-state refetch prevents stale grant from out-of-order events. This is a durable completion ledger, **not a complete asynchronous retry queue**; simultaneous duplicate events can repeat reconciliation, and some revocations still scan provider purchases. Fully indexed provider-object routing, queue leasing/backoff, dead-letter handling and recovery monitoring remain H6 work. Do not claim this gate cleared.

Provider network/database work is moved to the worker pool from async webhook handlers. Body input is capped at 1 MiB including chunked bodies, with a basic 120 requests/minute per peer per worker. Configure shared reverse-proxy limits by route, trusted proxy handling and allowed traffic before production; in-memory limits alone are not distributed abuse protection.

Monitor /health database availability, provider failure rates, incomplete events, pending deletion requests, disk space, backup age, entitlement/checkout latency and webhook retries. Redact tokens, secrets and payloads. Owner supplies private alerting/on-call/support routes and verifies actual Render deployment settings. Do not load .env into a test run or alter provider dashboards without authorization.

## Engineering continuation (supersedes the earlier remaining-work paragraph)

`requirements.txt` now includes the exact lock, so the ordinary deployment command cannot silently resolve broad ranges. Record `AKITO_DEPLOYMENT_SHA` and `AKITO_BACKEND_VERSION`; `/health/readiness` returns those values, schema version, pending inbox count and oldest pending age without account/provider credentials. Unrecorded values remain explicit, not fabricated deployment evidence.

Schema version 2 is an additive, transactionally serialized migration. It adds durable operation leases, indexed provider references and authenticated minimal event payload/attempt/retry/error fields. Newer unknown schemas are refused. WAL and busy timeout support local concurrent connections; use one durable database on a persistent local disk. Do not put SQLite on an unvalidated network filesystem or deploy multiple instances with separate disks. Ordinary synchronous endpoints run in FastAPI's worker pool; async webhooks delegate provider/database processing to that pool.

Verified webhook work takes a tokenized, renewable SQLite lease. Completed duplicates are acknowledged; simultaneous in-progress callbacks return retryable failure. Failed work retains the authenticated minimal event identifiers/routing fields and exponential retry time, never marks completion, and releases its lease. A crashed process's lease expires. The worker command below retries persisted authenticated events; it never accepts unsigned HTTP payloads. Checkout reservations retain a stable provider idempotency key across concurrent requests and ambiguous timeouts. Refresh takes a per-owner lease; it refuses stale snapshot publication when purchase block/ownership rows changed during provider verification.

Provider references (session/customer/intent/subscription/charge/capture identifiers) are indexed from verified state reads; events route to matching purchases instead of scanning every account. Historic records lacking reference mappings require a verified restore/refresh/backfill before dependent historic refund/dispute routing. Unrouteable events remain pending and require an alert/operator resolution; they are not silently acknowledged as fulfilled. Provider/API outages fail closed with retryable failure rather than granting a new unverified entitlement. Out-of-order callbacks re-fetch current provider state.

HTTPX provider timeouts are 20 seconds; Stripe timeout is 20 seconds with one bounded SDK retry; JWKS timeout is 10 seconds. Bodies remain limited to 1 MiB and an idle body-read timeout of 15 seconds. Per-worker peer limits still require shared edge enforcement. Slow/paused/killed processes and sustained provider outages need staging/operational acceptance, not just unit tests. Lease renewal does not establish a distributed transactional guarantee across remote provider systems; stable provider idempotency keys and current-state verification remain essential.

From the canonical source root, with reviewed environment supplied by the service account:

```sh
python -m Backend.operations backup --source /persistent/payments.sqlite3 --destination /protected/new-backup.sqlite3
python -m Backend.operations migrate
python -m Backend.operations retry-events
python -m Backend.operations restore --source /protected/new-backup.sqlite3 --destination /protected/new-restore.sqlite3
python -m unittest Backend.test_entitlements Backend.test_providers Backend.test_login Backend.test_hardening Backend.test_concurrency
```

Backup uses SQLite's online API, restrictive 0600 destination permissions and integrity checking. Restore only creates a new database; it never overwrites the active database. Before deployment/rollback: take backup, migrate a restore in staging, test historic entitlement restore/provider mappings and inbox recovery, then switch under owner supervision. Provider payments are not necessary for fixture backup/restore tests.

Configure a service-account scheduler/worker for `retry-events` (for example every minute) only in the reviewed deployment. This task has not created a live scheduler or altered Render. Monitor readiness pending count/age, lease errors, webhook/checkout 503 rates, backup age, disk capacity, provider latency and deletion backlog. Logs emit JSON operation/provider/event/status/error-class fields and omit bearer/device codes, credentials and raw payloads. Owner selects alerting route, retention and provider-event cleanup; no legal retention duration is invented.
