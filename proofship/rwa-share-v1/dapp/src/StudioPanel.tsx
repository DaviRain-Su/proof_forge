import { useCallback, useEffect, useRef, useState, type FC } from "react";
import { listLanes, runAgentDraft, runGate, type LaneInfo } from "./studio/bridge";
import type { ChatMsg, Launch } from "./studio/store";
import { extractFields, renderProgram } from "./studio/template";

const SUGGESTIONS = [
  "登记一笔代币化发票份额：总量 1,000,000 份，单笔转让最多 50,000，每 1000 个块一个窗口，窗口内累计最多转 100,000，只有白名单地址能受让。",
  "Issue 2,000,000 shares for a solar bond; max 25,000 per transfer; rolling 600-block window capped at 150,000; allowlisted recipients only.",
];

const now = () => new Date().toISOString();

export const StudioPanel: FC<{
  launch: Launch;
  onChange: (next: Launch) => void;
  onOpenRegistry: () => void;
}> = ({ launch, onChange, onOpenRegistry }) => {
  const [input, setInput] = useState("");
  const [busy, setBusy] = useState(false);
  const [lanes, setLanes] = useState<LaneInfo[]>([]);
  const [lane, setLane] = useState<string>(
    () => localStorage.getItem("proofship.lane") ?? "codex",
  );
  const threadRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    void (async () => {
      const res = await listLanes();
      if (res) {
        setLanes(res.lanes.filter((l) => l.available));
        if (!res.lanes.some((l) => l.name === lane && l.available)) {
          setLane(res.default);
        }
      }
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const scrollDown = useCallback(() => {
    requestAnimationFrame(() => {
      threadRef.current?.scrollTo({ top: threadRef.current.scrollHeight });
    });
  }, []);

  const push = useCallback(
    (msg: ChatMsg, base?: Launch) => {
      const target = base ?? launch;
      onChange({ ...target, msgs: [...target.msgs, msg] });
      scrollDown();
    },
    [launch, onChange, scrollDown],
  );

  const send = useCallback(
    async (text: string) => {
      const nl = text.trim();
      if (!nl || busy) return;
      setBusy(true);
      setInput("");

      const fields = extractFields(nl);
      const { program, source } = renderProgram(fields);
      let next: Launch = {
        ...launch,
        title: fields.assetName,
        fields,
        program,
        source,
        msgs: [...launch.msgs, { role: "user", text: nl, at: now() }],
      };
      onChange(next);

      // Preferred lane: a real local code agent via the bridge (ACP / exec).
      // Fallback: the deterministic template renderer (offline-safe).
      let finalProgram = program;
      let finalSource = source;
      let draftNote: string | null = null;
      if (lanes.length > 0) {
        const draft = await runAgentDraft(nl, lane);
        if (draft?.ok) {
          finalProgram = draft.module;
          finalSource = draft.source;
          draftNote = `drafted by ${draft.lane} (local agent)`;
        } else if (draft && !draft.ok) {
          draftNote = `${lane} unavailable (${draft.error}) — used the controlled template`;
        }
      }
      next = { ...next, program: finalProgram, source: finalSource };

      const draft: ChatMsg = {
        role: "agent",
        kind: "draft",
        fields,
        program: finalProgram,
        source: finalSource,
        note: draftNote,
        at: now(),
      };
      next = { ...next, msgs: [...next.msgs, draft] };
      onChange(next);
      scrollDown();

      const running: ChatMsg = { role: "agent", kind: "gate", state: "running", at: now() };
      next = { ...next, msgs: [...next.msgs, running] };
      onChange(next);
      scrollDown();

      const result = await runGate(finalProgram, finalSource);
      const gate: ChatMsg = result
        ? {
            role: "agent",
            kind: "gate",
            state: result.ok ? "pass" : "fail",
            result,
            at: now(),
          }
        : { role: "agent", kind: "gate", state: "offline", at: now() };
      next = {
        ...next,
        msgs: [...next.msgs.slice(0, -1), gate],
      };
      onChange(next);

      if (result?.ok) {
        push(
          {
            role: "agent",
            kind: "note",
            text: `Gate passed — artifacts sealed under the exact disk closure. Ship from the inspector (wallet-signed) or the CLI: scripts/deploy-testnet.sh ${fields.totalSupply} ${fields.maxPerTx} ${fields.windowCap}`,
            at: now(),
          },
          next,
        );
      } else if (result && !result.ok) {
        push(
          {
            role: "agent",
            kind: "note",
            text: "The gate rejected this draft and produced zero artifacts. Read the PF-* diagnostic in the card, adjust the rules, and send again — the repair loop is the product.",
            at: now(),
          },
          next,
        );
      } else {
        push(
          {
            role: "agent",
            kind: "note",
            text: "Local bridge offline — this build shows the last sealed gate report in the inspector. Start the bridge for a live gate: npm run bridge",
            at: now(),
          },
          next,
        );
      }
      setBusy(false);
      scrollDown();
    },
    [busy, launch, onChange, push, scrollDown],
  );

  useEffect(() => {
    scrollDown();
  }, [launch.id, scrollDown]);

  return (
    <div className="chat">
      <div className="thread" ref={threadRef}>
        {launch.msgs.length === 0 && (
          <div className="empty-thread">
            <p className="eyebrow">New launch</p>
            <h2>Describe the share rules.</h2>
            <p className="muted">
              Supply, per-transfer cap, rolling window, allowlist. The agent drafts the program,
              the gate checks it, and only then it can ship.
            </p>
            <div className="suggestions">
              {SUGGESTIONS.map((s) => (
                <button key={s.slice(0, 12)} type="button" className="ghost suggestion" onClick={() => void send(s)}>
                  {s}
                </button>
              ))}
            </div>
          </div>
        )}
        {launch.msgs.map((m, i) => (
          <MessageView key={`${m.at}-${i}`} msg={m} onOpenRegistry={onOpenRegistry} />
        ))}
        {busy && <div className="msg agent"><div className="card"><span className="muted">working…</span></div></div>}
      </div>

      <form
        className="composer"
        onSubmit={(e) => {
          e.preventDefault();
          void send(input);
        }}
      >
        <textarea
          value={input}
          onChange={(e) => setInput(e.target.value)}
          rows={2}
          placeholder="总量、单笔限额、窗口、白名单规则…"
          aria-label="describe share rules"
          onKeyDown={(e) => {
            if (e.key === "Enter" && !e.shiftKey) {
              e.preventDefault();
              void send(input);
            }
          }}
        />
        {lanes.length > 0 && (
          <select
            className="lane-pick"
            value={lane}
            onChange={(e) => {
              setLane(e.target.value);
              localStorage.setItem("proofship.lane", e.target.value);
            }}
            title="code agent lane"
          >
            {lanes.map((l) => (
              <option key={l.name} value={l.name}>
                {l.name} · {l.kind}
              </option>
            ))}
          </select>
        )}
        <button type="submit" disabled={busy || !input.trim()}>
          Send
        </button>
      </form>
    </div>
  );
};

const MessageView: FC<{ msg: ChatMsg; onOpenRegistry: () => void }> = ({ msg, onOpenRegistry }) => {
  if (msg.role === "user") {
    return (
      <div className="msg user">
        <div className="bubble">{msg.text}</div>
      </div>
    );
  }
  if (msg.kind === "draft") {
    const { fields, program, source, note } = msg;
    return (
      <div className="msg agent">
        <div className="card">
          <p className="card-title">Draft ready — {program}</p>
          {note && <p className="lane-note muted">{note}</p>}
          <div className="kv">
            <dt>totalSupply</dt>
            <dd>{fields.totalSupply}</dd>
            <dt>maxPerTx</dt>
            <dd>{fields.maxPerTx}</dd>
            <dt>window</dt>
            <dd>
              {fields.windowCap} per {fields.windowBlocks} blocks
            </dd>
            <dt>transfer rule</dt>
            <dd>allowlisted recipients only</dd>
          </div>
          <details>
            <summary>ProgramV1 source</summary>
            <pre className="src">{source}</pre>
          </details>
        </div>
      </div>
    );
  }
  if (msg.kind === "gate") {
    return (
      <div className="msg agent">
        <div className={`card gate-card ${msg.state}`}>
          {msg.state === "running" && <p className="card-title">Running the gate…</p>}
          {msg.state === "pass" && (
            <>
              <p className="card-title pass">⊢ GATE PASS</p>
              <GateDigest text={msg.result?.check ?? ""} label="sourceDigest" />
              <GateDigest text={msg.result?.check ?? ""} label="semanticDigest" />
              <GateDigest text={msg.result?.inspect ?? ""} label="outputSetDigest" />
            </>
          )}
          {msg.state === "fail" && (
            <>
              <p className="card-title fail">✗ GATE REJECTED — zero artifacts</p>
              <pre className="src">
                {(msg.result?.build || msg.result?.check || msg.result?.error || "").slice(0, 600)}
              </pre>
            </>
          )}
          {msg.state === "offline" && (
            <p className="card-title muted">Gate offline (static build) — showing sealed report in the inspector</p>
          )}
        </div>
      </div>
    );
  }
  return (
    <div className="msg agent">
      <div className="card note">
        <p className="muted" style={{ margin: 0 }}>
          {msg.text}
        </p>
        {msg.text.startsWith("Gate passed") && (
          <div className="actions">
            <button type="button" onClick={onOpenRegistry}>
              Open the registry
            </button>
          </div>
        )}
      </div>
    </div>
  );
};

const GateDigest: FC<{ text: string; label: string }> = ({ text, label }) => {
  const line = text
    .split("\n")
    .map((l) => l.trim())
    .find((l) => l.startsWith(`${label}=`));
  if (!line) return null;
  return (
    <div className="kv">
      <dt>{label}</dt>
      <dd>{line.slice(label.length + 1)}</dd>
    </div>
  );
};
