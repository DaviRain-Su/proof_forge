/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Crosscall materialization (portable intent → native form)

Authors never write CPI metas, Promise chains, or STATICCALL opcodes in the
portable path. They express **business** cross-contract intent
(`crosscall.invoke` capability / portable IR crosscall nodes). Each target
materializes that intent into its native call model:

| Target family | Native form of portable `crosscall.invoke` |
|---|---|
| EVM | CALL (typed variants may map to STATICCALL/DELEGATECALL only via extension) — **no account metas** |
| Solana | CPI frame (`sol_invoke_signed_c` + account metas/infos + entrypoint account validation prologue) |
| Wasm-NEAR | host `promise_create` (async; string pool for account/method names) |
| Wasm-Soroban | host `invoke_contract` (sync host adapter; same string pool; **not** NEAR Promise) |
| Wasm-CosmWasm | WasmMsg / submessage (deferred spike) |
| Wasm-Cloudflare | HTTP/service binding call (off-chain; deferred) |
| Move Aptos/Sui | entry function call / object call (spike-level) |
| Psy / Aleo | circuit / transition call (restricted; often reject full async) |

Solana-only: account **checks** (signer/writable/owner) live in entrypoint
prologue materialization (`lowerAccountValidations`), not in portable IR —
same layer as Anchor constraints / Pinocchio manual checks.

This module is the product vocabulary for that mapping. Full async Promise /
CPI packing remains in backends; here we expose an auditable, target-keyed
report so operators see how portable crosscall is realized.
-/
import ProofForge.IR.Contract
import ProofForge.Target.Registry
import ProofForge.Target.Capability

namespace ProofForge.Target.CrosscallMaterialize

open ProofForge.IR
open ProofForge.Target

/-- Native realization of portable cross-contract intent. -/
inductive NativeForm where
  | evmCall
  | solanaCpi
  | nearPromise
  | cosmWasmMsg
  | workersBinding
  | sorobanInvoke
  | moveCall
  | zkCircuitCall
  | unsupported
  deriving BEq, DecidableEq, Repr

def NativeForm.id : NativeForm → String
  | .evmCall => "evm-call"
  | .solanaCpi => "solana-cpi"
  | .nearPromise => "near-promise"
  | .cosmWasmMsg => "cosmwasm-msg"
  | .workersBinding => "workers-binding"
  | .sorobanInvoke => "soroban-invoke"
  | .moveCall => "move-call"
  | .zkCircuitCall => "zk-circuit-call"
  | .unsupported => "unsupported"

def NativeForm.describe : NativeForm → String
  | .evmCall => "EVM CALL (portable crosscall.invoke)"
  | .solanaCpi => "Solana CPI (crosscall.cpi + synthesized account metas)"
  | .nearPromise => "NEAR Promise / host cross-contract call"
  | .cosmWasmMsg => "CosmWasm WasmMsg / submessage"
  | .workersBinding => "Cloudflare Workers service binding / fetch"
  | .sorobanInvoke => "Soroban host invoke_contract (portable crosscall.invoke)"
  | .moveCall => "Move entry/object call (sourcegen)"
  | .zkCircuitCall => "ZK circuit/transition call (restricted subset)"
  | .unsupported => "target does not materialize portable crosscall yet"

structure Report where
  targetId : String
  nativeForm : NativeForm
  capabilityId : String
  asyncSupport : String
  note : String
  deriving Repr

/-! Linear record materialization reporting

`StructDecl.isRecord` carries consumable/linear semantics. Only Aleo currently
has a native adapter; every other registered target reports an explicit reject
so tooling cannot silently present the type as an ordinary copyable struct. -/

inductive LinearRecordDisposition where
  | materialize
  | reject
  deriving BEq, DecidableEq, Repr

structure LinearRecordReport where
  targetId : String
  disposition : LinearRecordDisposition
  note : String
  deriving Repr

def linearRecordForProfile (profile : TargetProfile) : LinearRecordReport :=
  if profile.capabilities.contains .dataLinearRecord then
    { targetId := profile.id
      disposition := .materialize
      note := "linear_record materializes as a Leo record with owner semantics" }
  else
    { targetId := profile.id
      disposition := .reject
      note := "target has no declared linear-record materialization; reject instead of lowering as a value struct" }

def linearRecordReportsForAllImplemented : Array LinearRecordReport :=
  all.map linearRecordForProfile

private def jsonStr (s : String) : String := "\"" ++ s ++ "\""

def Report.json (r : Report) : String :=
  "{" ++
  "\"targetId\":" ++ jsonStr r.targetId ++ "," ++
  "\"nativeForm\":" ++ jsonStr r.nativeForm.id ++ "," ++
  "\"capabilityId\":" ++ jsonStr r.capabilityId ++ "," ++
  "\"asyncSupport\":" ++ jsonStr r.asyncSupport ++ "," ++
  "\"note\":" ++ jsonStr r.note ++
  "}"

/-- Map a registry profile to the native crosscall form for portable intent. -/
def forProfile (profile : TargetProfile) : Report :=
  let form :=
    match profile.id with
    | "evm" => NativeForm.evmCall
    | "solana-sbpf-asm" => NativeForm.solanaCpi
    | "wasm-near" => NativeForm.nearPromise
    | "wasm-cosmwasm" => NativeForm.cosmWasmMsg
    | "wasm-cloudflare-workers" => NativeForm.workersBinding
    | "wasm-stellar-soroban" => NativeForm.sorobanInvoke
    | "move-aptos" | "move-sui" => NativeForm.moveCall
    | "psy-dpn" | "aleo-leo" => NativeForm.zkCircuitCall
    | _ =>
        match profile.family with
        | .evm => NativeForm.evmCall
        | .solana => NativeForm.solanaCpi
        | .wasmHost =>
            match profile.hostBridge? with
            | some .near => NativeForm.nearPromise
            | some .cosmWasm => NativeForm.cosmWasmMsg
            | some .soroban => NativeForm.sorobanInvoke
            | none => NativeForm.workersBinding
        | .move => NativeForm.moveCall
        | .zkCircuitSourcegen => NativeForm.zkCircuitCall
  let capabilityId :=
    match form with
    | .solanaCpi => Capability.crosscallCpi.id
    | .nearPromise => Capability.nearPromise.id
    | .sorobanInvoke => Capability.crosscallInvoke.id
    | .unsupported => "crosscall.unsupported"
    | _ => Capability.crosscallInvoke.id
  let asyncSupport :=
    match form with
    | .nearPromise => "async-promise"
    | .cosmWasmMsg => "submessage-async"
    | .solanaCpi => "sync-cpi"
    | .evmCall => "sync-call"
    | .workersBinding => "async-fetch"
    | .sorobanInvoke => "sync-host-invoke"
    | .moveCall => "sync-entry-call"
    | .zkCircuitCall => "circuit-static"
    | .unsupported => "none"
  let note :=
    match form with
    | .evmCall =>
        "Portable crosscall.invoke → EVM CALL; STATICCALL/DELEGATECALL/create remain EVM extensions"
    | .solanaCpi =>
        "Portable crosscall.invoke → Solana CPI (method+args ix data; selective accounts; PDA signers when declared; Source.Solana for protocol layouts)"
    | .nearPromise =>
        "Portable crosscall.invoke → NEAR promise_create (nearCrosscallStrings string pool for account/method names)"
    | .cosmWasmMsg =>
        "Portable crosscall.invoke → CosmWasm execute_msg host stub (WasmMsg-shaped; general peer remote, not token-only)"
    | .workersBinding =>
        "Portable crosscall.invoke reinterpreted as Workers binding/fetch (deferred off-chain host)"
    | .sorobanInvoke =>
        "Portable crosscall.invoke → Soroban host invoke_contract (string pool + JSON args; not NEAR promise_create)"
    | .moveCall =>
        "Portable crosscall.invoke → Move package call shape (spike; limited coverage)"
    | .zkCircuitCall =>
        "Portable crosscall restricted in ZK lanes; Psy accepts untyped U64 crosscall, typed/create rejected"
    | .unsupported =>
        "No portable crosscall materialization for this target"
  { targetId := profile.id
    nativeForm := form
    capabilityId := capabilityId
    asyncSupport := asyncSupport
    note := note }

def reportsForAllImplemented : Array Report :=
  all.map forProfile

/-- Whether the module IR uses any portable crosscall-shaped expression. -/
partial def moduleUsesPortableCrosscall (module : Module) : Bool :=
  module.entrypoints.any fun ep =>
    ep.body.any stmtUses
where
  exprUses : Expr → Bool
    | .crosscallInvoke .. | .crosscallInvokeTyped .. | .crosscallInvokeValueTyped ..
    | .crosscallInvokeStaticTyped .. | .crosscallInvokeDelegateTyped ..
    | .crosscallCreate .. | .crosscallCreate2 ..
    | .nearCrosscallInvokePool .. | .nearPromiseThen .. => true
    | .crosscallNamed _ _ args _ => args.any exprUses
    | .effect e => effectUses e
    | .add a b _ | .sub a b _ | .mul a b _ | .div a b | .mod a b | .pow a b
    | .bitAnd a b | .bitOr a b | .bitXor a b | .shiftLeft a b | .shiftRight a b
    | .eq a b | .ne a b | .lt a b | .le a b | .gt a b | .ge a b
    | .boolAnd a b | .boolOr a b | .hashTwoToOne a b => exprUses a || exprUses b
    | .ecrecover a b c d => exprUses a || exprUses b || exprUses c || exprUses d
    | .eip712PermitDigest a b c d e f =>
        exprUses a || exprUses b || exprUses c || exprUses d || exprUses e || exprUses f
    | .crosscallAbiPacked target _ _ _ _ _ _ _ _ => exprUses target
    | .cast a _ | .boolNot a | .hash a | .memoryArrayLength a | .field a _
    | .nearPromiseResultStatus a | .nearPromiseResultU64 a => exprUses a
    | .arrayLit _ xs => xs.any exprUses
    | .structLit _ fs => fs.any (fun f => exprUses f.snd)
    | .arrayGet a i | .memoryArrayGet a i => exprUses a || exprUses i
    | .memoryArrayNew _ len => exprUses len
    | .hashValue a b c d => exprUses a || exprUses b || exprUses c || exprUses d
    | .literal _ | .local _ | .nativeValue | .nearPromiseResultsCount => false
  effectUses : Effect → Bool
    | .storageScalarWrite _ v | .storageScalarAssignOp _ _ v
    | .storageStructFieldWrite _ _ v | .storageDynamicArrayPush _ v => exprUses v
    | .storageMapContains _ k | .storageMapGet _ k | .storageArrayRead _ k => exprUses k
    | .storageMapInsert _ k v | .storageMapSet _ k v | .storageArrayWrite _ k v
    | .storageArrayStructFieldWrite _ k _ v => exprUses k || exprUses v
    | .memoryArraySet a i v => exprUses a || exprUses i || exprUses v
    | .storagePathRead _ path => path.any pathUses
    | .storagePathWrite _ path v | .storagePathAssignOp _ path _ v =>
        path.any pathUses || exprUses v
    | .eventEmit _ fs => fs.any (fun f => exprUses f.snd)
    | .eventEmitIndexed _ indexed data =>
        indexed.any (fun f => exprUses f.snd) || data.any (fun f => exprUses f.snd)
    | .checkErc721Received a b c d =>
        exprUses a || exprUses b || exprUses c || exprUses d
    | .checkErc1155Received a b c d e =>
        exprUses a || exprUses b || exprUses c || exprUses d || exprUses e
    | .checkErc1155BatchReceived a b c d e f g =>
        exprUses a || exprUses b || exprUses c || exprUses d || exprUses e || exprUses f || exprUses g
    | .storageScalarRead _ | .storageStructFieldRead _ _ | .storageDynamicArrayPop _
    | .storageArrayStructFieldRead _ _ _ | .contextRead _ => false
  pathUses : StoragePathSegment → Bool
    | .field _ => false
    | .index i | .mapKey i => exprUses i
  stmtUses : Statement → Bool
    | .letBind _ _ v | .letMutBind _ _ v | .return v => exprUses v
    | .assign a b | .assignOp a _ b | .assertEq a b _ _ => exprUses a || exprUses b
    | .effect e => effectUses e
    | .assert c _ _ => exprUses c
    | .ifElse c t e => exprUses c || t.any stmtUses || e.any stmtUses
    | .boundedFor _ _ _ body => body.any stmtUses
    | .whileLoop c body => exprUses c || body.any stmtUses
    | .revert _ | .revertWithError _ | .release _ => false

/-! ### Sync request-response subset (gap-analysis route step 3)

**Policy (locked):** portable authors only use **sync request-response**
crosscall (`crosscallInvoke*` / `declareRemote`+`remoteCall`). They never
write NEAR promise chains, callbacks, or result polls.

| Target | Portable sync form | Author account metas? |
|--------|--------------------|------------------------|
| EVM | CALL (sync) | no |
| Solana | CPI (`sol_invoke_signed_c`); accounts **inferred** from peer + state | no |
| NEAR | `promise_create` only (fire-and-forget / no result in same receipt); raw promise_then / result APIs are **host-extension only** | no |

Full async/continuation is a non-goal. NEAR authors who need results use
host-extension nodes and leave the portable product path.
-/

/-- Explicit portable crosscall policy. -/
inductive SyncSubsetPolicy where
  /-- Only request-response shaped portable remotes; no author-facing async. -/
  | syncRequestResponseOnly
  deriving BEq, DecidableEq, Repr

def SyncSubsetPolicy.id : SyncSubsetPolicy → String
  | .syncRequestResponseOnly => "sync-request-response-only"

/-- Locked product policy for portable crosscall. -/
def portableCrosscallPolicy : SyncSubsetPolicy := .syncRequestResponseOnly

/-- Host-extension / non-portable async NEAR nodes (escape hatch). -/
partial def moduleUsesNearAsyncExtension (module : Module) : Bool :=
  module.entrypoints.any fun ep =>
    ep.body.any stmtUses
where
  exprUses : Expr → Bool
    | .nearPromiseThen .. | .nearPromiseResultsCount
    | .nearPromiseResultStatus _ | .nearPromiseResultU64 _ => true
    | .nearCrosscallInvokePool .. => false  -- still promise_create shaped
    | .effect e => effectUses e
    | .add a b _ | .sub a b _ | .mul a b _ | .div a b | .mod a b | .pow a b
    | .bitAnd a b | .bitOr a b | .bitXor a b | .shiftLeft a b | .shiftRight a b
    | .eq a b | .ne a b | .lt a b | .le a b | .gt a b | .ge a b
    | .boolAnd a b | .boolOr a b | .hashTwoToOne a b => exprUses a || exprUses b
    | .ecrecover a b c d => exprUses a || exprUses b || exprUses c || exprUses d
    | .eip712PermitDigest a b c d e f =>
        exprUses a || exprUses b || exprUses c || exprUses d || exprUses e || exprUses f
    | .crosscallAbiPacked target _ _ _ _ _ dynLen? _ dynTargets =>
        exprUses target ||
          (match dynLen? with | some e => exprUses e | none => false) ||
          dynTargets.any exprUses
    | .cast a _ | .boolNot a | .hash a | .memoryArrayLength a | .field a _ => exprUses a
    | .arrayLit _ xs => xs.any exprUses
    | .structLit _ fs => fs.any (fun f => exprUses f.snd)
    | .arrayGet a i | .memoryArrayGet a i => exprUses a || exprUses i
    | .memoryArrayNew _ len => exprUses len
    | .hashValue a b c d => exprUses a || exprUses b || exprUses c || exprUses d
    | .crosscallInvoke a b args => exprUses a || exprUses b || args.any exprUses
    | .crosscallInvokeTyped a b args _ => exprUses a || exprUses b || args.any exprUses
    | .crosscallInvokeValueTyped a b c args _ =>
        exprUses a || exprUses b || exprUses c || args.any exprUses
    | .crosscallInvokeStaticTyped a b args _ | .crosscallInvokeDelegateTyped a b args _ =>
        exprUses a || exprUses b || args.any exprUses
    | .crosscallCreate a _ => exprUses a
    | .crosscallCreate2 a b _ => exprUses a || exprUses b
    | .crosscallNamed _ _ args _ => args.any exprUses
    | .literal _ | .local _ | .nativeValue => false
  effectUses : Effect → Bool
    | .storageScalarWrite _ v | .storageScalarAssignOp _ _ v
    | .storageStructFieldWrite _ _ v | .storageDynamicArrayPush _ v => exprUses v
    | .storageMapContains _ k | .storageMapGet _ k | .storageArrayRead _ k => exprUses k
    | .storageMapInsert _ k v | .storageMapSet _ k v | .storageArrayWrite _ k v
    | .storageArrayStructFieldWrite _ k _ v => exprUses k || exprUses v
    | .memoryArraySet a i v => exprUses a || exprUses i || exprUses v
    | .storagePathRead _ path => path.any pathUses
    | .storagePathWrite _ path v | .storagePathAssignOp _ path _ v =>
        path.any pathUses || exprUses v
    | .eventEmit _ fs => fs.any (fun f => exprUses f.snd)
    | .eventEmitIndexed _ indexed data =>
        indexed.any (fun f => exprUses f.snd) || data.any (fun f => exprUses f.snd)
    | .checkErc721Received a b c d =>
        exprUses a || exprUses b || exprUses c || exprUses d
    | .checkErc1155Received a b c d e =>
        exprUses a || exprUses b || exprUses c || exprUses d || exprUses e
    | .checkErc1155BatchReceived a b c d e f g =>
        exprUses a || exprUses b || exprUses c || exprUses d || exprUses e || exprUses f || exprUses g
    | .storageScalarRead _ | .storageStructFieldRead _ _ | .storageDynamicArrayPop _
    | .storageArrayStructFieldRead _ _ _ | .contextRead _ => false
  pathUses : StoragePathSegment → Bool
    | .field _ => false
    | .index i | .mapKey i => exprUses i
  stmtUses : Statement → Bool
    | .letBind _ _ v | .letMutBind _ _ v | .return v => exprUses v
    | .assign a b | .assignOp a _ b | .assertEq a b _ _ => exprUses a || exprUses b
    | .effect e => effectUses e
    | .assert c _ _ => exprUses c
    | .ifElse c t e => exprUses c || t.any stmtUses || e.any stmtUses
    | .boundedFor _ _ _ body => body.any stmtUses
    | .whileLoop c body => exprUses c || body.any stmtUses
    | .revert _ | .revertWithError _ | .release _ => false

/-- Reject when portable path is claimed but module uses NEAR async escape hatches. -/
def requireSyncSubset (module : Module) : Except String Unit :=
  if moduleUsesNearAsyncExtension module then
    .error
      "CrosscallMaterialize: portable sync-subset policy rejects NEAR promise_then / \
promise_result* host extensions; use portable crosscallInvoke only, or mark the \
module host-extension (not portable product path)"
  else
    .ok ()

/-- One inferred Solana account role for a portable remote (no author metas). -/
structure InferredAccount where
  name : String
  role : String
  signer : Bool := false
  writable : Bool := false
  deriving Repr, BEq

/-- Infer Solana CPI account set for a portable remote to `peerId`.

Authors never pass account metas. Inference uses:
* always: payer (signer+writable), peer program, system program
* module state ids → writable data accounts
* when peer looks like SPL token program → token program + ATAs placeholders

If peer is empty, reject with a diagnostic naming the missing inference input. -/
def inferSolanaAccounts (module : Module) (peerId : String) :
    Except String (Array InferredAccount) :=
  if peerId.isEmpty then
    .error
      "CrosscallMaterialize: cannot infer Solana accounts for portable remote — \
peer id is empty (declareRemote / PeerMap required)"
  else
    let stateAccounts : Array InferredAccount :=
      module.state.map fun s =>
        { name := s.id
          role := "program-state"
          signer := false
          writable := true }
    let base : Array InferredAccount := #[
      { name := "payer", role := "fee-payer", signer := true, writable := true },
      { name := "peer_program", role := s!"peer:{peerId}", signer := false, writable := false },
      { name := "system_program", role := "system-program", signer := false, writable := false }
    ]
    let tokenish :=
      peerId == "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA" ||
      peerId == "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb" ||
      peerId.startsWith "spl-token" ||
      peerId.startsWith "token-2022"
    let tokenExtra : Array InferredAccount :=
      if tokenish then
        #[
          { name := "token_program", role := "spl-token-program", signer := false, writable := false },
          { name := "source_ata", role := "source-ata", signer := false, writable := true },
          { name := "dest_ata", role := "dest-ata", signer := false, writable := true }
        ]
      else #[]
    .ok (base ++ stateAccounts ++ tokenExtra)

/-- Materialize a portable sync remote on one triad target. -/
structure SyncRemoteMaterialization where
  targetId : String
  nativeForm : NativeForm
  asyncSupport : String
  inferredAccounts? : Option (Array InferredAccount) := none
  note : String
  deriving Repr

def materializeSyncRemote (targetId : String) (module : Module) (peerId : String) :
    Except String SyncRemoteMaterialization := do
  requireSyncSubset module
  match targetId with
  | "evm" =>
      .ok {
        targetId := targetId
        nativeForm := .evmCall
        asyncSupport := "sync-call"
        inferredAccounts? := none
        note := "portable remote → EVM CALL; no account metas"
      }
  | "solana-sbpf-asm" =>
      let accounts ← inferSolanaAccounts module peerId
      .ok {
        targetId := targetId
        nativeForm := .solanaCpi
        asyncSupport := "sync-cpi"
        inferredAccounts? := some accounts
        note :=
          s!"portable remote → Solana CPI; {accounts.size} accounts inferred \
(authors do not pass metas)"
      }
  | "wasm-near" =>
      .ok {
        targetId := targetId
        nativeForm := .nearPromise
        asyncSupport := "promise-create-only"
        inferredAccounts? := none
        note :=
          "portable sync-subset → env.promise_create only (no result in same receipt); \
promise_then / promise_result* are host-extension and rejected by requireSyncSubset"
      }
  | _ =>
      .error
        s!"CrosscallMaterialize: no sync-remote materialize row for target `{targetId}`"

end ProofForge.Target.CrosscallMaterialize
