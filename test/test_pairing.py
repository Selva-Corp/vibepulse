"""PairingGate: one code, one claim, sixty seconds, five guesses."""
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]
                       / "tools" / "tokenserver"))
from pairing import ARM_WINDOW_S, MAX_ATTEMPTS, PairingGate  # noqa: E402

KEY = "ab" * 32


class PairingGateTest(unittest.TestCase):
    def gate(self, key=KEY):
        return PairingGate(lambda: key)

    def test_arm_then_claim_hands_over_the_key_once(self):
        gate = self.gate()
        armed = gate.arm(now=1000.0)
        self.assertEqual(len(armed["code"]), 6)
        self.assertTrue(armed["code"].isdigit())
        key, reason = gate.claim(armed["code"], now=1001.0)
        self.assertEqual((key, reason), (KEY, "ok"))
        # Single use: the same correct code is now worthless.
        self.assertEqual(gate.claim(armed["code"], now=1002.0),
                         (None, "not armed"))

    def test_claim_without_arm_or_after_expiry(self):
        gate = self.gate()
        self.assertEqual(gate.claim("123456", now=1.0), (None, "not armed"))
        armed = gate.arm(now=1000.0)
        late = 1000.0 + ARM_WINDOW_S
        self.assertEqual(gate.claim(armed["code"], now=late),
                         (None, "not armed"))

    def test_wrong_guesses_burn_attempts_then_disarm(self):
        gate = self.gate()
        armed = gate.arm(now=0.0)
        wrong = "000000" if armed["code"] != "000000" else "999999"
        for _ in range(MAX_ATTEMPTS - 1):
            self.assertEqual(gate.claim(wrong, now=1.0), (None, "bad code"))
        # Attempt cap: the last wrong guess disarms entirely...
        self.assertEqual(gate.claim(wrong, now=1.0), (None, "bad code"))
        # ...so even the RIGHT code is dead afterwards.
        self.assertEqual(gate.claim(armed["code"], now=2.0),
                         (None, "not armed"))

    def test_malformed_input_burns_no_attempt(self):
        gate = self.gate()
        armed = gate.arm(now=0.0)
        for bad in (None, 123456, "12345", "1234567", "12345a", ""):
            key, reason = gate.claim(bad, now=1.0)
            self.assertIsNone(key)
        # All five attempts must still be available for the real code.
        self.assertEqual(gate.claim(armed["code"], now=2.0), (KEY, "ok"))

    def test_rearm_replaces_the_previous_code(self):
        gate = self.gate()
        first = gate.arm(now=0.0)
        second = gate.arm(now=1.0)
        if first["code"] != second["code"]:
            self.assertEqual(gate.claim(first["code"], now=2.0),
                             (None, "bad code"))
        self.assertEqual(gate.claim(second["code"], now=3.0), (KEY, "ok"))

    def test_no_key_no_pairing(self):
        gate = self.gate(key=None)
        self.assertIsNone(gate.arm(now=0.0))
        gate2 = self.gate(key="")
        self.assertIsNone(gate2.arm(now=0.0))


if __name__ == "__main__":
    unittest.main()
