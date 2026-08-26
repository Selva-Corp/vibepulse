# AgentTap numbers relay (quota rings, anywhere)

The user-owned counterpart of `tools/relay`: identical Worker source,
fresh per-account deployment. Carries ONLY the numbers documents
(`/api/tokens`, `/api/max-tracker`, `/api/github`) — plaintext by design,
access-controlled by the secret in the URL path. Never agent activity,
never Needs You. Deployed automatically by
`python3 tools/vibepulse_setup.py anywhere`.
