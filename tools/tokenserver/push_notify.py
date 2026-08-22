"""APNs push for Needs You: the wrist learns the moment a prompt parks.

Kept in the project's spirit: the server core stays pure-stdlib. ES256 needs
the `cryptography` package (already an optional dependency of the encrypted
relay) and delivery uses the system `curl --http2` — both are probed at
startup and their absence just means "no push", never an error elsewhere.

Trust model: registering a token requires an HMAC over the token with the
shared device key — the same possession proof as answering. The notification
itself carries only what the detail setting allows; the verdict still
happens in the app against the digest-verified card.
"""

from __future__ import annotations

import base64
import hashlib
import hmac as hmac_mod
import json
import subprocess
import threading
import time
from pathlib import Path
from typing import Callable, Optional

TOKEN_RE_HEX = 64  # APNs device tokens are 32 bytes
FRESHNESS_S = 90.0
MAX_TOKENS = 4
JWT_LIFETIME_S = 40 * 60
CURL_TIMEOUT_S = 10

PROD_HOST = "https://api.push.apple.com"
SANDBOX_HOST = "https://api.development.push.apple.com"


def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


class ApnsConfig:
    def __init__(self, key_path: str, key_id: str, team_id: str,
                 topic: str) -> None:
        self.key_path = key_path
        self.key_id = key_id
        self.team_id = team_id
        self.topic = topic

    @classmethod
    def load(cls, path: Path) -> Optional["ApnsConfig"]:
        try:
            raw = json.loads(path.read_text())
            cfg = cls(raw["key_path"], raw["key_id"], raw["team_id"],
                      raw["topic"])
            if not Path(cfg.key_path).exists():
                return None
            return cfg
        except (OSError, ValueError, KeyError):
            return None


class ApnsSender:
    """Signs JWTs and delivers alerts; remembers which APNs environment
    (production vs sandbox) each token lives in."""

    def __init__(self, config: ApnsConfig, state_dir: Path,
                 run: Callable = subprocess.run, log=None) -> None:
        self.config = config
        self.state_path = state_dir / "push-tokens.json"
        self._run = run
        self._log = log
        self._lock = threading.Lock()
        self._jwt: Optional[str] = None
        self._jwt_at = 0.0

    # -- capability probes ------------------------------------------------
    @staticmethod
    def crypto_available() -> bool:
        try:
            from cryptography.hazmat.primitives.asymmetric import ec  # noqa
            return True
        except Exception:
            return False

    # -- token registry ---------------------------------------------------
    def _read_tokens(self) -> list[dict]:
        try:
            data = json.loads(self.state_path.read_text())
            return data if isinstance(data, list) else []
        except (OSError, ValueError):
            return []

    def _write_tokens(self, tokens: list[dict]) -> None:
        self.state_path.parent.mkdir(parents=True, exist_ok=True)
        self.state_path.write_text(json.dumps(tokens[-MAX_TOKENS:]))

    def register(self, token: str) -> None:
        with self._lock:
            tokens = [t for t in self._read_tokens()
                      if t.get("token") != token]
            tokens.append({"token": token, "env": "auto",
                           "at": int(time.time())})
            self._write_tokens(tokens)

    @staticmethod
    def verify_registration(secret: str, payload: dict,
                            now: Optional[float] = None) -> Optional[str]:
        """Returns the token when the HMAC proves key possession."""
        token = payload.get("token")
        ts = payload.get("ts")
        mac = payload.get("hmac")
        if not (isinstance(token, str) and len(token) == TOKEN_RE_HEX and
                all(c in "0123456789abcdef" for c in token)):
            return None
        if not isinstance(ts, int) or isinstance(ts, bool):
            return None
        if abs((now if now is not None else time.time()) - ts) > FRESHNESS_S:
            return None
        if not isinstance(mac, str):
            return None
        expected = hmac_mod.new(
            secret.encode(), f"push|register|{token}|{ts}".encode(),
            hashlib.sha256).hexdigest()
        if not hmac_mod.compare_digest(expected, mac):
            return None
        return token

    # -- JWT --------------------------------------------------------------
    def _bearer(self, now: float) -> Optional[str]:
        with self._lock:
            if self._jwt and now - self._jwt_at < JWT_LIFETIME_S:
                return self._jwt
        try:
            from cryptography.hazmat.primitives import hashes, serialization
            from cryptography.hazmat.primitives.asymmetric import ec
            from cryptography.hazmat.primitives.asymmetric.utils import (
                decode_dss_signature)
            key = serialization.load_pem_private_key(
                Path(self.config.key_path).read_bytes(), password=None)
            header = _b64url(json.dumps(
                {"alg": "ES256", "kid": self.config.key_id},
                separators=(",", ":")).encode())
            claims = _b64url(json.dumps(
                {"iss": self.config.team_id, "iat": int(now)},
                separators=(",", ":")).encode())
            signing_input = f"{header}.{claims}".encode()
            der = key.sign(signing_input, ec.ECDSA(hashes.SHA256()))
            r, s = decode_dss_signature(der)
            sig = _b64url(r.to_bytes(32, "big") + s.to_bytes(32, "big"))
            jwt = f"{header}.{claims}.{sig}"
        except Exception:
            if self._log:
                self._log.warning("APNs: kunde inte signera JWT")
            return None
        with self._lock:
            self._jwt = jwt
            self._jwt_at = now
        return jwt

    # -- delivery ---------------------------------------------------------
    def _deliver(self, host: str, token: str, payload: bytes,
                 jwt: str, expiry: int) -> tuple[int, str]:
        completed = self._run(
            ["curl", "-sS", "--http2", "-o", "-", "-w", "\n%{http_code}",
             "--max-time", str(CURL_TIMEOUT_S),
             "-H", f"authorization: bearer {jwt}",
             "-H", f"apns-topic: {self.config.topic}",
             "-H", "apns-push-type: alert",
             "-H", "apns-priority: 10",
             "-H", f"apns-expiration: {expiry}",
             "-d", payload.decode(),
             f"{host}/3/device/{token}"],
            capture_output=True, text=True, timeout=CURL_TIMEOUT_S + 5)
        out = (completed.stdout or "").strip().rsplit("\n", 1)
        body = out[0] if len(out) == 2 else ""
        try:
            status = int(out[-1])
        except (ValueError, IndexError):
            status = 0
        return status, body

    def notify(self, *, title: str, body: str, hold_s: int) -> None:
        """Fire-and-forget from a worker thread — never blocks a hook."""
        threading.Thread(
            target=self._notify_sync, args=(title, body, hold_s),
            daemon=True).start()

    def _notify_sync(self, title: str, body: str, hold_s: int) -> None:
        now = time.time()
        jwt = self._bearer(now)
        if jwt is None:
            return
        payload = json.dumps({"aps": {
            "alert": {"title": title, "body": body},
            "sound": "default",
            "interruption-level": "time-sensitive",
        }}, separators=(",", ":")).encode()
        expiry = int(now) + hold_s
        with self._lock:
            tokens = self._read_tokens()
        changed = False
        for entry in tokens:
            token = entry.get("token", "")
            env = entry.get("env", "auto")
            hosts = ([PROD_HOST, SANDBOX_HOST] if env == "auto"
                     else [PROD_HOST] if env == "prod" else [SANDBOX_HOST])
            for host in hosts:
                try:
                    status, resp = self._deliver(
                        host, token, payload, jwt, expiry)
                except Exception:
                    status, resp = 0, ""
                if status == 200:
                    resolved = "prod" if host == PROD_HOST else "sandbox"
                    if entry.get("env") != resolved:
                        entry["env"] = resolved
                        changed = True
                    if self._log:
                        self._log.info("APNs: Needs You-puff levererad (%s)",
                                       resolved)
                    break
                if ("BadDeviceToken" in resp or
                        "BadEnvironmentKeyInToken" in resp):
                    continue  # wrong environment — try the other
                if self._log:
                    self._log.warning("APNs: leverans misslyckades (%s %s)",
                                      status, resp[:120])
                break
            else:
                if self._log:
                    self._log.warning(
                        "APNs: båda miljöerna avvisade token — är nyckeln "
                        "skapad för både Sandbox & Production?")
        if changed:
            with self._lock:
                self._write_tokens(tokens)
