# ProofShip Relay (R0 spike)

Cloudflare Worker + one Durable Object that relays a local ProofShip bridge/engine to any browser. The engine is the single writer and gate authority; the web app observes state and may enqueue commands for the local engine to execute.

## Event contract

Engine WebSocket: `GET /ws/engine/:launchId?token=...`

Engine messages are JSON:

```json
{"type":"event","kind":"session.open","payload":{"launchId":"...","fields":{},"agentLane":"..."}}
{"type":"event","kind":"draft.ready","payload":{"program":"...","source":"...","lane":"..."}}
{"type":"event","kind":"gate.start","payload":{}}
{"type":"event","kind":"gate.done","payload":{"ok":true,"stage":"...","digests":{}}}
{"type":"event","kind":"artifact.sealed","payload":{"outputSetDigest":"...","files":[]}}
{"type":"event","kind":"note","payload":{"text":"..."}}
```

The relay assigns each event `{seq, ts}` and broadcasts:

```json
{"type":"event","event":{"seq":1,"ts":"2026-08-11T00:00:00.000Z","kind":"draft.ready","payload":{}}}
```

Viewer WebSocket: `GET /ws/web/:launchId`

On connect, viewers receive:

```json
{"type":"snapshot","state":{},"tail":[]}
```

Viewer commands are JSON and are persisted until delivered to a connected engine:

```json
{"type":"cmd.prompt","nl":"revise the draft","lane":"optional"}
{"type":"cmd.cancel"}
```

HTTP snapshot: `GET /api/launches/:id/state` returns the same materialized state plus the last 50 events.

## Development

```sh
cd proofship/relay
npm install
npm run typecheck
npm run dev
```

Set `ENGINE_TOKEN` for engine authentication in deployed/dev environments. If `ENGINE_TOKEN` is absent, the spike accepts any engine token to keep local development simple.

## Deploy

```sh
cd proofship/relay
wrangler secret put ENGINE_TOKEN
npm run deploy
```

`wrangler.toml` intentionally has no `account_id`; deployment uses ambient Wrangler authentication.

## Security note

The relay never holds chain private keys or LLM API credentials. The local engine remains the only writer and the only gate executor. `ENGINE_TOKEN` is a shared secret for this R0 spike; per-device tokens, accounts, sharing policy, D1, and OAuth/SIWE belong to R1+.
