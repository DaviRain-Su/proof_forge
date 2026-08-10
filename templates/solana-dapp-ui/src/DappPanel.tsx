import { useCallback, useEffect, useMemo, useState, type FC } from "react";
import { useConnection, useWallet } from "@solana/wallet-adapter-react";
import {
  PublicKey,
  SystemProgram,
  Transaction,
  TransactionInstruction,
  Keypair,
} from "@solana/web3.js";
import { envProgramId, envStateAccount, loadDefaultIdl, loadDeployment } from "./config";
import { encodePfIxData, readU64Le } from "./ix";
import type { DeploymentFile, PfIdl, PfIdlInstruction } from "./types";

type LogLine = { at: string; text: string; kind?: "ok" | "bad" | "info" };

function findIx(idl: PfIdl, name: string): PfIdlInstruction | undefined {
  return idl.instructions.find((i) => i.name === name);
}

export const DappPanel: FC = () => {
  const { connection } = useConnection();
  const wallet = useWallet();
  const [deployment, setDeployment] = useState<DeploymentFile | null>(null);
  const [idl, setIdl] = useState<PfIdl | null>(null);
  const [programIdStr, setProgramIdStr] = useState(envProgramId());
  const [stateStr, setStateStr] = useState(envStateAccount());
  const [count, setCount] = useState<string | null>(null);
  const [delta, setDelta] = useState("5");
  const [ctorInitial, setCtorInitial] = useState("7");
  const [busy, setBusy] = useState(false);
  const [logs, setLogs] = useState<LogLine[]>([]);

  const pushLog = useCallback((text: string, kind: LogLine["kind"] = "info") => {
    const at = new Date().toISOString().slice(11, 19);
    setLogs((prev) => [{ at, text, kind }, ...prev].slice(0, 50));
  }, []);

  useEffect(() => {
    void (async () => {
      const dep = await loadDeployment();
      if (dep) {
        setDeployment(dep);
        setIdl(dep.idl);
        setProgramIdStr(dep.programId);
        setStateStr(dep.stateAccount);
        pushLog(
          `loaded deployment.json program=${dep.program} id=${dep.programId.slice(0, 8)}…`,
          "ok",
        );
        return;
      }
      try {
        const i = await loadDefaultIdl();
        setIdl(i);
        pushLog(
          `loaded default ${i.programName ?? "StateCell"}.idl.json (no deployment.json yet)`,
          "info",
        );
      } catch (e) {
        pushLog(`IDL load failed: ${e instanceof Error ? e.message : String(e)}`, "bad");
      }
    })();
  }, [pushLog]);

  const programId = useMemo(() => {
    try {
      return programIdStr ? new PublicKey(programIdStr) : null;
    } catch {
      return null;
    }
  }, [programIdStr]);

  const stateKey = useMemo(() => {
    try {
      return stateStr ? new PublicKey(stateStr) : null;
    } catch {
      return null;
    }
  }, [stateStr]);

  const refreshCount = useCallback(async () => {
    if (!stateKey) {
      setCount(null);
      return;
    }
    try {
      const info = await connection.getAccountInfo(stateKey, "confirmed");
      if (!info) {
        setCount(null);
        pushLog("state account missing on RPC", "bad");
        return;
      }
      // StateCell layout (ordinary single-state): first u64 after PF header varies by
      // profile; product CPI state often stores count at a fixed leaf. Demo reads
      // bytes[0..8] when data is short, else tries offset 0 then 8.
      const data = info.data;
      let value: bigint;
      try {
        value = readU64Le(data, 0);
        // Heuristic: if looks like a length/tag with huge value, try +8
        if (value > 1_000_000_000_000n && data.length >= 16) {
          value = readU64Le(data, 8);
        }
      } catch (e) {
        throw e;
      }
      setCount(value.toString());
      pushLog(`state u64@0 = ${value.toString()} (raw read; confirm layout for your profile)`, "ok");
    } catch (e) {
      setCount(null);
      pushLog(`read state failed: ${e instanceof Error ? e.message : String(e)}`, "bad");
    }
  }, [connection, stateKey, pushLog]);

  useEffect(() => {
    void refreshCount();
  }, [refreshCount]);

  const sendHandler = async (ixName: string, params: bigint[]) => {
    if (!idl || !programId || !stateKey) {
      pushLog("need IDL + programId + state account", "bad");
      return;
    }
    if (!wallet.publicKey || !wallet.sendTransaction) {
      pushLog("connect a wallet first", "bad");
      return;
    }
    const spec = findIx(idl, ixName);
    if (!spec) {
      pushLog(`IDL missing instruction '${ixName}'`, "bad");
      return;
    }
    setBusy(true);
    try {
      const data = encodePfIxData(spec.handlerId, params);
      const isWritable = Boolean(spec.accounts[0]?.outerWritable ?? true);
      // state is program-owned — never marked signer here; wallet is fee payer only.
      const ix = new TransactionInstruction({
        programId,
        keys: [{ pubkey: stateKey, isSigner: false, isWritable }],
        data,
      });
      // Prefer wallet as fee payer only
      const tx = new Transaction().add(ix);
      tx.feePayer = wallet.publicKey;
      const { blockhash } = await connection.getLatestBlockhash();
      tx.recentBlockhash = blockhash;
      const sig = await wallet.sendTransaction(tx, connection, {
        skipPreflight: false,
      });
      pushLog(`${ixName} sig=${sig}`, "ok");
      await connection.confirmTransaction(sig, "confirmed");
      await refreshCount();
    } catch (e) {
      pushLog(`${ixName} failed: ${e instanceof Error ? e.message : String(e)}`, "bad");
    } finally {
      setBusy(false);
    }
  };

  const onCreateStateAccount = async () => {
    // Helper for local demos: allocate a 16-byte system account the user owns,
    // then hand to program (ownership transfer depends on program init).
    if (!wallet.publicKey || !wallet.signTransaction) {
      pushLog("connect wallet that can sign", "bad");
      return;
    }
    setBusy(true);
    try {
      const kp = Keypair.generate();
      const lamports = await connection.getMinimumBalanceForRentExemption(16);
      const tx = new Transaction().add(
        SystemProgram.createAccount({
          fromPubkey: wallet.publicKey,
          newAccountPubkey: kp.publicKey,
          lamports,
          space: 16,
          programId: programId ?? SystemProgram.programId,
        }),
      );
      tx.feePayer = wallet.publicKey;
      const { blockhash } = await connection.getLatestBlockhash();
      tx.recentBlockhash = blockhash;
      tx.partialSign(kp);
      const signed = await wallet.signTransaction(tx);
      const sig = await connection.sendRawTransaction(signed.serialize());
      await connection.confirmTransaction(sig, "confirmed");
      setStateStr(kp.publicKey.toBase58());
      pushLog(`created state account ${kp.publicKey.toBase58()} sig=${sig}`, "ok");
    } catch (e) {
      pushLog(`createAccount failed: ${e instanceof Error ? e.message : String(e)}`, "bad");
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="panel">
      <div className="row">
        <label>RPC</label>
        <code>{connection.rpcEndpoint}</code>
        {deployment ? <span className="ok">deployment.json</span> : null}
      </div>
      <div className="row">
        <label>programId</label>
        <input
          value={programIdStr}
          onChange={(e) => setProgramIdStr(e.target.value.trim())}
          placeholder="after pf deploy --network local"
          spellCheck={false}
        />
      </div>
      <div className="row">
        <label>state account</label>
        <input
          value={stateStr}
          onChange={(e) => setStateStr(e.target.value.trim())}
          placeholder="program-owned state pubkey"
          spellCheck={false}
        />
        <button type="button" disabled={busy || !programId} onClick={() => void onCreateStateAccount()}>
          Create 16B account (local helper)
        </button>
      </div>
      <div className="row">
        <label>count (raw)</label>
        <strong>{count ?? "—"}</strong>
        <button type="button" disabled={busy} onClick={() => void refreshCount()}>
          Refresh
        </button>
      </div>
      <div className="row">
        <label>init initial</label>
        <input value={ctorInitial} onChange={(e) => setCtorInitial(e.target.value)} />
        <button
          type="button"
          disabled={busy}
          onClick={() => void sendHandler("init", [BigInt(ctorInitial || "0")])}
        >
          Send init
        </button>
      </div>
      <div className="row">
        <label>increment δ</label>
        <input value={delta} onChange={(e) => setDelta(e.target.value)} />
        <button
          type="button"
          disabled={busy}
          onClick={() => void sendHandler("increment", [BigInt(delta || "0")])}
        >
          Send increment
        </button>
        <button type="button" disabled={busy} onClick={() => void sendHandler("get", [])}>
          Send get (ix)
        </button>
      </div>
      <p style={{ fontSize: "0.9rem", opacity: 0.9 }}>
        ix-data = <code>handlerId u64 LE</code> + <code>u64 LE params</code> (PF encoding, not
        Anchor sighash). IDL from <code>pf build -t solana</code>. Wallet only signs; compile stays
        on <code>pf</code>.
      </p>
      <div className="logs">
        {logs.length === 0 ? <div>no logs yet</div> : null}
        {logs.map((l, i) => (
          <div key={`${l.at}-${i}`} className={l.kind === "ok" ? "ok" : l.kind === "bad" ? "bad" : ""}>
            <code>{l.at}</code> {l.text}
          </div>
        ))}
      </div>
    </div>
  );
};
