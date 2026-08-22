"""APNs push: registration auth, JWT shape, environment fallback."""
import hashlib
import hmac
import json
import pathlib
import sys
import tempfile
import time
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]
                       / "tools" / "tokenserver"))
from push_notify import ApnsConfig, ApnsSender, PROD_HOST, SANDBOX_HOST  # noqa: E402

KEY = "ab" * 32
TOKEN = "cd" * 32


def signed_registration(ts=None, token=TOKEN, key=KEY):
    ts = int(time.time()) if ts is None else ts
    mac = hmac.new(key.encode(), f"push|register|{token}|{ts}".encode(),
                   hashlib.sha256).hexdigest()
    return {"token": token, "ts": ts, "hmac": mac}


class RegistrationAuthTests(unittest.TestCase):
    def test_valid_signature_yields_token(self):
        self.assertEqual(
            ApnsSender.verify_registration(KEY, signed_registration()),
            TOKEN)

    def test_wrong_key_and_stale_ts_are_refused(self):
        payload = signed_registration(key="ef" * 32)
        self.assertIsNone(ApnsSender.verify_registration(KEY, payload))
        old = signed_registration(ts=int(time.time()) - 600)
        self.assertIsNone(ApnsSender.verify_registration(KEY, old))

    def test_malformed_tokens_are_refused(self):
        for bad in ("zz" * 32, "cd" * 16, 123, None):
            payload = signed_registration()
            payload["token"] = bad
            self.assertIsNone(
                ApnsSender.verify_registration(KEY, payload))
        boolts = signed_registration()
        boolts["ts"] = True
        self.assertIsNone(ApnsSender.verify_registration(KEY, boolts))


@unittest.skipUnless(ApnsSender.crypto_available(), "needs cryptography")
class JwtTests(unittest.TestCase):
    def test_jwt_verifies_with_the_public_key(self):
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import ec
        from cryptography.hazmat.primitives.asymmetric.utils import (
            encode_dss_signature)
        import base64
        key = ec.generate_private_key(ec.SECP256R1())
        with tempfile.TemporaryDirectory() as tmp:
            pem = pathlib.Path(tmp) / "AuthKey_TESTKEY123.p8"
            pem.write_bytes(key.private_bytes(
                serialization.Encoding.PEM,
                serialization.PrivateFormat.PKCS8,
                serialization.NoEncryption()))
            sender = ApnsSender(
                ApnsConfig(str(pem), "TESTKEY123", "TEAMID9999", "com.x.y"),
                pathlib.Path(tmp))
            jwt = sender._bearer(time.time())
            self.assertIsNotNone(jwt)
            head, claims, sig = jwt.split(".")
            def unb64(s):
                return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))
            self.assertEqual(json.loads(unb64(head)),
                             {"alg": "ES256", "kid": "TESTKEY123"})
            self.assertEqual(json.loads(unb64(claims))["iss"], "TEAMID9999")
            raw = unb64(sig)
            der = encode_dss_signature(
                int.from_bytes(raw[:32], "big"),
                int.from_bytes(raw[32:], "big"))
            key.public_key().verify(
                der, f"{head}.{claims}".encode(),
                ec.ECDSA(hashes.SHA256()))  # raises on mismatch


@unittest.skipUnless(ApnsSender.crypto_available(), "needs cryptography")
class DeliveryTests(unittest.TestCase):
    def test_bad_device_token_falls_back_to_sandbox_and_remembers(self):
        from cryptography.hazmat.primitives import serialization
        from cryptography.hazmat.primitives.asymmetric import ec
        key = ec.generate_private_key(ec.SECP256R1())
        with tempfile.TemporaryDirectory() as tmp:
            pem = pathlib.Path(tmp) / "k.p8"
            pem.write_bytes(key.private_bytes(
                serialization.Encoding.PEM,
                serialization.PrivateFormat.PKCS8,
                serialization.NoEncryption()))
            calls = []

            class Completed:
                def __init__(self, stdout):
                    self.stdout = stdout
                    self.returncode = 0

            def fake_run(argv, **kw):
                calls.append(argv[-1])
                if argv[-1].startswith(PROD_HOST):
                    return Completed(
                        '{"reason":"BadDeviceToken"}\n400')
                return Completed("\n200")

            sender = ApnsSender(
                ApnsConfig(str(pem), "TESTKEY123", "TEAM", "com.x.y"),
                pathlib.Path(tmp), run=fake_run)
            sender.register(TOKEN)
            sender._notify_sync("Needs You", "vibepulse", 120)
            self.assertTrue(calls[0].startswith(PROD_HOST))
            self.assertTrue(calls[1].startswith(SANDBOX_HOST))
            saved = json.loads((pathlib.Path(tmp) /
                                "push-tokens.json").read_text())
            self.assertEqual(saved[0]["env"], "sandbox")
            # Next send goes straight to sandbox.
            sender._notify_sync("Needs You", "vibepulse", 120)
            self.assertTrue(calls[2].startswith(SANDBOX_HOST))
            self.assertEqual(len(calls), 3)


if __name__ == "__main__":
    unittest.main()
