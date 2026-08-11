import { DurableObject } from "cloudflare:workers";

export interface Env {
  SESSION_ROOM: DurableObjectNamespace<SessionRoom>;
  ENGINE_TOKEN?: string;
}

type Role = "engine" | "viewer";

type EventKind =
  | "session.open"
  | "draft.ready"
  | "gate.start"
  | "gate.done"
  | "artifact.sealed"
  | "note";

interface EngineEventMessage {
  type: "event";
  kind: EventKind;
  payload: unknown;
}

interface StoredEvent {
  seq: number;
  ts: string;
  kind: EventKind;
  payload: unknown;
}

interface PromptCommand {
  type: "cmd.prompt";
  nl: string;
  lane?: string;
}

interface CancelCommand {
  type: "cmd.cancel";
}

type CommandMessage = PromptCommand | CancelCommand;

type QueuedCommand = CommandMessage;

interface SessionState {
  launch?: unknown;
  draft?: unknown;
  gate?: "running" | {
    ok?: unknown;
    stage?: unknown;
    digests?: unknown;
  };
  artifact?: unknown;
  notes?: unknown[];
}

interface SocketAttachment {
  role: Role;
}

const MAX_EVENTS = 500;
const SNAPSHOT_TAIL = 50;
const MAX_NOTES = 20;

function json(data: unknown, init: ResponseInit = {}): Response {
  return new Response(JSON.stringify(data), {
    ...init,
    headers: {
      "content-type": "application/json; charset=utf-8",
      ...init.headers,
    },
  });
}

function badRequest(message: string): Response {
  return json({ ok: false, error: message }, { status: 400 });
}

function notFound(): Response {
  return json({ ok: false, error: "not found" }, { status: 404 });
}

function extractLaunchId(pathname: string, prefix: string): string | null {
  if (!pathname.startsWith(prefix)) {
    return null;
  }
  const rest = pathname.slice(prefix.length);
  if (rest.length === 0 || rest.includes("/")) {
    return null;
  }
  try {
    return decodeURIComponent(rest);
  } catch {
    return null;
  }
}

function isUpgrade(request: Request): boolean {
  return request.headers.get("Upgrade")?.toLowerCase() === "websocket";
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function parseEngineEvent(raw: unknown): EngineEventMessage | null {
  if (!isRecord(raw) || raw.type !== "event" || typeof raw.kind !== "string") {
    return null;
  }
  switch (raw.kind) {
    case "session.open":
    case "draft.ready":
    case "gate.start":
    case "gate.done":
    case "artifact.sealed":
    case "note":
      return { type: "event", kind: raw.kind, payload: raw.payload };
    default:
      return null;
  }
}

function parseViewerCommand(raw: unknown): CommandMessage | null {
  if (!isRecord(raw) || typeof raw.type !== "string") {
    return null;
  }
  if (raw.type === "cmd.prompt") {
    if (typeof raw.nl !== "string") {
      return null;
    }
    const command: PromptCommand = { type: "cmd.prompt", nl: raw.nl };
    if (raw.lane !== undefined) {
      if (typeof raw.lane !== "string") {
        return null;
      }
      command.lane = raw.lane;
    }
    return command;
  }
  if (raw.type === "cmd.cancel") {
    return { type: "cmd.cancel" };
  }
  return null;
}

function parseJsonMessage(message: string | ArrayBuffer): unknown | null {
  if (typeof message !== "string") {
    return null;
  }
  try {
    return JSON.parse(message) as unknown;
  } catch {
    return null;
  }
}

function sendJson(ws: WebSocket, data: unknown): void {
  try {
    ws.send(JSON.stringify(data));
  } catch {
    ws.close(1011, "send failed");
  }
}

function eventStatePatch(state: SessionState, event: StoredEvent): SessionState {
  const next: SessionState = { ...state };
  switch (event.kind) {
    case "session.open":
      next.launch = event.payload;
      break;
    case "draft.ready":
      next.draft = event.payload;
      break;
    case "gate.start":
      next.gate = "running";
      break;
    case "gate.done":
      if (isRecord(event.payload)) {
        next.gate = {
          ok: event.payload.ok,
          stage: event.payload.stage,
          digests: event.payload.digests,
        };
      } else {
        next.gate = {};
      }
      break;
    case "artifact.sealed":
      next.artifact = event.payload;
      break;
    case "note": {
      const notes = Array.isArray(next.notes) ? [...next.notes] : [];
      notes.push(event.payload);
      next.notes = notes.slice(-MAX_NOTES);
      break;
    }
  }
  return next;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "GET" && url.pathname === "/health") {
      return json({ ok: true });
    }

    const engineLaunchId = extractLaunchId(url.pathname, "/ws/engine/");
    if (request.method === "GET" && engineLaunchId !== null) {
      if (!isUpgrade(request)) {
        return badRequest("expected WebSocket upgrade");
      }
      // R0 local development accepts any token when ENGINE_TOKEN is unset.
      // Deployed environments should set ENGINE_TOKEN as a Wrangler secret/var.
      if (env.ENGINE_TOKEN !== undefined && url.searchParams.get("token") !== env.ENGINE_TOKEN) {
        return json({ ok: false, error: "unauthorized" }, { status: 401 });
      }
      return forwardToRoom(request, env, engineLaunchId, "engine");
    }

    const viewerLaunchId = extractLaunchId(url.pathname, "/ws/web/");
    if (request.method === "GET" && viewerLaunchId !== null) {
      if (!isUpgrade(request)) {
        return badRequest("expected WebSocket upgrade");
      }
      return forwardToRoom(request, env, viewerLaunchId, "viewer");
    }

    const stateMatch = url.pathname.match(/^\/api\/launches\/([^/]+)\/state$/u);
    if (request.method === "GET" && stateMatch !== null) {
      const launchId = decodeURIComponent(stateMatch[1] ?? "");
      if (launchId.length === 0) {
        return badRequest("missing launch id");
      }
      const id = env.SESSION_ROOM.idFromName(launchId);
      const room = env.SESSION_ROOM.get(id);
      return room.fetch(new Request(new URL("/state", request.url), { method: "GET" }));
    }

    return notFound();
  },
};

async function forwardToRoom(request: Request, env: Env, launchId: string, role: Role): Promise<Response> {
  if (launchId.length === 0) {
    return badRequest("missing launch id");
  }
  const id = env.SESSION_ROOM.idFromName(launchId);
  const room = env.SESSION_ROOM.get(id);
  const url = new URL(request.url);
  url.pathname = "/ws";
  url.search = `?role=${role}`;
  return room.fetch(new Request(url, request));
}

export class SessionRoom extends DurableObject<Env> {
  private loaded = false;
  private events: StoredEvent[] = [];
  private state: SessionState = {};
  private queue: QueuedCommand[] = [];
  private nextSeq = 1;

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
  }

  async fetch(request: Request): Promise<Response> {
    await this.ensureLoaded();
    const url = new URL(request.url);

    if (request.method === "GET" && url.pathname === "/state") {
      return json({ state: this.state, tail: this.events.slice(-SNAPSHOT_TAIL) });
    }

    if (request.method === "GET" && url.pathname === "/ws") {
      if (!isUpgrade(request)) {
        return badRequest("expected WebSocket upgrade");
      }
      const role = url.searchParams.get("role");
      if (role !== "engine" && role !== "viewer") {
        return badRequest("invalid role");
      }

      const pair = new WebSocketPair();
      const [client, server] = Object.values(pair) as [WebSocket, WebSocket];
      server.serializeAttachment({ role } satisfies SocketAttachment);

      if (role === "engine") {
        for (const socket of this.engineSockets()) {
          socket.close(1012, "engine replaced");
        }
      }

      this.ctx.acceptWebSocket(server);

      if (role === "viewer") {
        sendJson(server, { type: "snapshot", state: this.state, tail: this.events.slice(-SNAPSHOT_TAIL) });
      } else {
        await this.drainQueueToEngine(server);
      }

      return new Response(null, { status: 101, webSocket: client });
    }

    return notFound();
  }

  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    await this.ensureLoaded();
    const attachment = this.attachmentFor(ws);
    const parsed = parseJsonMessage(message);

    if (attachment.role === "engine") {
      const engineEvent = parseEngineEvent(parsed);
      if (engineEvent === null) {
        sendJson(ws, { type: "error", error: "invalid engine event" });
        return;
      }
      await this.appendEvent(engineEvent);
      return;
    }

    const command = parseViewerCommand(parsed);
    if (command === null) {
      sendJson(ws, { type: "error", error: "invalid viewer command" });
      return;
    }
    await this.enqueueCommand(command);
  }

  webSocketClose(ws: WebSocket, code: number, reason: string, wasClean: boolean): void {
    void ws;
    void code;
    void reason;
    void wasClean;
  }

  webSocketError(ws: WebSocket, error: unknown): void {
    void error;
    ws.close(1011, "websocket error");
  }

  private async ensureLoaded(): Promise<void> {
    if (this.loaded) {
      return;
    }
    const [events, state, queue, nextSeq] = await Promise.all([
      this.ctx.storage.get<StoredEvent[]>("events"),
      this.ctx.storage.get<SessionState>("state"),
      this.ctx.storage.get<QueuedCommand[]>("queue"),
      this.ctx.storage.get<number>("nextSeq"),
    ]);

    this.events = events ?? [];
    this.state = state ?? {};
    this.queue = queue ?? [];
    this.nextSeq = nextSeq ?? (this.events.at(-1)?.seq ?? 0) + 1;
    this.loaded = true;
  }

  private attachmentFor(ws: WebSocket): SocketAttachment {
    const attachment = ws.deserializeAttachment() as Partial<SocketAttachment> | undefined;
    if (attachment?.role === "engine" || attachment?.role === "viewer") {
      return { role: attachment.role };
    }
    return { role: "viewer" };
  }

  private engineSockets(): WebSocket[] {
    return this.ctx.getWebSockets().filter((socket) => this.attachmentFor(socket).role === "engine");
  }

  private viewerSockets(): WebSocket[] {
    return this.ctx.getWebSockets().filter((socket) => this.attachmentFor(socket).role === "viewer");
  }

  private async appendEvent(message: EngineEventMessage): Promise<void> {
    const event: StoredEvent = {
      seq: this.nextSeq,
      ts: new Date().toISOString(),
      kind: message.kind,
      payload: message.payload,
    };
    this.nextSeq += 1;
    this.events = [...this.events, event].slice(-MAX_EVENTS);
    this.state = eventStatePatch(this.state, event);

    await this.ctx.storage.put({
      events: this.events,
      state: this.state,
      nextSeq: this.nextSeq,
    });

    for (const viewer of this.viewerSockets()) {
      sendJson(viewer, { type: "event", event });
    }
  }

  private async enqueueCommand(command: CommandMessage): Promise<void> {
    this.queue = [...this.queue, command];

    await this.ctx.storage.put({
      queue: this.queue,
    });

    const [engine] = this.engineSockets();
    if (engine !== undefined) {
      await this.drainQueueToEngine(engine);
    }
  }

  private async drainQueueToEngine(engine: WebSocket): Promise<void> {
    if (this.queue.length === 0) {
      return;
    }

    const pending = this.queue;
    this.queue = [];
    await this.ctx.storage.put({ queue: this.queue });

    for (const command of pending) {
      sendJson(engine, command);
    }
  }
}
