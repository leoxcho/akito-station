import unittest
from types import SimpleNamespace
from unittest.mock import Mock
from .providers import provider_state

class Object(dict):
    def __getattr__(self, key):
        return self[key]

class ProviderTests(unittest.TestCase):
    def setUp(self):
        self.row = dict(id="owned", owner="user", provider="stripe", model="oneTime", remote="remote", blocked=0)
        self.stripe = SimpleNamespace(checkout=SimpleNamespace(Session=Mock()), PaymentIntent=Mock(), Subscription=Mock())
        self.paypal = Mock()
        self.session = Object(client_reference_id="owned", payment_status="paid", payment_intent="intent", status="complete", subscription="subscription")
        self.stripe.checkout.Session.retrieve.return_value = self.session
        self.stripe.PaymentIntent.retrieve.return_value = Object(status="succeeded", latest_charge=Object(refunded=False, disputed=False, amount_refunded=0))

    def check(self):
        return provider_state(self.row, self.stripe, self.paypal)

    def test_stripe_paid_and_refund(self):
        self.assertEqual(self.check()[0], "pro")
        self.stripe.PaymentIntent.retrieve.return_value.latest_charge["amount_refunded"] = 1
        self.assertEqual(self.check()[0], "free")

    def test_stripe_ownership_rejected(self):
        self.session["client_reference_id"] = "someone-else"
        with self.assertRaises(ValueError): self.check()

    def test_stripe_failed_pending_and_subscription(self):
        self.session["payment_status"] = "unpaid"
        self.assertEqual(self.check()[0], "paymentPending")
        self.session["status"] = "expired"
        self.assertEqual(self.check()[0], "free")
        self.row["model"] = "subscription"
        self.stripe.Subscription.retrieve.return_value = Object(status="active", latest_invoice=Object(status="paid"), items={"data": [{"current_period_end": 2000000000}]})
        self.assertEqual(self.check()[0], "subscriptionActive")
        self.stripe.Subscription.retrieve.return_value["status"] = "past_due"
        self.assertEqual(self.check()[0], "subscriptionExpired")

    def test_paypal_order_capture_and_refund(self):
        self.row["provider"] = "paypal"
        order = {"status": "COMPLETED", "purchase_units": [{"custom_id": "owned", "amount": {"value": "20.00", "currency_code": "USD"}, "payments": {"captures": [{"id": "capture"}]}}]}
        self.paypal.side_effect = [{"status": "APPROVED"}, {"status": "COMPLETED"}, order, {"status": "COMPLETED", "amount": {"value": "20.00", "currency_code": "USD"}}]
        self.assertEqual(self.check()[0], "pro")
        self.assertEqual(self.paypal.call_args_list[1].args, ("POST", "/v2/checkout/orders/remote/capture", {}, "owned-capture"))
        self.paypal.side_effect = [order, {"status": "PARTIALLY_REFUNDED"}]
        self.assertEqual(self.check()[0], "free")

    def test_paypal_subscription_requires_payment_and_future_period(self):
        self.row.update(provider="paypal", model="subscription")
        self.paypal.return_value = {"status": "ACTIVE", "custom_id": "owned", "billing_info": {}}
        self.assertEqual(self.check()[0], "subscriptionExpired")
        self.paypal.return_value["billing_info"] = {"last_payment": {"amount": {"value": "5.00"}}, "next_billing_time": "2030-01-01T00:00:00Z"}
        self.assertEqual(self.check()[0], "subscriptionActive")
        self.row["blocked"] = 1
        self.assertEqual(self.check()[0], "subscriptionExpired")

    def test_provider_unavailable_does_not_return_grant(self):
        self.stripe.checkout.Session.retrieve.side_effect = TimeoutError()
        with self.assertRaises(TimeoutError): self.check()

if __name__ == "__main__": unittest.main()
