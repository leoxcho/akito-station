"""Provider-independent entitlement policy; no network or credentials."""
from datetime import timedelta

def aggregate(states, now):
    # Short in-memory client lease; no writable preference or disk cache grants PRO.
    lease = now + timedelta(seconds=60)
    if any(state == "pro" for state, _ in states):
        return {"state": "pro", "validUntil": lease.isoformat(timespec="seconds")}
    active = [end for state, end in states if state == "subscriptionActive" and end and end > now]
    if active:
        return {"state": "subscriptionActive", "validUntil": min(lease, max(active)).isoformat(timespec="seconds")}
    state = "subscriptionExpired" if any(s in ("subscriptionExpired", "subscriptionActive") for s, _ in states) else "paymentPending" if any(s == "paymentPending" for s, _ in states) else "free"
    return {"state": state, "validUntil": None}
