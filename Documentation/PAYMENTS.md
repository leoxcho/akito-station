# Akito Station PRO payments

## Public-only integration

The public main window has a large gold, persistent top-right PRO control in a slim row above the content. Settings → Akito Station PRO opens the same membership view. Both observe `PremiumStore.shared` → `EntitlementManager`; there are no separate badge/settings unlock values. The developer edition retains its existing unrestricted access and StoreKit source path, with no membership controls or dependency on the new service.

PRO is a supporter membership for Akito Station development and early access to Akito Station releases. It does not supply games, ROMs, BIOS, firmware, keys, console software, PKGs, emulator binaries, or third-party proprietary content. Existing theme/wallpaper/customization gates use the verified membership. Free emulator, library, controller, save and artwork functionality is unchanged. Online profiles remain unconfigured. **Private early-access release hosting/delivery is not implemented here:** provision a protected channel before advertising that benefit commercially. Never distribute the unrestricted internal developer edition as a payment enforcement mechanism.

## Architecture and API

The app uses Foundation HTTPS plus hosted browser checkout, with no Stripe/PayPal SDKs or provider credentials. `StripePaymentProvider` and `PayPalPaymentProvider` implement the common `PaymentProvider`. The backend chooses prices and account ownership; clients cannot submit an amount, provider product ID, account ID, or entitlement grant.

`Backend/` is a separate Python/FastAPI reference service, not an Xcode target. SQLite stores stable OIDC issuer/subject ownership, provider references, dispute blocks and last verified entitlement snapshots. Provider operations use server environment secrets. Keep the database durable and backed up: a fresh database cannot restore deleted purchase associations.

| Route | Purpose |
| --- | --- |
| `GET /offers` | Server-enabled provider/pricing choices |
| `POST /login/start`, `/login/poll` | OIDC device authorization; browser sign-in, no password in app |
| `POST /checkout` | Authenticated Stripe Checkout, PayPal order or subscription creation |
| `GET /entitlement` | Authenticated canonical provider verification |
| `POST /verify`, `/restore`, `/subscription` | Same verification, used after checkout, on another Mac and for renewal |
| `POST /manage` | Stripe customer portal or PayPal subscription management |
| `POST /webhooks/stripe`, `/webhooks/paypal` | Verified provider notifications, reconciliation and snapshot update |
| `GET /return` | Instructions only; never grants membership |

All account routes require a JWT API access token verified against a configured JWKS, RS256 signature, issuer, audience and expiration. Configure a device-flow OIDC client issuing JWT access tokens for this API. Bearer access tokens are stored in the macOS Keychain with WhenUnlockedThisDeviceOnly accessibility, scoped to the backend URL. Launch restores the session and re-verifies entitlement. An HTTP 401 clears the token and entitlement and asks for sign-in again. No refresh token is issued by the current backend; expired sessions use device sign-in again. Signing into the same account restores purchases after reinstall or on another Mac. Account authentication is required infrastructure, not supplied by Stripe/PayPal payment accounts.

The client starts refresh on launch/sign-in, foregrounding, and every 30 seconds while signed in. After checkout opens it additionally checks every five seconds for up to five minutes, stopping early on verified access. Free responses during that window keep the pending UI; users can resume checkout or restore afterward. Restore is independent of offer catalog availability. It keeps a maximum 60-second verified lease in memory, bounded by subscription expiry. There is no defaults/disk unlock flag. A backend outage preserves the last verified entitlement object and shows an unavailable message; it does not extend its lease. After expiry, paid customization remains unavailable until verification succeeds. Sign-out clears the session and grant. Provider failures never mint new access. Modifying an unsigned/patched desktop binary is outside this protection; protected downloads must enforce membership server-side too.

Stripe fulfillment retrieves the Checkout Session, verifies its stored reference and paid status, and checks charge refund/dispute status or the active subscription's paid invoice/period. PayPal captures only server-created approved orders and re-fetches completed captures; subscriptions require ACTIVE status, a payment record, no failed payments, and a future billing boundary. Trials are not supported by this policy. Replayed/out-of-order webhooks re-fetch canonical status rather than replaying old grants. Refunds/disputes conservatively suspend affected memberships for operator review.

## Sandbox setup

1. Create an isolated Python environment, install `Backend/requirements.lock`, and supply variables from `Backend/.env.example` through your service's secret/environment manager. No real `.env` is included, and the service does not auto-load one.
2. Configure the OIDC issuer, trusted JWKS URL, device/token URLs, client ID and API audience (`OIDC_*`). Use HTTPS. Enable device authorization, RS256 JWT API access tokens and suitable account recovery in your identity provider. Never use an ID token as an API bearer token.
3. Set `PUBLIC_URL` to your HTTPS service origin and `PAYMENTS_DB` to a persistent private database path. Launch from repository root: `uvicorn Backend.server:app --host 127.0.0.1 --port 8000`. Place an HTTPS reverse proxy in front.
4. **Stripe Dashboard, test mode:** create an “Akito Station PRO Membership” product with a one-time price and, optionally, a recurring price. Set `STRIPE_PRICE_ID` and `STRIPE_SUBSCRIPTION_PRICE_ID`; put the test secret key in `STRIPE_SECRET_KEY` on the server only. Configure the customer portal's cancellation/payment-method settings. Add `https://YOUR_SERVICE/webhooks/stripe` with these events: `checkout.session.completed`, `checkout.session.async_payment_succeeded`, `checkout.session.async_payment_failed`, `checkout.session.expired`, `customer.subscription.created`, `customer.subscription.updated`, `customer.subscription.deleted`, `invoice.paid`, `invoice.payment_failed`, `charge.refunded`, `charge.dispute.created`. Store its signing secret as `STRIPE_WEBHOOK_SECRET`.
5. **PayPal Developer Dashboard, sandbox:** create a REST app linked to your sandbox business account; set `PAYPAL_CLIENT_ID`, `PAYPAL_CLIENT_SECRET`, `PAYPAL_MERCHANT_ID`, `PAYPAL_CURRENCY` and `PAYPAL_AMOUNT`. Leave `PAYPAL_LIVE=false`. For subscriptions create a product and an ACTIVE fixed-price recurring plan, without trial cycles, in the sandbox subscription tools/API; set `PAYPAL_PLAN_ID`. Add `https://YOUR_SERVICE/webhooks/paypal` to this same REST app. Subscribe to `CHECKOUT.ORDER.APPROVED`, `PAYMENT.CAPTURE.COMPLETED`, `PAYMENT.CAPTURE.DENIED`, `PAYMENT.CAPTURE.REFUNDED`, `PAYMENT.CAPTURE.REVERSED`, `BILLING.SUBSCRIPTION.ACTIVATED`, `BILLING.SUBSCRIPTION.UPDATED`, `BILLING.SUBSCRIPTION.CANCELLED`, `BILLING.SUBSCRIPTION.SUSPENDED`, `BILLING.SUBSCRIPTION.EXPIRED`, `BILLING.SUBSCRIPTION.PAYMENT.FAILED`, `PAYMENT.SALE.COMPLETED`, `PAYMENT.SALE.REFUNDED`, `PAYMENT.SALE.REVERSED`, and `CUSTOMER.DISPUTE.CREATED`. Set its webhook ID as `PAYPAL_WEBHOOK_ID`.
6. Enable `ENABLE_ONE_TIME=true` and/or `ENABLE_SUBSCRIPTION=true`. Both providers appear in one picker when configured. Checkout displays the provider's final price, billing schedule and consent terms.
7. Build with `AKITO_API_BASE_URL=https://akito-station-backend.onrender.com bash Scripts/build.sh release public`. For Xcode, set the public URL in `Resources/Public-Info.plist`, then use the Public Release scheme. The shipped public URL defaults to `https://akito-station-backend.onrender.com`; the build script preserves the plist value unless `AKITO_API_BASE_URL` is supplied. The developer plist and developer app are unaffected.
8. Use Stripe test payment details and PayPal sandbox buyer accounts. Verify both one-time and recurring flows, failed/pending payment, webhook retries/reordering, cancellation, renewal, refunds, disputes, expired token, outage, sign-out, and restore on a second Mac. Closing the success page must not prevent restoration. A return URL alone must never unlock PRO. PayPal simulator events cannot pass the remote signature-verification endpoint; use actual sandbox transactions for end-to-end tests.

## Tests

```
Backend/.venv/bin/python -m unittest Backend.test_entitlements Backend.test_providers Backend.test_login -v
CLANG_MODULE_CACHE_PATH=/tmp/akito-station-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/akito-station-swift-cache AKITO_EDITION=public swift test --disable-sandbox --build-system native --scratch-path /tmp/akito-station-public-build --filter 'PaymentTests|FeatureAccessTests'
bash Scripts/build.sh release public
```

Offline tests inject Stripe/PayPal/backend responses and cover free, PRO, active/expired subscription, failed/pending payment, restore, outage, refunds, ownership mismatch, lease expiry and HTTPS configuration. They do not contact payment providers. Mock HTTP device login, slow-down, denied/expired login, and missing-Bearer routes are also covered. Real JWT/JWKS, webhook delivery and actual sandbox transactions still need the configured deployment; they are not proven by these tests.

## Production and security review

Deploy and test sandbox first. Before enabling live checkout, configure a real membership/support policy, privacy/terms links, remove unavailable benefit claims, durable backups, monitoring, rate limits (especially login and checkout), request/body size limits, and secret rotation. Do not log Authorization headers, device codes or provider credentials. Pin/lock audited Python dependencies for deployment. Keep the service database outside the public document root and repository.

The reference service intentionally favors simple canonical verification: it rechecks provider records on each refresh and scans provider purchases during webhooks. For production volume, replace this with a durable deduplicated webhook queue, indexed event-to-purchase routing, retry/dead-letter handling and a scheduled reconciliation worker. Add HTTP/auth/signature integration tests and test multi-worker checkout races before launch. Provider idempotency keys are persisted and reused for six hours; ambiguous requests older than that need operator reconciliation before another purchase. One-time PayPal order retention and historic restoration must be validated against the account's API retention limits. Unrouteable PayPal subscription refunds return a retryable error and require operator attention; disputed/refunded subscriptions stay blocked until manually reviewed. Stripe subscription refunds conservatively block subscriptions associated with that customer. These are reference-service operational limits, not production certification.

Then create **live** Stripe prices, portal configuration and webhook destination/secrets, and a **live** PayPal app, business merchant ID, recurring plan and webhook ID. Store live secrets only on the server; set `PAYPAL_LIVE=true`, use a separate live database and deploy the verified HTTPS URL in the public app. Perform a controlled live purchase/refund and restore test before general release. No production credentials or live purchases were created by this implementation.

Only the HTTPS API origin belongs in the app. Public OAuth/client IDs are not secrets, but are kept server-side in this template. Stripe secret keys, PayPal client secrets, webhook signing secrets, OIDC signing/private keys and privileged tokens must never enter the app, plist, build artifacts or Git repository. `.gitignore` excludes local environment/credential/key files; it does not replace secret scanning.

## Changing pricing

Change server price/plan IDs or PayPal amount/currency to affect new purchases. Toggle the two `ENABLE_*` switches to hide either model without changing the app. Existing purchases retain their stored provider references and continue to verify even when their offer is hidden; do not delete provider products/history or the database. Model changes do not automatically migrate existing subscriptions. Manage migrations in provider dashboards with customer consent and test restore afterward.

Provider references: [Stripe hosted Checkout fulfillment](https://docs.stripe.com/checkout/fulfillment), [PayPal Orders](https://developer.paypal.com/api/orders/v2), [PayPal Subscriptions](https://developer.paypal.com/api/subscriptions/v1), [PayPal webhook verification](https://developer.paypal.com/api/rest/webhooks/rest/).

## Render / Auth0 deployment checkpoint (2026-09-23)

A live `POST https://akito-station-backend.onrender.com/login/start` returned device authorization fields successfully. No login code/token was printed or saved. The former “Payment provider unavailable” response was not reproduced. `GET /offers` advertised only `paypal:oneTime`; Stripe and subscriptions were not advertised. This proves startup/catalog availability, not completed authentication, charging, webhook delivery, or restoration.

Render environment inspection was not available in this workspace, so no specific missing secret is asserted. Verify these exact settings in Render:

- `PUBLIC_URL=https://akito-station-backend.onrender.com`; `PAYMENTS_DB` must point to a persistent Render disk, not the ephemeral deploy filesystem.
- Auth0 Native application with Device Code grant enabled: `OIDC_CLIENT_ID` (native application ID), `OIDC_ISSUER=https://YOUR_AUTH0_DOMAIN/` (including trailing slash), `OIDC_JWKS_URL=https://YOUR_AUTH0_DOMAIN/.well-known/jwks.json`, `OIDC_DEVICE_URL=https://YOUR_AUTH0_DOMAIN/oauth/device/code`, `OIDC_TOKEN_URL=https://YOUR_AUTH0_DOMAIN/oauth/token`, and `OIDC_AUDIENCE` equal to the Auth0 API identifier. The API must use RS256. The native flow needs no client secret. The backend now propagates device-flow slow-down intervals; redeploy `Backend/server.py` to apply this behavior.
- Stripe one-time checkout requires `ENABLE_ONE_TIME=true`, `STRIPE_SECRET_KEY`, `STRIPE_PRICE_ID`; configure `STRIPE_WEBHOOK_SECRET` for `https://akito-station-backend.onrender.com/webhooks/stripe`. The catalog cannot reveal which Stripe setting is absent. Optional subscriptions require `ENABLE_SUBSCRIPTION=true`, `STRIPE_SUBSCRIPTION_PRICE_ID`, and the Stripe customer portal.
- PayPal sandbox: retain `PAYPAL_LIVE=false` and the already configured `PAYPAL_WEBHOOK_ID`. Confirm `PAYPAL_CLIENT_ID`, `PAYPAL_CLIENT_SECRET`, `PAYPAL_MERCHANT_ID`, `PAYPAL_AMOUNT`, `PAYPAL_CURRENCY`, and webhook URL `https://akito-station-backend.onrender.com/webhooks/paypal` belong to the same sandbox business app. Optional subscriptions additionally require `PAYPAL_PLAN_ID` and `ENABLE_SUBSCRIPTION=true`.
- Existing website authorization-code routes separately require `OIDC_WEB_CLIENT_ID`, `OIDC_WEB_CLIENT_SECRET` and the registered callback `https://akito-station-backend.onrender.com/auth/callback`. They are not used by the native app and their secrets must remain server-side.

Complete a sandbox sign-in, checkout, webhook confirmation and second-device restore for each provider before claiming end-to-end readiness. No live charge was made. Switching PayPal to live requires a separate live app, merchant/plan/webhook configuration; do not merely flip the sandbox flag.
