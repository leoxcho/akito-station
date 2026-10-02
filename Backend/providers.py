"""Verification against canonical provider responses; dependencies injected for offline tests."""
from datetime import datetime, timezone
from decimal import Decimal

def iso(value):
    return datetime.fromisoformat(value.replace("Z", "+00:00"))

def provider_state(row, stripe, paypal, record=lambda remote:None):
    if row["blocked"]:
        return "subscriptionExpired" if row["model"] == "subscription" else "free", None
    if not row["remote"]:
        return "free", None
    if row["provider"] == "stripe":
        session = stripe.checkout.Session.retrieve(row["remote"])
        if session.client_reference_id != row["id"]:
            raise ValueError("Purchase ownership mismatch")
        for key in ["id","customer","payment_intent","subscription"]: record(session.get(key))
        if row["model"] == "oneTime":
            if session.payment_status != "paid":
                return ("free" if session.status == "expired" else "paymentPending"), None
            intent = stripe.PaymentIntent.retrieve(session.payment_intent, expand=["latest_charge"])
            charge = intent.latest_charge
            if charge: record(charge.get("id") if hasattr(charge,"get") else getattr(charge,"id",None))
            return ("pro" if intent.status == "succeeded" and charge and not charge.refunded and not charge.disputed and charge.amount_refunded == 0 else "free"), None
        if not session.subscription:
            return "paymentPending", None
        subscription = stripe.Subscription.retrieve(session.subscription, expand=["latest_invoice"])
        if subscription.status != "active" or not subscription.latest_invoice or subscription.latest_invoice.status != "paid":
            return "subscriptionExpired", None
        periods = [x.get("current_period_end", subscription.get("current_period_end", 0)) for x in subscription["items"]["data"]]
        return "subscriptionActive", datetime.fromtimestamp(min(periods or [0]), timezone.utc)
    if row["model"] == "subscription":
        subscription = paypal("GET", "/v1/billing/subscriptions/" + row["remote"])
        if subscription.get("custom_id") != row["id"]:
            raise ValueError("Purchase ownership mismatch")
        record(subscription.get("id"))
        billing = subscription.get("billing_info", {})
        if subscription["status"] != "ACTIVE" or not billing.get("last_payment") or not billing.get("next_billing_time") or billing.get("failed_payments_count", 0) > 0:
            return ("paymentPending" if subscription["status"] in ("APPROVAL_PENDING", "APPROVED") else "subscriptionExpired"), None
        return "subscriptionActive", iso(billing["next_billing_time"])
    order = paypal("GET", "/v2/checkout/orders/" + row["remote"])
    if order["status"] == "APPROVED":
        paypal("POST", "/v2/checkout/orders/" + row["remote"] + "/capture", {}, row["id"] + "-capture")
        order = paypal("GET", "/v2/checkout/orders/" + row["remote"])
    if order["status"] != "COMPLETED":
        return ("free" if order["status"] == "VOIDED" else "paymentPending"), None
    units = order.get("purchase_units", [])
    if len(units) != 1 or units[0].get("custom_id") != row["id"]:
        raise ValueError("Purchase ownership mismatch")
    # Validate against the original provider order, not today's configurable price.
    unit = units[0]
    captures = unit.get("payments", {}).get("captures", [])
    if not captures:
        return "free", None
    total = Decimal("0")
    for capture in captures:
        record(capture["id"])
        live = paypal("GET", "/v2/payments/captures/" + capture["id"])
        if live["status"] != "COMPLETED" or live["amount"]["currency_code"] != unit["amount"]["currency_code"]:
            return "free", None
        total += Decimal(live["amount"]["value"])
    return ("pro" if total == Decimal(unit["amount"]["value"]) else "free"), None

