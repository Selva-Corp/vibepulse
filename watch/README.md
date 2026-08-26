# AgentTap — your AI agents, on your wrist

Glanceable Claude Code / Codex quota, live agent activity, and **Needs
You** answering from an Apple Watch — at home over your own network, and
anywhere else through push notifications and end-to-end-encrypted relays
you own. No account exists, nothing is collected, and every cloud piece is
optional and yours.

This README is the complete setup, start to finish. Times are honest.

---

## What you need before starting

| Thing | Why |
|---|---|
| A Mac signed in to **Claude Code** | That login IS the link to your Claude — no API key, ever |
| Python 3.11+ (`python3 --version`) | Runs the tokenserver; pure stdlib |
| This repository (`git clone …`) | The tokenserver and setup tools live here |
| **AgentTap** from the App Store | The watch app ($3.99) |
| Apple Watch, watchOS 10+, paired iPhone | And on the same WiFi as the Mac for first-time setup |

---

## Part 1 — The laptop (≈3 minutes)

From the repository root:

```sh
python3 tools/tokenserver/tokenserver.py &
python3 tools/vibepulse_setup.py watch
```

The guided `watch` command does everything this side needs:

- turns on Claude answering,
- asks the one real privacy question — *may bounded prompt text reach
  your devices?* (no is the default; without it the watch shows only THAT
  something waits),
- installs the Claude Code hooks into `~/.claude/settings.json` (safe
  merge, backup written, re-runs change nothing),
- offers start-at-login for the tokenserver,
- verifies the running server, and prints a **6-digit pairing code**.

Keep that code visible — it expires in 60 seconds (re-run
`python3 tools/vibepulse_setup.py pair` any time for a fresh one).

## Part 2 — The watch (≈1 minute)

1. Open **AgentTap**. First launch shows **"Choose your computer"** with
   your Mac already discovered — tap it. The quota rings light up right
   there; viewing needs no pairing.
2. Tap **Allow** on the notification prompt.
3. Gear → **Pairing** → enter the 6 digits → **"Paired — answering is
   on."**

That single code delivers everything the watch will ever need: the
signing key, and (once Part 4 is done) your relay credentials. You never
see or type any of them.

**Working already:** rings, live agent rows, and full-screen decisions
you answer from the wrist while on your home network.

## Part 3 — Push: the buzz, anywhere (≈1 minute)

```sh
python3 tools/vibepulse_setup.py push
```

Zero arguments — it uses the hosted push relay (which can see only your
device token; the notification text is a fixed generic string). Restart
the tokenserver, open AgentTap once, done: from now on your wrist buzzes
the moment an agent needs you, on any network, app closed. Tapping the
notification opens the verified decision card.

## Part 4 — Data anywhere: your own encrypted relays (≈4 minutes, once)

This makes rings, agent rows, and answering work when the watch is
nowhere near your Mac. It runs on a **free Cloudflare account** you own;
the decision/status mailbox is end-to-end encrypted (the cloud stores
ciphertext with a 15–120 s lifetime), and the quota mailbox carries the
same numbers-only documents your screen shows.

```sh
cd tools/interaction-relay && npm ci && npx wrangler login && cd ../..
python3 tools/vibepulse_setup.py anywhere
```

`wrangler login` opens the browser once (create the free account in that
flow if you don't have one). The `anywhere` command then deploys and
enables everything, and ends with the same two steps it prints:

1. restart the tokenserver,
2. **re-pair the watch** (one fresh 6-digit code — this hands the relay
   credentials over).

Running `anywhere` again later is safe; it rotates the relay credentials,
so it always ends with a re-pair.

## Done — daily life

Nothing to operate. The Mac must be awake (it is the data source and the
answering authority — laptop closed means the system honestly goes
stale). The watch:

- **Glance** — quota rings with reset countdowns; dashes are missing
  data, dimmed is stale, "Via relay" appears when you're away from home.
- **Agents** — every running agent, its project, its state; waiting
  agents jump to the top in accent color.
- **Needs You** — the decision card: APPROVE (only when the server's
  safe tier allows), DENY, LEAVE IT. Long-press the header to deny
  everything pending. Doing nothing always falls back to the terminal.
- **Complication** — tightest weekly quota on the watch face.
- **Demo mode** (Settings) — every screen on sample data, no setup, for
  trying the app before any of the above.

## When something is off

| Symptom | Cause | Fix |
|---|---|---|
| "Choose your computer" shows nothing | Different WiFi, or mDNS blocked | Join the Mac's network; or type `THE-MACS-IP:8737` in Settings → Server |
| Rings dashes at home, `-1001` under the label | `.local` lookup hang (physical watches) | Tap the discovered Mac row (stores a raw IP), or type the IP |
| Pair says "No code is active" | The 60 s window passed | Run `pair` again, type the fresh code |
| Buzz never arrives | Push not set up, or notification permission denied | Part 3; check watch Settings → Notifications → AgentTap |
| Away from home: rings/agents stale, no card | Part 4 not done, or watch not re-paired after it | Run `anywhere`, then re-pair |
| "Via relay" but stale agents | Mac asleep or offline | Wake the Mac — it is the only data source |
| APPROVE missing on a card | Detail off, or item outside the safe tier | Re-run the `watch` wizard and answer yes to detail; some items are terminal-only by design |
| Answer rejected "signature rejected" | Clock skew or stale pairing | Sync watch clock; re-pair |
| Quota rings never move | Tokenserver not restarted after setup steps | Restart it |

## For developers

Build from source instead of the App Store: `watch/setup.sh` (bakes your
key + server so answering works with nothing to type). Tests:
`xcodebuild test -project AgentTap.xcodeproj -scheme AgentTap
-destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)'`
— the relay crypto is pinned against the repository's cross-language
reference vectors, and the computer side is covered by
`test/test_pairing.py`, `test/test_push_notify.py`, and
`test/test_vibepulse_setup_watch.py`. Store submission kit:
[appstore/](appstore/README.md). Push relay source:
[../tools/push-relay/](../tools/push-relay/). Numbers relay shim:
[../tools/numbers-relay/](../tools/numbers-relay/).
