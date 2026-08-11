import { useEffect, useRef, useState, type FC } from "react";

const RELAY = "wss://proofship-relay.davirain-yin.workers.dev";

type RelayEvent = { seq: number; ts: number; kind: string; payload: Record<string, unknown> };

type LiveState =
  | { phase: "connecting" }
  | { phase: "live" }
  | { phase: "closed"; reason: string };

/** Read-only live view of a launch room on the relay (R0). */
export const LivePanel: FC<{ launchId: string; onExit: () => void }> = ({ launchId, onExit }) => {
  const [state, setState] = useState<LiveState>({ phase: "connecting" });
  const [events, setEvents] = useState<RelayEvent[]>([]);
  const threadRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const ws = new WebSocket(`${RELAY}/ws/web/${encodeURIComponent(launchId)}`);
    ws.onopen = () => setState({ phase: "live" });
    ws.onclose = () => setState({ phase: "closed", reason: "connection closed" });
    ws.onerror = () => setState({ phase: "closed", reason: "connection error" });
    ws.onmessage = (e) => {
      try {
        const msg = JSON.parse(String(e.data));
        if (msg.type === "snapshot") {
          const tail = (msg.tail ?? []) as RelayEvent[];
          setEvents(tail);
        } else if (msg.type === "event" && msg.event) {
          setEvents((prev) => [...prev.slice(-199), msg.event as RelayEvent]);
        }
      } catch {
        /* ignore malformed frames */
      }
    };
    return () => ws.close();
  }, [launchId]);

  useEffect(() => {
    threadRef.current?.scrollTo({ top: threadRef.current.scrollHeight });
  }, [events.length]);

  return (
    <div className="chat">
      <div className="thread" ref={threadRef}>
        <div className="empty-thread" style={{ margin: "0 0 auto", maxWidth: "none" }}>
          <p className="eyebrow">
            live · {launchId} ·{" "}
            {state.phase === "live" ? "connected" : state.phase === "connecting" ? "connecting…" : state.reason}
          </p>
        </div>
        {events.length === 0 && state.phase === "live" && (
          <p className="muted">Waiting for the engine to publish events…</p>
        )}
        {events.map((ev) => (
          <EventCard key={ev.seq} ev={ev} />
        ))}
      </div>
      <div className="composer">
        <button type="button" className="ghost" onClick={onExit}>
          ← Back to Studio
        </button>
        <span className="muted" style={{ alignSelf: "center" }}>
          read-only mirror · the gate runs on the owner&apos;s machine
        </span>
      </div>
    </div>
  );
};

const EventCard: FC<{ ev: RelayEvent }> = ({ ev }) => {
  const p = ev.payload as Record<string, unknown>;
  if (ev.kind === "draft.ready") {
    return (
      <div className="msg agent">
        <div className="card">
          <p className="card-title">Draft ready — {String(p.module ?? "")}</p>
          <p className="lane-note muted">lane {String(p.lane ?? "?")}</p>
          {typeof p.source === "string" && (
            <details>
              <summary>ProgramV1 source</summary>
              <pre className="src">{p.source}</pre>
            </details>
          )}
        </div>
      </div>
    );
  }
  if (ev.kind === "gate.start") {
    return (
      <div className="msg agent">
        <div className="card">
          <p className="card-title">Running the gate — {String(p.module ?? "")}…</p>
        </div>
      </div>
    );
  }
  if (ev.kind === "gate.done") {
    const ok = p.ok === true;
    return (
      <div className="msg agent">
        <div className={`card gate-card ${ok ? "pass" : "fail"}`}>
          <p className={`card-title ${ok ? "pass" : "fail"}`}>
            {ok ? "⊢ GATE PASS" : "✗ GATE REJECTED"} · stage {String(p.stage ?? "")}
          </p>
          {typeof p.check === "string" && (
            <pre className="src">{p.check.slice(0, 800)}</pre>
          )}
        </div>
      </div>
    );
  }
  if (ev.kind === "artifact.sealed") {
    return (
      <div className="msg agent">
        <div className="card">
          <p className="card-title pass">artifact sealed — {String(p.outputDir ?? "")}</p>
        </div>
      </div>
    );
  }
  return (
    <div className="msg agent">
      <div className="card note">
        <p className="muted" style={{ margin: 0 }}>
          {ev.kind}: {typeof p.text === "string" ? p.text : JSON.stringify(p).slice(0, 200)}
        </p>
      </div>
    </div>
  );
};
