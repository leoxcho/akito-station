import unittest
from datetime import datetime, timezone, timedelta
from .entitlements import aggregate

class EntitlementTests(unittest.TestCase):
    def setUp(self):
        self.now = datetime(2026, 1, 1, tzinfo=timezone.utc)

    def test_free(self):
        self.assertEqual(aggregate([], self.now), {"state": "free", "validUntil": None})

    def test_one_time_and_pending_do_not_remove_paid_membership(self):
        result = aggregate([("pro", None), ("paymentPending", None)], self.now)
        self.assertEqual(result["state"], "pro")
        self.assertEqual(datetime.fromisoformat(result["validUntil"]), self.now + timedelta(seconds=60))

    def test_subscription_lease_never_exceeds_paid_period(self):
        end = self.now + timedelta(seconds=10)
        self.assertEqual(aggregate([("subscriptionActive", end)], self.now)["validUntil"], end.isoformat())

    def test_expired_and_missing_period_fail_closed(self):
        for end in (None, self.now, self.now - timedelta(seconds=1)):
            self.assertEqual(aggregate([("subscriptionActive", end)], self.now)["state"], "subscriptionExpired")

    def test_pending_does_not_grant_access(self):
        self.assertEqual(aggregate([("paymentPending", None)], self.now), {"state": "paymentPending", "validUntil": None})

if __name__ == "__main__":
    unittest.main()
