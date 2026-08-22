# AgentTap push relay

A single Cloudflare Worker, hosted once by the app's developer, that lets
every user's self-hosted tokenserver ring the Needs You doorbell on their
own watch — without anyone but the developer holding the APNs key.

**What it can and cannot see, by construction:** requests carry only a
64-hex APNs device token. The notification body is a fixed generic string
compiled into the Worker. Prompt text, commands, and project names never
leave the user's LAN. Tokens are rate-limited (6/min) and never logged.

## Deploy (developer, once)

```sh
cd tools/push-relay
npx wrangler login
npx wrangler deploy
npx wrangler secret put APNS_KEY      < ~/.vibepulse-apns-XXXXXXXXXX.p8
echo "XXXXXXXXXX" | npx wrangler secret put APNS_KEY_ID
echo "TEAMID9999" | npx wrangler secret put APNS_TEAM_ID
```

## Use (every user)

```sh
python3 tools/vibepulse_setup.py push --relay-url https://agenttap-push-relay.<subdomain>.workers.dev
```

Then restart the tokenserver and open AgentTap once on the watch.
