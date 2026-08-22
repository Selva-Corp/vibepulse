# App Review notes (paste into App Store Connect "Notes")

AgentTap is a companion display/remote for a self-hosted, open-source
service (a "tokenserver") that developers run on their own computer to
monitor their AI coding agents. Like other self-hosted companions, the
app's live data requires that server on the reviewer's network — so a full
built-in DEMO MODE is provided:

1. Launch AgentTap.
2. On the first screen, tap "Try demo mode" (shown when no server is
   reachable) — or open the gear icon > scroll down > toggle "Demo mode".
3. The quota rings and the Agents page fill with sample data. Within a few
   seconds a "Needs You" decision card appears — the app's core interaction.
   APPROVE / LEAVE IT resolve it locally.

Demo mode exercises every screen with no network access. Outside demo mode
the app communicates only with the user's own server on their LAN
(NSAllowsLocalNetworking; Bonjour type _vibepulse._tcp), authenticated by a
key the user pairs themselves. The app collects no data (see privacy
policy) and contains no third-party code.
