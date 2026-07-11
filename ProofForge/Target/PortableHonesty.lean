/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Portable honesty pipeline (gap-analysis full implementation)

Invokes HostEnv / Identity / sync-crosscall / upgrade catalogs from the
**real** resolve path so unsupported uses fail closed before codegen.

Called from `Adapter.defaultResolve` (resolveSpec / resolveModule).
-/
import ProofForge.IR.Contract
import ProofForge.Target.HostRuntime
import ProofForge.Target.Identity
import ProofForge.Target.CrosscallMaterialize
import ProofForge.Target.PortableMechanics
import ProofForge.Contract.UpgradePolicy
import ProofForge.Contract.UpgradePolicy.Lower

namespace ProofForge.Target.PortableHonesty

open ProofForge.IR
open ProofForge.Target.HostRuntime
open ProofForge.Target.Identity
open ProofForge.Target.CrosscallMaterialize
open ProofForge.Target.PortableMechanics
open ProofForge.Contract
open ProofForge.Contract.UpgradePolicy

/-! ### Collect context / crosscall shape from IR -/

partial def collectContextFields (module : Module) : Array ContextField :=
  module.entrypoints.foldl (init := #[]) fun acc ep =>
    ep.body.foldl (init := acc) pushStmt
where
  pushUnique (acc : Array ContextField) (f : ContextField) : Array ContextField :=
    if acc.any (fun x => x.name == f.name) then acc else acc.push f
  pushExpr (acc : Array ContextField) : Expr → Array ContextField
    | .effect e => pushEffect acc e
    | .add a b _ | .sub a b _ | .mul a b _ | .div a b | .mod a b | .pow a b
    | .bitAnd a b | .bitOr a b | .bitXor a b | .shiftLeft a b | .shiftRight a b
    | .eq a b | .ne a b | .lt a b | .le a b | .gt a b | .ge a b
    | .boolAnd a b | .boolOr a b | .hashTwoToOne a b => pushExpr (pushExpr acc a) b
    | .ecrecover a b c d => pushExpr (pushExpr (pushExpr (pushExpr acc a) b) c) d
    | .eip712PermitDigest a b c d e f =>
        pushExpr (pushExpr (pushExpr (pushExpr (pushExpr (pushExpr acc a) b) c) d) e) f
    | .crosscallAbiPacked t _ _ _ _ _ dynLen? _ dynTargets =>
        let acc := pushExpr acc t
        let acc := match dynLen? with | some e => pushExpr acc e | none => acc
        dynTargets.foldl pushExpr acc
    | .cast a _ | .boolNot a | .hash a | .memoryArrayLength a | .field a _ => pushExpr acc a
    | .arrayLit _ xs => xs.foldl pushExpr acc
    | .structLit _ fs => fs.foldl (fun a f => pushExpr a f.snd) acc
    | .arrayGet a i | .memoryArrayGet a i => pushExpr (pushExpr acc a) i
    | .memoryArrayNew _ len => pushExpr acc len
    | .hashValue a b c d => pushExpr (pushExpr (pushExpr (pushExpr acc a) b) c) d
    | .crosscallInvoke a b args | .crosscallInvokeTyped a b args _
    | .crosscallInvokeStaticTyped a b args _ | .crosscallInvokeDelegateTyped a b args _ =>
        args.foldl pushExpr (pushExpr (pushExpr acc a) b)
    | .crosscallInvokeValueTyped a b c args _ =>
        args.foldl pushExpr (pushExpr (pushExpr (pushExpr acc a) b) c)
    | .crosscallCreate a _ => pushExpr acc a
    | .crosscallCreate2 a b _ => pushExpr (pushExpr acc a) b
    | .crosscallNamed _ _ args _ => args.foldl pushExpr acc
    | .nearCrosscallInvokePool a b args d =>
        args.foldl pushExpr (pushExpr (pushExpr (pushExpr acc a) b) d)
    | .nearPromiseThen a b args d =>
        args.foldl pushExpr (pushExpr (pushExpr (pushExpr acc a) b) d)
    | .nearPromiseResultStatus a | .nearPromiseResultU64 a => pushExpr acc a
    | .literal _ | .local _ | .nativeValue | .nearPromiseResultsCount => acc
  pushEffect (acc : Array ContextField) : Effect → Array ContextField
    | .contextRead f => pushUnique acc f
    | .storageScalarWrite _ v | .storageScalarAssignOp _ _ v
    | .storageStructFieldWrite _ _ v | .storageDynamicArrayPush _ v => pushExpr acc v
    | .storageMapContains _ k | .storageMapGet _ k | .storageMapDelete _ k | .storageArrayRead _ k => pushExpr acc k
    | .storageMapInsert _ k v | .storageMapSet _ k v | .storageArrayWrite _ k v
    | .storageArrayStructFieldWrite _ k _ v => pushExpr (pushExpr acc k) v
    | .memoryArraySet a i v => pushExpr (pushExpr (pushExpr acc a) i) v
    | .storagePathRead _ path => path.foldl pushPath acc
    | .storagePathWrite _ path v | .storagePathAssignOp _ path _ v =>
        pushExpr (path.foldl pushPath acc) v
    | .eventEmit _ fs => fs.foldl (fun a f => pushExpr a f.snd) acc
    | .eventEmitIndexed _ ix data =>
        data.foldl (fun a f => pushExpr a f.snd) (ix.foldl (fun a f => pushExpr a f.snd) acc)
    | .checkErc721Received a b c d =>
        pushExpr (pushExpr (pushExpr (pushExpr acc a) b) c) d
    | .checkErc1155Received a b c d e =>
        pushExpr (pushExpr (pushExpr (pushExpr (pushExpr acc a) b) c) d) e
    | .checkErc1155BatchReceived a b c d e =>
        pushExpr (pushExpr (pushExpr (pushExpr (pushExpr acc a) b) c) d) e
    | .storageScalarRead _ | .storageStructFieldRead _ _ | .storageDynamicArrayPop _
    | .storageArrayStructFieldRead _ _ _ => acc
  pushPath (acc : Array ContextField) : StoragePathSegment → Array ContextField
    | .field _ => acc
    | .index i | .mapKey i => pushExpr acc i
  pushStmt (acc : Array ContextField) : Statement → Array ContextField
    | .letBind _ _ v | .letMutBind _ _ v | .return v => pushExpr acc v
    | .assign a b | .assignOp a _ b | .assertEq a b _ _ => pushExpr (pushExpr acc a) b
    | .effect e => pushEffect acc e
    | .assert c _ _ => pushExpr acc c
    | .ifElse c t e => e.foldl pushStmt (t.foldl pushStmt (pushExpr acc c))
    | .boundedFor _ _ _ body => body.foldl pushStmt acc
    | .whileLoop c body => body.foldl pushStmt (pushExpr acc c)
    | .revert _ | .revertWithError _ | .release _ => acc

/-- Portable sync remotes only (not NEAR host-extension promise APIs). -/
partial def moduleUsesPortableSyncCrosscall (module : Module) : Bool :=
  module.entrypoints.any fun ep =>
    ep.body.any stmtUses
where
  exprUses : Expr → Bool
    | .crosscallInvoke .. | .crosscallInvokeTyped .. | .crosscallInvokeValueTyped ..
    | .crosscallInvokeStaticTyped .. | .crosscallInvokeDelegateTyped .. => true
    | .crosscallAbiPacked .. => true
    | .effect e => effectUses e
    | .add a b _ | .sub a b _ | .mul a b _ | .div a b | .mod a b | .pow a b
    | .bitAnd a b | .bitOr a b | .bitXor a b | .shiftLeft a b | .shiftRight a b
    | .eq a b | .ne a b | .lt a b | .le a b | .gt a b | .ge a b
    | .boolAnd a b | .boolOr a b | .hashTwoToOne a b => exprUses a || exprUses b
    | .ecrecover a b c d => exprUses a || exprUses b || exprUses c || exprUses d
    | .eip712PermitDigest a b c d e f =>
        exprUses a || exprUses b || exprUses c || exprUses d || exprUses e || exprUses f
    | .cast a _ | .boolNot a | .hash a | .memoryArrayLength a | .field a _
    | .nearPromiseResultStatus a | .nearPromiseResultU64 a => exprUses a
    | .arrayLit _ xs => xs.any exprUses
    | .structLit _ fs => fs.any (fun f => exprUses f.snd)
    | .arrayGet a i | .memoryArrayGet a i => exprUses a || exprUses i
    | .memoryArrayNew _ len => exprUses len
    | .hashValue a b c d => exprUses a || exprUses b || exprUses c || exprUses d
    | .crosscallCreate a _ => exprUses a
    | .crosscallCreate2 a b _ => exprUses a || exprUses b
    | .crosscallNamed _ _ args _ => args.any exprUses
    | .nearCrosscallInvokePool a b args d =>
        exprUses a || exprUses b || args.any exprUses || exprUses d
    | .nearPromiseThen a b args d =>
        exprUses a || exprUses b || args.any exprUses || exprUses d
    | .literal _ | .local _ | .nativeValue | .nearPromiseResultsCount => false
  effectUses : Effect → Bool
    | .storageScalarWrite _ v | .storageScalarAssignOp _ _ v
    | .storageStructFieldWrite _ _ v | .storageDynamicArrayPush _ v => exprUses v
    | .storageMapContains _ k | .storageMapGet _ k | .storageMapDelete _ k | .storageArrayRead _ k => exprUses k
    | .storageMapInsert _ k v | .storageMapSet _ k v | .storageArrayWrite _ k v
    | .storageArrayStructFieldWrite _ k _ v => exprUses k || exprUses v
    | .memoryArraySet a i v => exprUses a || exprUses i || exprUses v
    | .storagePathRead _ path => path.any pathUses
    | .storagePathWrite _ path v | .storagePathAssignOp _ path _ v =>
        path.any pathUses || exprUses v
    | .eventEmit _ fs => fs.any (fun f => exprUses f.snd)
    | .eventEmitIndexed _ ix data =>
        ix.any (fun f => exprUses f.snd) || data.any (fun f => exprUses f.snd)
    | .checkErc721Received a b c d =>
        exprUses a || exprUses b || exprUses c || exprUses d
    | .checkErc1155Received a b c d e =>
        exprUses a || exprUses b || exprUses c || exprUses d || exprUses e
    | .checkErc1155BatchReceived a b c d e =>
        exprUses a || exprUses b || exprUses c || exprUses d || exprUses e
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

/-- HostEnv materialize for every `contextRead` in the module. -/
def requireHostEnvHonesty (targetId : String) (module : Module) : Except String Unit :=
  (collectContextFields module).foldlM
    (fun _ field =>
      match materializeEnv targetId field.toHostEnv with
      | .ok _ => .ok ()
      | .error msg =>
          .error
            s!"PortableHonesty HostEnv: contextRead `{field.name}` on target `{targetId}`: {msg}")
    ()

/-- Identity materialize for caller/self context reads. -/
def requireIdentityHonesty (targetId : String) (module : Module) : Except String Unit :=
  (collectContextFields module).foldlM
    (fun _ field =>
      match field with
      | .userId | .userIdHash =>
          match materializeIdentity targetId .caller with
          | .ok _ => .ok ()
          | .error msg =>
              .error s!"PortableHonesty Identity: caller via `{field.name}` on `{targetId}`: {msg}"
      | .contractId =>
          match materializeIdentity targetId .self with
          | .ok _ => .ok ()
          | .error msg =>
              .error s!"PortableHonesty Identity: self via contractId on `{targetId}`: {msg}"
      | _ => .ok ())
    ()

/-- Declared logical peer for Solana account inference (`declareRemote` / string pool).
Empty or missing → inference cannot run; resolve must reject (no silent placeholder). -/
def declaredPeerId? (module : Module) : Option String :=
  match module.nearCrosscallStrings[0]? with
  | some s => if s.isEmpty then none else some s
  | none => none

/-- Sync-subset: portable sync remotes cannot mix NEAR async host-extension nodes.
Host-extension-only modules (promise_then without portable crosscallInvoke) are
allowed on wasm-near only (family portability still applies elsewhere).

Solana: requires a **non-empty declared peer** in `nearCrosscallStrings` so
`inferSolanaAccounts` runs (empty peer fails closed — no `portable.peer` invent). -/
def requireSyncCrosscallHonesty (targetId : String) (module : Module) : Except String Unit := do
  if moduleUsesPortableSyncCrosscall module then
    requireSyncSubset module
    if targetId == "solana-sbpf-asm" then
      match declaredPeerId? module with
      | none =>
          .error
            "PortableHonesty Crosscall: Solana portable remote requires a non-empty peer id \
from `remote peerId \"logical.peer\" \"method\"` / declareRemote (nearCrosscallStrings / PeerMap). \
empty peer cannot be inferred — fail-closed (no portable.peer invent)"
      | some peer =>
          match materializeSyncRemote targetId module peer with
          | .ok m =>
              match m.inferredAccounts? with
              | some accs =>
                  if accs.isEmpty then
                    .error
                      "PortableHonesty Crosscall: Solana inferred account set is empty \
(authors must not pass metas; inference failed)"
                  else .ok ()
              | none =>
                  .error "PortableHonesty Crosscall: Solana remote missing inferred accounts"
          | .error msg => .error s!"PortableHonesty Crosscall: {msg}"
    else if targetId == "evm" || targetId == "wasm-near" then
      -- Peer string optional on EVM/NEAR for sync materialize (no account metas).
      let peer := (declaredPeerId? module).getD "portable.peer"
      match materializeSyncRemote targetId module peer with
      | .ok _ => .ok ()
      | .error msg => .error s!"PortableHonesty Crosscall: {msg}"
    else
      .ok ()
  else if moduleUsesNearAsyncExtension module && targetId != "wasm-near" then
    .error
      s!"PortableHonesty Crosscall: target `{targetId}` rejects NEAR promise_then/result \
host extensions (portable sync-subset / wrong family)"
  else
    .ok ()

/-- PortableMechanics honesty for IR-used crypto / error / serde shapes. -/
def requireMechanicsHonesty (targetId : String) (module : Module) : Except String Unit := do
  let caps := module.capabilities
  -- crypto.hash → at least one of keccak/sha256 must materialize on triad
  if caps.any (fun c => c == .cryptoHash) then
    let keccakOk :=
      match materializeMechanic targetId .cryptoKeccak with
      | .ok _ => true
      | .error _ => false
    let shaOk :=
      match materializeMechanic targetId .cryptoSha256 with
      | .ok _ => true
      | .error _ => false
    if !(keccakOk || shaOk) then
      .error
        s!"PortableHonesty Mechanics: target `{targetId}` cannot materialize crypto.hash \
(keccak/sha256 both reject)"
  -- ecrecover / sig path
  if caps.any (fun c => c == .cryptoEcrecover) then
    match materializeMechanic targetId .cryptoEcrecover with
    | .ok _ => pure ()
    | .error msg => .error s!"PortableHonesty Mechanics: {msg}"
  -- Always require portable error surface materialize on triad when assertions used
  if caps.any (fun c => c == .assertions) then
    match materializeMechanic targetId .errorCode with
    | .ok _ => pure ()
    | .error msg => .error s!"PortableHonesty Mechanics: {msg}"
  pure ()

/-- Upgrade intent materialize (UUPS-only on EVM, etc.). -/
def requireUpgradeHonesty (targetId : String) (policy? : Option UpgradePolicy)
    (proxy? : Option ProxyPattern) : Except String Unit :=
  match policy? with
  | none => .ok ()
  | some policy =>
      match materializeUpgrade targetId policy proxy? with
      | .ok _ => .ok ()
      | .error msg => .error s!"PortableHonesty Upgrade: {msg}"

/-- Primary product triad for full HostEnv / Identity / sync honesty. -/
def isPrimaryTriad (targetId : String) : Bool :=
  targetId == "evm" || targetId == "solana-sbpf-asm" || targetId == "wasm-near"

/-- Full portable honesty for a module + optional upgrade policy on one target.

HostEnv / Identity / sync-subset tables are triad-complete; non-triad hosts
(CosmWasm, Soroban, Move, …) still get upgrade honesty when declared, but
skip HostEnv rows until those targets fill materializeEnv.
-/
def requirePortableHonesty (targetId : String) (module : Module)
    (upgradePolicy? : Option UpgradePolicy := none)
    (proxyPattern? : Option ProxyPattern := none) : Except String Unit := do
  if isPrimaryTriad targetId then
    requireHostEnvHonesty targetId module
    requireIdentityHonesty targetId module
    requireSyncCrosscallHonesty targetId module
    requireMechanicsHonesty targetId module
  requireUpgradeHonesty targetId upgradePolicy? proxyPattern?

end ProofForge.Target.PortableHonesty
