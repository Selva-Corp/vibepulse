// AgentTap push relay: lets every user's self-hosted tokenserver trigger a
// Needs You push without holding the developer's APNs key.
//
// Privacy contract, enforced by construction: the request carries ONLY a
// device token; the notification body is a fixed generic string. Prompt
// text, project names, and anything else never reach this Worker, so it
// can never log or leak what it never saw. Tokens are never logged.
//
// Secrets (wrangler secret put): APNS_KEY (the .p8 PEM), APNS_KEY_ID,
// APNS_TEAM_ID. Vars: APNS_TOPIC.

const JWT_LIFETIME_MS = 40 * 60 * 1000;
const RATE_LIMIT_PER_MIN = 6; // per token, best-effort per isolate

let cachedJwt = null;
let cachedJwtAt = 0;
const recentNudges = new Map(); // token -> [timestamps]

function b64url(bytes) {
  let s = btoa(String.fromCharCode(...new Uint8Array(bytes)));
  return s.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function bearer(env) {
  const now = Date.now();
  if (cachedJwt && now - cachedJwtAt < JWT_LIFETIME_MS) return cachedJwt;
  const pem = env.APNS_KEY.replace(/-----[A-Z ]+-----|\s/g, "");
  const der = Uint8Array.from(atob(pem), c => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const enc = new TextEncoder();
  const header = b64url(enc.encode(JSON.stringify(
    { alg: "ES256", kid: env.APNS_KEY_ID })));
  const claims = b64url(enc.encode(JSON.stringify(
    { iss: env.APNS_TEAM_ID, iat: Math.floor(now / 1000) })));
  const sig = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" }, key,
    enc.encode(`${header}.${claims}`));
  cachedJwt = `${header}.${claims}.${b64url(sig)}`;
  cachedJwtAt = now;
  return cachedJwt;
}

function rateLimited(token) {
  const now = Date.now();
  const stamps = (recentNudges.get(token) || [])
    .filter(t => now - t < 60_000);
  if (stamps.length >= RATE_LIMIT_PER_MIN) return true;
  stamps.push(now);
  recentNudges.set(token, stamps);
  if (recentNudges.size > 10_000) recentNudges.clear();
  return false;
}

async function deliver(host, token, jwt, env) {
  // Fixed, generic payload — the relay never carries content.
  const payload = JSON.stringify({
    aps: {
      alert: { title: "Needs You", body: "An agent is waiting for you" },
      sound: "default",
      "interruption-level": "time-sensitive",
    },
  });
  return fetch(`${host}/3/device/${token}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-topic": env.APNS_TOPIC,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "apns-expiration": String(Math.floor(Date.now() / 1000) + 120),
    },
    body: payload,
  });
}

// Pairing rendezvous: for the 90 seconds a pairing code lives, the
// computer parks its LAN address here so the watch can find it with the
// same six digits — Bonjour browsing does not exist for third-party
// watchOS apps, so the code is the only discovery channel a watch has.
// The relay stores an opaque ciphertext under a HASH of the code (the
// code itself never arrives), single successful readout, hard TTL.
export class Rendezvous {
  constructor(state) {
    this.state = state;
  }
  async fetch(request) {
    const url = new URL(request.url);
    const hash = url.pathname.split("/").pop();
    if (!/^[0-9a-f]{64}$/.test(hash)) {
      return new Response(JSON.stringify({ ok: false }), { status: 400 });
    }
    if (request.method === "PUT") {
      let body;
      try { body = await request.json(); } catch {
        return new Response(JSON.stringify({ ok: false }), { status: 400 });
      }
      const payload = body && body.payload;
      if (typeof payload !== "string" || payload.length > 2048) {
        return new Response(JSON.stringify({ ok: false }), { status: 400 });
      }
      await this.state.storage.put(hash, payload);
      await this.state.storage.setAlarm(Date.now() + 90_000);
      return new Response(JSON.stringify({ ok: true }), { status: 201 });
    }
    if (request.method === "GET") {
      const payload = await this.state.storage.get(hash);
      if (payload === undefined) {
        return new Response(JSON.stringify({ ok: false }), { status: 404 });
      }
      await this.state.storage.delete(hash);
      return new Response(JSON.stringify({ ok: true, payload }),
        { status: 200 });
    }
    return new Response(JSON.stringify({ ok: false }), { status: 404 });
  }
  async alarm() {
    await this.state.storage.deleteAll();
  }
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname.startsWith("/rendezvous/")) {
      if (!env.RENDEZVOUS) {
        return new Response(JSON.stringify({ ok: false }), { status: 404 });
      }
      const id = env.RENDEZVOUS.idFromName("v1");
      return env.RENDEZVOUS.get(id).fetch(request);
    }
    if (request.method !== "POST" ||
        new URL(request.url).pathname !== "/nudge") {
      return new Response(JSON.stringify({ error: "not found" }),
        { status: 404 });
    }
    let body;
    try {
      body = await request.json();
    } catch {
      return new Response(JSON.stringify({ ok: false, reason: "bad json" }),
        { status: 400 });
    }
    const token = body && body.token;
    if (typeof token !== "string" || !/^[0-9a-f]{64}$/.test(token)) {
      return new Response(JSON.stringify({ ok: false, reason: "bad token" }),
        { status: 400 });
    }
    if (rateLimited(token)) {
      return new Response(JSON.stringify({ ok: false, reason: "slow down" }),
        { status: 429 });
    }
    const jwt = await bearer(env);
    let resp = await deliver("https://api.push.apple.com", token, jwt, env);
    if (resp.status === 400 || resp.status === 403) {
      const text = await resp.text();
      if (text.includes("BadDeviceToken") ||
          text.includes("BadEnvironmentKeyInToken")) {
        resp = await deliver(
          "https://api.development.push.apple.com", token, jwt, env);
      }
    }
    return new Response(JSON.stringify({ ok: resp.status === 200 }),
      { status: resp.status === 200 ? 200 : 502 });
  },
};
