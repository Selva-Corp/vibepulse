"""The push relay Worker's privacy contract, held by source assertions."""
import pathlib
import unittest

WORKER = (pathlib.Path(__file__).resolve().parents[1]
          / "tools" / "push-relay" / "worker.js").read_text()


class PushRelayWiringTests(unittest.TestCase):
    def test_alert_is_fixed_and_generic(self):
        self.assertIn('title: "Needs You"', WORKER)
        self.assertIn('body: "An agent is waiting for you"', WORKER)
        # No request-derived value may reach the payload.
        self.assertNotIn("body.project", WORKER)
        self.assertNotIn("body.prompt", WORKER)

    def test_token_is_validated_and_never_logged(self):
        self.assertIn("/^[0-9a-f]{64}$/", WORKER)
        self.assertNotIn("console.log", WORKER)

    def test_rate_limit_and_environment_fallback_exist(self):
        self.assertIn("RATE_LIMIT_PER_MIN", WORKER)
        self.assertIn("api.development.push.apple.com", WORKER)
        self.assertIn("BadEnvironmentKeyInToken", WORKER)
