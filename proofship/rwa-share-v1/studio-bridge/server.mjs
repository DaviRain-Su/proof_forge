#!/usr/bin/env node
/**
 * ProofShip Studio bridge (P0 · local-only).
 *
 * The browser Studio posts candidate ProgramV1 source here; this service runs
 * the REAL product gate on this machine (proof-forge-next check → build --target
 * evm → inspect exact closure) and returns the outcome as JSON.
 *
 * Discipline:
 *   - binds 127.0.0.1 only; never expose beyond localhost
 *   - no deploy endpoint (keys never flow through the bridge)
 *   - the gate is the product's sole authority; this bridge only invokes it
 *
 * Usage: node studio-bridge/server.mjs   (or: npm run bridge in dapp/)
 * Env:   PROOFSHIP_BRIDGE_PORT (default 5198)
 */
import { execFile, spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { mkdir, readdir, readFile, rm, writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url)); // proofship/rwa-share-v1/studio-bridge
const proj = resolve(here, ".."); // proofship/rwa-share-v1
const repo = resolve(proj, "../.."); // monorepo root
const cli = join(repo, ".lake/build/bin/proof-forge-next");
const inbox = join(proj, "studio-inbox");
const PORT = Number(process.env.PROOFSHIP_BRIDGE_PORT ?? 5198);
const MAX_SOURCE = 64 * 1024;
const RELAY_BASE = process.env.PROOFSHIP_RELAY;
const RELAY_TOKEN = process.env.PROOFSHIP_DEVICE_TOKEN ?? "";
const RELAY_LAUNCH_ID = process.env.PROOFSHIP_LAUNCH_ID ?? "default";
const RELAY_BUFFER_CAP = 200;
const RELAY_MAX_TEXT = 4096;


const MODULE_RE = /^[A-Za-z][A-Za-z0-9_]{0,63}$/;

let inFlightAgentProc = null;
let relayWs = null;
let relayReconnectTimer = null;
let relayBackoffMs = 1000;
const relayQueue = [];

function trimRelayText(value) {
  return String(value ?? "").slice(0, RELAY_MAX_TEXT);
}

function relaySocketUrl() {
  const base = String(RELAY_BASE ?? "").replace(/\/+$/, "");
  const launchId = encodeURIComponent(RELAY_LAUNCH_ID);
  const token = encodeURIComponent(RELAY_TOKEN);
  return `${base}/ws/engine/${launchId}?token=${token}`;
}

function relaySendRaw(obj) {
  const msg = JSON.stringify(obj);
  if (relayWs?.readyState === WebSocket.OPEN) {
    try {
      relayWs.send(msg);
      return;
    } catch {
      // Fall through and buffer below; reconnect handling will report state.
    }
  }
  relayQueue.push(msg);
  while (relayQueue.length > RELAY_BUFFER_CAP) relayQueue.shift();
}

function relayEvent(kind, payload) {
  if (!RELAY_BASE) return;
  relaySendRaw({ type: "event", kind, payload });
}

function relayFlush() {
  while (relayQueue.length > 0 && relayWs?.readyState === WebSocket.OPEN) {
    relayWs.send(relayQueue.shift());
  }
}

function relayScheduleReconnect() {
  if (!RELAY_BASE || relayReconnectTimer) return;
  const wait = relayBackoffMs;
  console.error(`relay: disconnected, retry in ${Math.ceil(wait / 1000)}s`);
  relayReconnectTimer = setTimeout(() => {
    relayReconnectTimer = null;
    relayConnect();
  }, wait);
  relayBackoffMs = Math.min(relayBackoffMs * 2, 30_000);
}

function relayConnect() {
  if (!RELAY_BASE) return;
  if (typeof WebSocket === "undefined") {
    console.error("relay: WebSocket unavailable; Node 25+ global WebSocket is required for PROOFSHIP_RELAY");
    process.exit(70);
  }
  let ws;
  try {
    ws = new WebSocket(relaySocketUrl());
  } catch (err) {
    relayScheduleReconnect();
    return;
  }
  relayWs = ws;
  ws.addEventListener("open", () => {
    relayBackoffMs = 1000;
    console.error("relay: connected");
    relayFlush();
  });
  ws.addEventListener("message", (ev) => {
    void handleRelayMessage(ev.data);
  });
  ws.addEventListener("close", () => {
    if (relayWs === ws) relayWs = null;
    relayScheduleReconnect();
  });
  ws.addEventListener("error", () => {
    try { ws.close(); } catch { /* already closing */ }
  });
}

async function handleRelayMessage(data) {
  let msg;
  try {
    msg = JSON.parse(String(data));
  } catch {
    return;
  }
  if (msg?.type === "cmd.prompt") {
    const nl = String(msg.nl ?? "").slice(0, 4000);
    if (!nl.trim()) {
      relayEvent("note", { level: "warn", text: "empty nl" });
      return;
    }
    const lane = msg.lane === undefined ? DEFAULT_LANE : String(msg.lane);
    const draft = await createAgentDraft({ nl, lane });
    emitDraftRelayResult(draft);
    if (!draft.ok) return;
    await runGate({ moduleName: draft.module, source: draft.source });
    return;
  }
  if (msg?.type === "cmd.cancel") {
    try { inFlightAgentProc?.kill("SIGTERM"); } catch { /* best effort */ }
  }
}

function emitDraftRelayResult(result) {
  if (result.ok) {
    relayEvent("draft.ready", {
      lane: result.lane,
      module: result.module,
      file: result.file,
      source: result.source,
      workdir: result.workdir,
    });
  } else {
    relayEvent("note", { level: "warn", text: trimRelayText(result.error ?? "draft failed") });
  }
}

function runCli(args) {
  return new Promise((res) => {
    execFile(
      cli,
      args,
      { cwd: proj, timeout: 240_000, maxBuffer: 8 * 1024 * 1024 },
      (error, stdout, stderr) => {
        const code =
          error == null ? 0 : typeof error.code === "number" ? error.code : 1;
        res({ code, stdout: String(stdout), stderr: String(stderr) });
      },
    );
  });
}

function json(res, status, body) {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "access-control-allow-origin": "*",
    "access-control-allow-methods": "GET,POST,OPTIONS",
    "access-control-allow-headers": "content-type",
    "cache-control": "no-store",
  });
  res.end(payload);
}

async function parseGateBody(req) {
  let raw = "";
  for await (const chunk of req) {
    raw += chunk;
    if (raw.length > MAX_SOURCE + 4096) {
      return { ok: false, status: 413, body: { ok: false, stage: "check", error: "source too large" } };
    }
  }
  let body;
  try {
    body = JSON.parse(raw);
  } catch {
    return { ok: false, status: 400, body: { ok: false, stage: "check", error: "bad json" } };
  }
  const moduleName = String(body?.module ?? "");
  const source = String(body?.source ?? "");
  if (!MODULE_RE.test(moduleName)) {
    return { ok: false, status: 400, body: { ok: false, stage: "check", error: "bad module name" } };
  }
  if (!source.startsWith("import ProofForgeV2") || source.length > MAX_SOURCE) {
    return { ok: false, status: 400, body: { ok: false, stage: "check", error: "source contract violated" } };
  }
  return { ok: true, moduleName, source };
}

async function runGate({ moduleName, source }) {
  relayEvent("gate.start", { module: moduleName });

  await mkdir(inbox, { recursive: true });
  const relSource = `studio-inbox/${moduleName}.lean`;
  await writeFile(join(proj, relSource), source, "utf8");

  const check = await runCli(["check", relSource, "--module", moduleName]);
  if (check.code !== 0) {
    const result = {
      ok: false,
      stage: "check",
      check: (check.stdout + check.stderr).trim(),
    };
    relayEvent("gate.done", {
      ok: result.ok,
      stage: result.stage,
      check: trimRelayText(result.check),
      build: "",
      inspect: "",
    });
    return result;
  }

  const outRel = `studio-inbox/out-${moduleName.toLowerCase()}`;
  await rm(join(proj, outRel), { recursive: true, force: true });
  const build = await runCli([
    "build",
    relSource,
    "--module",
    moduleName,
    "--target",
    "evm",
    "-o",
    outRel,
  ]);
  if (build.code !== 0) {
    const result = {
      ok: false,
      stage: "build",
      check: check.stdout.trim(),
      build: (build.stdout + build.stderr).trim(),
    };
    relayEvent("gate.done", {
      ok: result.ok,
      stage: result.stage,
      check: trimRelayText(result.check),
      build: trimRelayText(result.build),
      inspect: "",
    });
    return result;
  }

  const inspect = await runCli(["inspect", "--output-dir", outRel]);
  const result = {
    ok: inspect.code === 0,
    stage: inspect.code === 0 ? "done" : "inspect",
    check: check.stdout.trim(),
    build: build.stdout.trim(),
    inspect: (inspect.stdout + inspect.stderr).trim(),
  };
  relayEvent("gate.done", {
    ok: result.ok,
    stage: result.stage,
    check: trimRelayText(result.check),
    build: trimRelayText(result.build),
    inspect: trimRelayText(result.inspect),
  });
  if (result.ok && result.stage === "done") {
    relayEvent("artifact.sealed", { outputDir: outRel });
  }
  return result;
}

async function handleGate(req, res) {
  const parsed = await parseGateBody(req);
  if (!parsed.ok) {
    json(res, parsed.status, parsed.body);
    return;
  }
  json(res, 200, await runGate(parsed));
}


/* ---------------------------------------------------------------------------
 * Local code-agent lanes (driver registry).
 *
 *   kind "acp"  — Agent Client Protocol over stdio JSON-RPC 2.0
 *                 (initialize → session/new → session/prompt; permissions
 *                 auto-allowed). Lanes: omp, claude (adapter), gemini.
 *   kind "exec" — headless one-shot in a scratch workdir.
 *                 Lanes: codex, grok, pi, omp.
 *
 * Every lane: cwd = fresh studio-inbox/agent/<id>/, prompt = ProofShip system
 * prompt + user NL; the one *.lean file produced is the draft we then gate.
 * Default lane: PROOFSHIP_AGENT_CMD ?? "codex". "off" disables the lane.
 * ------------------------------------------------------------------------- */

const AGENT_TIMEOUT_MS = Number(process.env.PROOFSHIP_AGENT_TIMEOUT_MS ?? 420_000);

function fullPrompt(systemPrompt, nl) {
  return `${systemPrompt}\n\n---\n\n用户需求：\n${nl}\n\n请把最终合约写入当前目录下的 \`${pickModuleName(nl)}.lean\`（只写这一个 .lean 文件，不要创建其它文件）。`;
}

const DRIVERS = {
  /* ---- exec lanes (headless one-shot) ---- */
  codex: {
    kind: "exec",
    cmd: "codex",
    args: (wd, prompt) => ["exec", "--skip-git-repo-check", "--sandbox", "workspace-write", "--cd", wd, prompt],
  },
  grok: {
    kind: "exec",
    cmd: "grok",
    args: (wd, prompt) => ["-p", prompt, "--always-approve", "--cwd", wd],
  },
  pi: {
    kind: "exec",
    cmd: "pi",
    args: (_wd, prompt) => ["-p", prompt],
  },
  omp: {
    kind: "exec",
    cmd: "omp",
    args: (_wd, prompt) => ["-p", prompt],
  },
  kimi: {
    kind: "exec",
    cmd: "kimi",
    args: (_wd, prompt) => ["-p", prompt, "--yolo"],
  },
  "cursor-agent": {
    kind: "exec",
    cmd: "cursor-agent",
    args: (_wd, prompt) => ["-p", "--force", prompt],
  },
  amp: {
    kind: "exec",
    cmd: "amp",
    args: (_wd, prompt) => ["-x", prompt],
  },
  copilot: {
    kind: "exec",
    cmd: "copilot",
    args: (_wd, prompt) => ["-p", prompt, "--allow-all-tools"],
  },
  /* ---- ACP lanes (Agent Client Protocol over stdio) ---- */
  "omp-acp": {
    kind: "acp",
    cmd: "omp",
    args: () => ["acp"],
  },
  "kimi-acp": {
    kind: "acp",
    cmd: "kimi",
    args: () => ["acp"],
  },
  "qwen-acp": {
    kind: "acp",
    cmd: "qwen",
    args: () => ["--acp"],
  },
  "opencode-acp": {
    kind: "acp",
    cmd: "opencode",
    args: () => ["acp"],
  },
  "copilot-acp": {
    kind: "acp",
    cmd: "copilot",
    args: () => ["--acp", "--stdio"],
  },
  "claude-acp": {
    kind: "acp",
    cmd: "claude-code-acp",
    args: () => [],
  },
  "gemini-acp": {
    kind: "acp",
    cmd: "gemini",
    args: () => ["--acp"],
  },
};

const DEFAULT_LANE = process.env.PROOFSHIP_AGENT_CMD ?? "codex";

function which(cmd) {
  return new Promise((res) => {
    execFile("which", [cmd], (error, stdout) => {
      res(error ? null : String(stdout).trim());
    });
  });
}

async function laneList() {
  const out = [];
  for (const [name, d] of Object.entries(DRIVERS)) {
    const path = await which(d.cmd);
    out.push({ name, kind: d.kind, cmd: d.cmd, available: path !== null });
  }
  return out;
}

function readJsonBody(req) {
  return new Promise((res, rej) => {
    let raw = "";
    req.on("data", (c) => {
      raw += c;
      if (raw.length > MAX_SOURCE + 4096) rej(new Error("too large"));
    });
    req.on("end", () => res(raw));
    req.on("error", rej);
  });
}

/** ACP lane: initialize → session/new → session/prompt, auto-allow permissions. */
function acpDraft(promptText, workdir, driver) {
  return new Promise((resolvePromise) => {
    const proc = spawn(driver.cmd, driver.args(workdir, promptText), {
      cwd: workdir,
      stdio: ["pipe", "pipe", "pipe"],
      env: { ...process.env },
    });
    inFlightAgentProc = proc;
    let buf = "";
    let stderrTail = "";
    let nextId = 1;
    const pending = new Map();
    const chunks = [];
    let done = false;

    const finish = (value) => {
      if (done) return;
      done = true;
      clearTimeout(timer);
      try { proc.kill("SIGTERM"); } catch { /* already gone */ }
      if (inFlightAgentProc === proc) inFlightAgentProc = null;
      resolvePromise(value);
    };
    const timer = setTimeout(
      () => finish({ ok: false, error: `agent timeout (${AGENT_TIMEOUT_MS / 1000}s)`, stderrTail }),
      AGENT_TIMEOUT_MS,
    );

    proc.stderr.on("data", (d) => {
      stderrTail = (stderrTail + String(d)).slice(-2000);
    });

    const send = (obj) => proc.stdin.write(JSON.stringify(obj) + "\n");
    const request = (method, params) =>
      new Promise((res2) => {
        const id = nextId++;
        pending.set(id, res2);
        send({ jsonrpc: "2.0", id, method, params });
      });

    proc.stdout.on("data", (d) => {
      buf += String(d);
      let idx;
      while ((idx = buf.indexOf("\n")) >= 0) {
        const line = buf.slice(0, idx).trim();
        buf = buf.slice(idx + 1);
        if (!line) continue;
        let msg;
        try { msg = JSON.parse(line); } catch { continue; }
        if (msg.id !== undefined && pending.has(msg.id) && (msg.result !== undefined || msg.error !== undefined)) {
          pending.get(msg.id)(msg);
          pending.delete(msg.id);
          continue;
        }
        if (msg.method === "session/update") {
          const upd = msg.params?.update;
          if (upd?.sessionUpdate === "agent_message_chunk" && upd.content?.text) {
            chunks.push(upd.content.text);
          }
          continue;
        }
        if (msg.id !== undefined && msg.method) {
          if (msg.method === "session/request_permission") {
            const opts = msg.params?.options ?? [];
            const allow = opts.find((o) => /allow/i.test(String(o.id ?? o.kind ?? o))) ?? opts[0];
            send({
              jsonrpc: "2.0",
              id: msg.id,
              result: { outcome: { outcome: "selected", optionId: allow?.id ?? "allow_once" } },
            });
          } else {
            send({
              jsonrpc: "2.0",
              id: msg.id,
              error: { code: -32601, message: `unsupported: ${msg.method}` },
            });
          }
        }
      }
    });

    proc.on("error", (err) => finish({ ok: false, error: `spawn failed: ${err.message}` }));
    proc.on("exit", (code) => {
      if (!done) finish({ ok: false, error: `agent exited (${code})`, stderrTail, chunks });
    });

    (async () => {
      const init = await request("initialize", {
        protocolVersion: 1,
        clientCapabilities: { fs: { readTextFile: false, writeTextFile: false } },
      });
      if (init.error) return finish({ ok: false, error: `initialize: ${init.error.message}` });
      const sess = await request("session/new", { cwd: workdir, mcpServers: [] });
      if (sess.error) return finish({ ok: false, error: `session/new: ${sess.error.message}` });
      const sessionId = sess.result?.sessionId;
      if (!sessionId) return finish({ ok: false, error: "no sessionId" });
      const pr = await request("session/prompt", {
        sessionId,
        prompt: [{ type: "text", text: promptText }],
      });
      if (pr.error) return finish({ ok: false, error: `prompt: ${pr.error.message}` });
      finish({ ok: true, chunks });
    })();
  });
}

/** exec lane: headless one-shot in the scratch workdir. */
function execDraft(promptText, workdir, driver) {
  return new Promise((resolvePromise) => {
    const proc = spawn(driver.cmd, driver.args(workdir, promptText), {
      cwd: workdir,
      stdio: ["ignore", "pipe", "pipe"],
    });
    inFlightAgentProc = proc;
    let out = "";
    let err = "";
    let done = false;
    const finish = (v) => {
      if (done) return;
      done = true;
      clearTimeout(timer);
      try { proc.kill("SIGTERM"); } catch { /* gone */ }
      if (inFlightAgentProc === proc) inFlightAgentProc = null;
      resolvePromise(v);
    };
    const timer = setTimeout(
      () => finish({ ok: false, error: `${driver.cmd} timeout (${AGENT_TIMEOUT_MS / 1000}s)` }),
      AGENT_TIMEOUT_MS,
    );
    proc.stdout.on("data", (d) => { out = (out + String(d)).slice(-8000); });
    proc.stderr.on("data", (d) => { err = (err + String(d)).slice(-4000); });
    proc.on("error", (e) => finish({ ok: false, error: `spawn ${driver.cmd} failed: ${e.message}` }));
    proc.on("exit", (code) =>
      finish(code === 0
        ? { ok: true, chunks: [out] }
        : { ok: false, error: `${driver.cmd} exited ${code}`, stderrTail: err }),
    );
  });
}

function pickModuleName(nl) {
  return nl.includes("发票") ? "InvoiceShare" : "RwaShareRegistry";
}

async function createAgentDraft({ nl, lane }) {
  const nlText = String(nl ?? "").slice(0, 4000);
  if (!nlText.trim()) {
    return { ok: false, error: "empty nl" };
  }
  const laneName = String(lane ?? DEFAULT_LANE);
  if (laneName === "off") {
    return { ok: false, lane: laneName, error: "agent lane disabled" };
  }
  const driver = DRIVERS[laneName];
  if (!driver) {
    return { ok: false, lane: laneName, error: `unknown lane '${laneName}'`, lanes: Object.keys(DRIVERS) };
  }

  const id = `${Date.now().toString(36)}`;
  const workdir = join(inbox, "agent", id);
  await mkdir(workdir, { recursive: true });
  const systemPromptPath = join(proj, "ai/system-prompt.md");
  const systemPrompt = existsSync(systemPromptPath)
    ? await readFile(systemPromptPath, "utf8")
    : "Write one ProofForge ProgramV1 file.";

  const promptText = fullPrompt(systemPrompt, nlText);
  const out = driver.kind === "acp"
    ? await acpDraft(promptText, workdir, driver)
    : await execDraft(promptText, workdir, driver);
  if (!out.ok) {
    return { ok: false, lane: laneName, error: out.error, stderrTail: out.stderrTail ?? "" };
  }

  const files = (await readdir(workdir)).filter((f) => f.endsWith(".lean"));
  if (files.length === 0) {
    return {
      ok: false,
      lane: laneName,
      error: "agent produced no .lean file",
      agentText: out.chunks.join("").slice(-1500),
    };
  }
  const file = files[0];
  const source = await readFile(join(workdir, file), "utf8");
  return {
    ok: true,
    lane: laneName,
    file,
    module: file.replace(/\.lean$/, ""),
    source,
    workdir: `studio-inbox/agent/${id}`,
  };
}

async function handleAgentDraft(req, res) {
  let raw;
  try {
    raw = await readJsonBody(req);
  } catch {
    const result = { ok: false, error: "body too large" };
    emitDraftRelayResult(result);
    json(res, 413, result);
    return;
  }
  let body;
  try {
    body = JSON.parse(raw);
  } catch {
    const result = { ok: false, error: "bad json" };
    emitDraftRelayResult(result);
    json(res, 400, result);
    return;
  }
  const result = await createAgentDraft({ nl: body?.nl, lane: body?.lane });
  emitDraftRelayResult(result);
  const status = !result.ok && (result.error === "empty nl" || String(result.error).startsWith("unknown lane")) ? 400 : 200;
  json(res, status, result);
}


const server = createServer(async (req, res) => {
  if (req.method === "OPTIONS") {
    json(res, 204, {});
    return;
  }
  const url = new URL(req.url ?? "/", "http://127.0.0.1");
  if (req.method === "GET" && url.pathname === "/api/health") {
    json(res, 200, { ok: existsSync(cli), agent: DEFAULT_LANE });
    return;
  }
  if (req.method === "GET" && url.pathname === "/api/agent/lanes") {
    json(res, 200, { ok: true, default: DEFAULT_LANE, lanes: await laneList() });
    return;
  }
  if (req.method === "POST" && url.pathname === "/api/gate") {
    void handleGate(req, res);
    return;
  }
  if (req.method === "POST" && url.pathname === "/api/agent/draft") {
    void handleAgentDraft(req, res);
    return;
  }
  json(res, 404, { ok: false, error: "not found" });
});

if (!existsSync(cli)) {
  console.error("studio-bridge: product CLI missing — run `just build` first");
  process.exit(70);
}

server.on("error", (err) => {
  if (err && err.code === "EADDRINUSE") {
    console.error(
      `studio-bridge: 127.0.0.1:${PORT} already in use — a bridge is likely already running.\n` +
        "  Use it as-is, or set PROOFSHIP_BRIDGE_PORT to run another.",
    );
    process.exit(48);
  }
  throw err;
});

relayConnect();

server.listen(PORT, "127.0.0.1", () => {
  console.log(`studio-bridge: listening on http://127.0.0.1:${PORT}/api (local-only)`);
});
