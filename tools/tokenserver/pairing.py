"""One-shot 6-digit pairing: hand the device key to a new panel/watch once.

The model mirrors how a TV pairs a remote: the person proves presence on BOTH
ends inside one short window. Arming happens only from this computer
(loopback route); claiming happens from the LAN with the 6 digits the
computer just displayed. The key that changes hands is the same shared
device key the panel compiles in — pairing is a delivery mechanism for it,
not a new trust root. One code, one claim, sixty seconds, five guesses.
"""

from __future__ import annotations

import hmac
import secrets
import threading
import json
from pathlib import Path
from typing import Callable, Optional


ARM_WINDOW_S = 60.0
MAX_ATTEMPTS = 5
_CODE_DIGITS = 6


class PairingGate:
    """In-memory pairing state. Dies with the server process, on purpose."""

    def __init__(self, key_provider: Callable[[], Optional[str]]) -> None:
        self._key_provider = key_provider
        self._lock = threading.Lock()
        self._code: Optional[str] = None
        self._expires_at = 0.0
        self._attempts_left = 0

    def arm(self, now: float) -> Optional[dict]:
        """Generate a fresh code. Returns None if no key exists to hand out."""
        if not self._key_provider():
            return None
        code = "".join(
            str(secrets.randbelow(10)) for _ in range(_CODE_DIGITS))
        with self._lock:
            self._code = code
            self._expires_at = now + ARM_WINDOW_S
            self._attempts_left = MAX_ATTEMPTS
        return {"code": code, "expires_in_s": int(ARM_WINDOW_S)}

    def claim(self, code: object, now: float) -> tuple[Optional[str], str]:
        """One guess. Returns (device_key, "ok") or (None, reason).

        Reasons: "not armed" (nothing to claim — also after expiry, a
        successful claim, or exhausted attempts), "bad code" (guess wrong,
        attempts remain), "no key" (key vanished between arm and claim).
        """
        if not isinstance(code, str) or len(code) != _CODE_DIGITS or \
                not code.isdigit():
            # Malformed input burns no attempt: it cannot be a guess from
            # the code space, only a broken client.
            return None, "not armed" if self._armed(now) is False else "bad request"
        with self._lock:
            if self._code is None or now >= self._expires_at or \
                    self._attempts_left <= 0:
                self._disarm_locked()
                return None, "not armed"
            self._attempts_left -= 1
            matched = hmac.compare_digest(self._code, code)
            if not matched:
                if self._attempts_left <= 0:
                    self._disarm_locked()
                return None, "bad code"
            self._disarm_locked()
        key = self._key_provider()
        if not key:
            return None, "no key"
        return key, "ok"

    def _armed(self, now: float) -> bool:
        with self._lock:
            return (self._code is not None and now < self._expires_at and
                    self._attempts_left > 0)

    def _disarm_locked(self) -> None:
        self._code = None
        self._expires_at = 0.0
        self._attempts_left = 0


def relay_handout(url: Optional[str], mailbox: Optional[str],
                  home: Optional[Path] = None) -> Optional[dict]:
    """The relay credentials pairing may hand a device, or None.

    Panel-role only — the Mac token never leaves this computer. Handed out
    solely through a successful pairing claim, which already proves the
    same possession the device key itself requires.
    """
    if not url or not mailbox:
        return None
    token_path = (home or Path.home()) / \
        ".vibepulse-interaction-relay-panel-token"
    try:
        token = token_path.read_text().strip()
    except OSError:
        return None
    if len(token) != 43:
        return None
    return {"url": url, "mailbox": mailbox, "panel_token": token}


def numbers_handout(state_dir: Path) -> Optional[str]:
    """The numbers-relay URL (secret embedded) pairing may hand a device."""
    try:
        raw = json.loads((state_dir / "numbers-relay.json").read_text())
    except (OSError, ValueError):
        return None
    url = raw.get("url")
    if isinstance(url, str) and url.startswith("https://") and "/u/" in url:
        return url
    return None
