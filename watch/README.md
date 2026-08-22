# AgentTap — VibePulse on your wrist

Glanceable Claude/Codex quota and **Needs You** answering on an Apple Watch.
AgentTap is a native watchOS client of the VibePulse tokenserver — the same
LAN service the AMOLED panel polls, speaking the same endpoints and the same
v2 signed-verdict protocol. Everything stays on your local network; there is
no account and nothing is collected.

## What you need

| Thing | Why |
|---|---|
| A Mac signed in to **Claude Code** | The tokenserver reads *your* Claude quota from your local login — that is the entire "link to your Claude". No API key, no account. |
| Python 3.11+ | Runs the tokenserver. Pure stdlib — nothing to install. |
| Xcode 26+ | Builds the watch app. Free. |
| An Apple Watch paired to an iPhone | watchOS 10 or newer. |
| Everything on the same WiFi | The watch talks to the Mac directly over the LAN. |

## Setup — two commands

**1. The computer** (from the repository root):

```sh
python3 tools/tokenserver/tokenserver.py &
python3 tools/vibepulse_setup.py watch
```

The guided `watch` command does everything the computer needs: turns on
Claude answering, asks the one real question (may bounded prompt text reach
your devices? — no is the private default), installs the Claude Code hooks
into `~/.claude/settings.json` (safe merge, backup written, re-runs change
nothing), optionally sets the tokenserver to start at login, verifies the
running server, and ends by printing a pairing code for step 3. Every step
is idempotent.

**2. The app**:

```sh
watch/setup.sh
```

Installs XcodeGen if needed, bakes your device key and server address into a
gitignored file, generates the project, and opens Xcode. One-time there: pick
your Team under *Signing & Capabilities*, choose your watch as the run
destination (iPhone plugged in), press Run. Free Apple IDs re-sign every
7 days; a paid developer account lifts that.

**3. First launch**: the quota rings appear within a poll or two. If you
built with your own key (step 2 does this), answering already works —
nothing to type. Done.

## Pairing (for a build without your key)

A copy of the app built without a baked key — someone else's build, or
`xcodebuild AGENTTAP_NO_KEY=1` — starts **display-only** and pairs at
runtime:

1. Computer: `python3 tools/vibepulse_setup.py pair` prints a **6-digit
   code** — 60 seconds, one use, five guesses. (Creates the key file first
   if this computer has none.)
2. Watch: gear → *Pairing* → enter the code → **Pair** → "Paired —
   answering is on". The key lands in the watch keychain.

The code proves you were at both devices inside one minute; the key itself
never appears on either screen. Arming works only from the computer itself.
*Unpair* forgets the key; changing `~/.vibepulse-device-key` and re-pairing
rotates it everywhere.

The server address rarely needs typing either: the tokenserver announces
itself on the network, and discovered Macs appear in the watch's Settings as
tap-to-select rows. (A raw `http://<ip>:8737` still works when mDNS
doesn't.)

## Using it

- **Glance** — Claude session / week / model-week and Codex week, with reset
  countdowns. Dashes mean the data honestly is not there; dimmed + STALE
  means last-known-good.
- **Agents** — live rows per provider: the *folder name* each agent works
  in, its state, its model. Waiting agents jump to the top in accent color.
- **Needs You** — when a Claude session asks a question or wants permission,
  a full-screen card takes over: countdown ring, APPROVE (only when the
  server's safe-command tier allows it), DENY (approvals only), LEAVE IT.
  Long-press the header for the panic: deny everything pending.
- **Complication** — the AgentTap gauge on a watch face shows the tightest
  weekly quota at a wrist-raise, wearing its staleness openly.
- **Demo mode** — Settings → Demo mode fills every screen with sample data
  and a scripted decision, no computer needed. Try the app before setting
  anything up.

**Honest limitation:** watchOS budgets background wakeups, so answering is a
foreground feature — the app polls at 1 Hz while open. A 120-second decision
window cannot be reliably caught in the background without push
infrastructure. The terminal fallback always stands, and the watch and the
AMOLED panel coexist: first valid answer wins, the other clears.

## When it does not work

| Symptom | Cause | Fix |
|---|---|---|
| Rings all dashes, "Mac unreachable" | Wrong server, Mac asleep, different WiFi | Tap your Mac's name under Settings → Server, or enter a raw IP; check `curl localhost:8737/` on the Mac |
| "Mac unreachable" with `-1001 timedOut` on a physical watch | watchOS often hangs resolving `.local` hostnames | Enter the Mac's raw IP under Settings → Server (`ip:8737` is enough — the scheme is added). Give the Mac a DHCP reservation in your router so the IP holds |
| Your Mac never appears in Server list | mDNS blocked, or zeroconf not installed on the Mac | Type the address once — discovery is a convenience, not a requirement |
| Rings show but Codex dashed | No Codex source on the Mac | Normal — the halves are independent |
| Card appears but no APPROVE | Detail off, item outside the safe tier, or unpaired | Re-run the `watch` wizard (choose detail), pair; some items are terminal-only by design |
| Pair says "No code is active" | 60 s passed, code used, or five wrong guesses | Run `pair` again for a fresh code |
| Answer rejected: "signature rejected" | Watch clock skew > 90 s, or key mismatch | Sync the watch clock; re-pair |
| Answer rejected: "no such pending interaction" | The panel or terminal answered first, or it expired | Nothing to fix — first valid answer wins |
| Card never appears | Hooks not installed, or an old Claude session | The wizard installs hooks; they load only in sessions started afterwards |
| Quota rings never move after setup | Tokenserver started before the wizard ran | Restart it (autostart from the wizard handles this at login) |

## Tests

```sh
xcodebuild test -project AgentTap.xcodeproj -scheme AgentTap \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)'
```

Crypto is pinned against vectors generated from the tokenserver's reference
implementation (`tools/tokenserver/interactions.py`), including canonical-view
digests with non-ASCII and escaping edge cases. The client recomputes the
view digest from what it decoded and refuses to sign anything else — "I
approved this screen" is literally true. Computer-side behavior (wizard,
hooks merge, pairing gate, Claude-only installs) is covered by
`test/test_vibepulse_setup_watch.py` and `test/test_pairing.py` in the
repository suite.

## App Store

Everything needed for a store submission lives in
[appstore/](appstore/README.md): reviewer notes with the demo-mode
walkthrough, privacy policy, listing copy, screenshots, and the archive
commands. Only enrollment and upload require the account holder.
