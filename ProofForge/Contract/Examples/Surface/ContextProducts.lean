import ProofForge.Frontend.Surface

open ProofForge.Frontend.Surface

namespace ProofForge.Contract.Examples.Surface.ContextProducts

private def u64 (value : Nat) : SurfaceExpr := .literal (.u64Lit value)

def hostEnvProbe : SurfaceContract := {
  name := "HostEnvProbe"
  structs := #[]
  state := #[
    { name := "lastTime", kind := .scalar .u64 },
    { name := "lastHeight", kind := .scalar .u64 },
    { name := "lastSelf", kind := .scalar .u64 },
    { name := "lastCaller", kind := .scalar .u64 }
  ]
  events := #[]
  errors := #[]
  entrypoints := #[
    { name := "initialize", kind := .function, mutability := .call,
      selector? := some "8129fc1c", params := #[], retType := .unit,
      body := #[
        .stateWrite "lastTime" (u64 0), .stateWrite "lastHeight" (u64 0),
        .stateWrite "lastSelf" (u64 0), .stateWrite "lastCaller" (u64 0)] },
    { name := "snapshot", kind := .function, mutability := .call,
      selector? := some "9711715a", params := #[], retType := .unit,
      body := #[
        .stateWrite "lastTime" (.contextRead .blockTimestamp),
        .stateWrite "lastHeight" (.contextRead .blockNumber),
        .stateWrite "lastSelf" (.cast .u64 (.contextRead .contractAddress)),
        .stateWrite "lastCaller" (.cast .u64 (.contextRead .sender))] },
    { name := "getTime", kind := .function, mutability := .view,
      selector? := some "557ed1ba", params := #[], retType := .u64,
      body := #[.returnExpr (.stateRead "lastTime")] },
    { name := "getHeight", kind := .function, mutability := .view,
      selector? := some "19efb11d", params := #[], retType := .u64,
      body := #[.returnExpr (.stateRead "lastHeight")] },
    { name := "getSelf", kind := .function, mutability := .view,
      selector? := some "e237f75b", params := #[], retType := .u64,
      body := #[.returnExpr (.stateRead "lastSelf")] },
    { name := "getCaller", kind := .function, mutability := .view,
      selector? := some "ab470f05", params := #[], retType := .u64,
      body := #[.returnExpr (.stateRead "lastCaller")] }
  ]
  constructorParams := #[]
  constructorBindings := #[]
}

private def binaryLock
    (contractName unlockState unlockParam unlockGetter unlockSelector : String)
    (clock : SurfaceContextField) : SurfaceContract := {
  name := contractName
  structs := #[]
  state := #[
    { name := "locked", kind := .scalar .u64 },
    { name := unlockState, kind := .scalar .u64 },
    { name := "claimBalance", kind := .scalar .u64 },
    { name := "claimed", kind := .scalar .u64 }
  ]
  events := #[
    { name := "Locked", fields := #[
      { name := "amount", type := .u64, indexed := false },
      { name := unlockParam, type := .u64, indexed := false }] },
    { name := "Claimed", fields := #[
      { name := "amount", type := .u64, indexed := false }] }
  ]
  errors := #[]
  entrypoints := #[
    { name := "init", kind := .function, mutability := .call,
      selector? := some "e1c7392a", params := #[], retType := .unit,
      body := #[
        .stateWrite "locked" (u64 0), .stateWrite unlockState (u64 0),
        .stateWrite "claimBalance" (u64 0), .stateWrite "claimed" (u64 0)] },
    { name := "lock", kind := .function, mutability := .call,
      selector? := some "8c25a303",
      params := #[{ name := "amount", type := .u64 }, { name := unlockParam, type := .u64 }],
      retType := .unit,
      body := #[
        .assert (.compare .eq (.stateRead "locked") (u64 0)) "already locked",
        .assert (.compare .eq (.stateRead "claimed") (u64 0)) "already claimed",
        .assert (.compare .ne (.local "amount") (u64 0)) "zero amount",
        .stateWrite "locked" (.local "amount"),
        .stateWrite unlockState (.local unlockParam),
        .emit "Locked" #[.local "amount", .local unlockParam]] },
    { name := "claim", kind := .function, mutability := .call,
      selector? := some "4e71d92d", params := #[], retType := .unit,
      body := #[
        .assert (.compare .eq (.stateRead "claimed") (u64 0)) "already claimed",
        .bind "amount" .u64 (.stateRead "locked"),
        .assert (.compare .ne (.local "amount") (u64 0)) "nothing locked",
        .assert (.compare .ge (.contextRead clock) (.stateRead unlockState)) "lock active",
        .stateWrite "claimed" (u64 1), .stateWrite "locked" (u64 0),
        .bind "balance" .u64 (.stateRead "claimBalance"),
        .stateWrite "claimBalance" (.arith .add true (.local "balance") (.local "amount")),
        .emit "Claimed" #[.local "amount"]] },
    { name := "get_locked", kind := .function, mutability := .view,
      selector? := some "b0093365", params := #[], retType := .u64,
      body := #[.returnExpr (.stateRead "locked")] },
    { name := unlockGetter, kind := .function, mutability := .view,
      selector? := some unlockSelector, params := #[], retType := .u64,
      body := #[.returnExpr (.stateRead unlockState)] },
    { name := "claim_balance", kind := .function, mutability := .view,
      selector? := some "8068092a", params := #[], retType := .u64,
      body := #[.returnExpr (.stateRead "claimBalance")] },
    { name := "is_claimed", kind := .function, mutability := .view,
      selector? := some "7c93f8c8", params := #[], retType := .u64,
      body := #[.returnExpr (.stateRead "claimed")] }
  ]
  constructorParams := #[]
  constructorBindings := #[]
}

def heightLockVault : SurfaceContract :=
  binaryLock "HeightLockVault" "unlockHeight" "unlockHeight"
    "get_unlock_height" "62fb93e3" .blockNumber

def timelockVault : SurfaceContract :=
  binaryLock "TimelockVault" "unlockAt" "unlockAt"
    "get_unlock_at" "85caba73" .blockTimestamp

end ProofForge.Contract.Examples.Surface.ContextProducts
