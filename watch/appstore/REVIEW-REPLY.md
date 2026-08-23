# Reply to Guideline 2.1 Information Request (paste into Resolution Center)

Thank you for the review. Answers to each point:

**1. Screen recording**
Attached: a recording captured on a physical Apple Watch Ultra 2 running
watchOS 26.6 (mirrored to the paired iPhone via Apple Watch Mirroring and
screen-recorded there, as watchOS has no native screen recording). It begins
at app launch and shows the full typical flow, including the built-in demo
mode that exercises every feature with no external setup. The app has no
account registration, login, or account deletion (no accounts exist), no
in-app purchases or subscriptions, no user-generated content, and its only
permission prompt — notification authorization — is shown in the recording.

**2. Devices and operating systems tested**
- Apple Watch Ultra 2, watchOS 26.6 (physical device)
- Apple Watch Series 11 (46mm), watchOS 26.5 (simulator)
- Paired iPhone 16 Plus, iOS 27.0
The automated test suite (cryptographic signing vectors, parser and UI
logic) runs on the watchOS 26.5 simulator in CI.

**3. Function, audience, and value**
AgentTap is a utility for software developers who run AI coding agents
(Anthropic's Claude Code, OpenAI's Codex CLI) on their own computer. Those
tools work autonomously for long stretches, then stop and wait for the
developer to answer a question or approve an action — often unnoticed.
AgentTap shows, on the wrist: (a) the developer's remaining usage quota as
rings, (b) a list of currently running agents and their state, and (c) a
"Needs You" decision card when an agent is waiting, which the developer can
answer from the watch. Answers are cryptographically signed against exactly
what was displayed. The value: no more agents sitting idle for twenty
minutes because their one question scrolled by in a terminal.

**4. Setup and access instructions**
For review, no setup is required: launch the app and tap "Try demo mode"
(shown on first launch when no server is reachable), or open the gear icon
and enable "Demo mode". Demo mode fills every screen with realistic sample
data and raises a sample decision card within a few seconds — the complete
core flow, offline. No credentials exist anywhere in the app. (Real-world
use pairs the app with a free, open-source program the user runs on their
own computer, via a one-time 6-digit code displayed there.)

**5. External services, tools, platforms**
- Apple Push Notification service — the only third-party-visible service;
  planned for the next update (the submitted build does not yet register
  for push).
- The user's own self-hosted "VibePulse tokenserver" (open-source, MIT) on
  the user's local network — this is user infrastructure, not a vendor.
- No analytics, no data providers, no authentication services, no payment
  processors, no AI/ML services, no third-party SDKs. The app collects no
  data (see privacy policy).

**6. Regional differences**
None. The app functions identically in all regions and has no
region-gated features or content.

**7. Regulated industry / protected third-party material**
Not applicable. AgentTap is a developer utility; it contains no protected
third-party material and operates in no regulated industry. It is a
companion to an MIT-licensed open-source project, used with the user's own
locally installed developer tools.

---

# Shot list for the screen recording (~75 seconds, one take)

Prep once: iPhone → Settings → Accessibility → Apple Watch Mirroring → ON
(watch screen appears on iPhone). Add Screen Recording to iPhone Control
Center if missing. If AgentTap is running from earlier, force-quit it on
the watch first (press side button, swipe the app card away) so the
recording starts at launch.

1. Start iPhone screen recording (Control Center → record button).
2. On the watch: open AgentTap from the app grid. (Launch on camera.)
3. If the notification-permission dialog appears, tap Allow — on camera.
4. Glance page: wait ~3 s on the rings (or tap "Try demo mode" if shown).
5. Open the gear → scroll to "Demo mode" → toggle ON → tap back (<).
6. Glance now shows the demo rings; hold ~3 s.
7. Swipe up to the Agents page; hold ~3 s.
8. Wait a few seconds — the "Needs You" demo card takes over.
9. Scroll the card once, then tap APPROVE. Card resolves back to glance.
10. Gear → show the Pairing section briefly (Display-only/paired state),
    back out.
11. Stop the recording. The video is in iPhone Photos → AirDrop it to the
    Mac or attach directly from the phone in App Store Connect.
