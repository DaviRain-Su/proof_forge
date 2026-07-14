import ProofForge.Frontend.Surface

open ProofForge.Frontend.Surface

namespace ProofForge.Contract.Stdlib.Surface.Policies

private def u64 (value : Nat) : SurfaceExpr :=
  .literal (.u64Lit value)

private def zeroAddress : SurfaceExpr :=
  .literal (.addressLit "0x0000000000000000000000000000000000000000")

private def sender : SurfaceExpr :=
  .contextRead .sender

/-- Portable ownership policy expressed directly in Surface v2. -/
def ownable : SurfaceContract := {
  name := "Ownable"
  structs := #[]
  state := #[
    { name := "owner", kind := .scalar .address },
    { name := "initialized", kind := .scalar .bool }
  ]
  events := #[{
    name := "OwnershipTransferred"
    fields := #[
      { name := "previousOwner", type := .address, indexed := true },
      { name := "newOwner", type := .address, indexed := true }
    ]
  }]
  errors := #[]
  entrypoints := #[
    { name := "init", kind := .function, mutability := .call,
      selector? := some "e1c7392a", params := #[], retType := .unit,
      body := #[
        .assert (.compare .eq (.stateRead "initialized") (.literal (.boolLit false)))
          "already initialized",
        .stateWrite "initialized" (.literal (.boolLit true)),
        .emit "OwnershipTransferred" #[zeroAddress, sender],
        .stateWrite "owner" sender] },
    { name := "owner", kind := .function, mutability := .view,
      selector? := some "8da5cb5b", params := #[], retType := .address,
      body := #[.returnExpr (.stateRead "owner")] },
    { name := "transferOwnership", kind := .function, mutability := .call,
      selector? := some "f2fde38b",
      params := #[{ name := "newOwner", type := .address }], retType := .unit,
      body := #[
        .assert (.compare .eq (.stateRead "owner") sender) "caller is not owner",
        .assert (.compare .ne (.local "newOwner") zeroAddress) "zero address",
        .emit "OwnershipTransferred" #[.stateRead "owner", .local "newOwner"],
        .stateWrite "owner" (.local "newOwner")] },
    { name := "renounceOwnership", kind := .function, mutability := .call,
      selector? := some "715018a6", params := #[], retType := .unit,
      body := #[
        .assert (.compare .eq (.stateRead "owner") sender) "caller is not owner",
        .emit "OwnershipTransferred" #[.stateRead "owner", zeroAddress],
        .stateWrite "owner" zeroAddress] }
  ]
  constructorParams := #[]
  constructorBindings := #[]
}

/-- Portable emergency-stop state machine expressed directly in Surface v2. -/
def pausable : SurfaceContract := {
  name := "Pausable"
  structs := #[]
  state := #[{ name := "paused", kind := .scalar .u64 }]
  events := #[]
  errors := #[]
  entrypoints := #[
    { name := "paused", kind := .function, mutability := .view,
      selector? := some "5c975abb", params := #[], retType := .u64,
      body := #[.returnExpr (.stateRead "paused")] },
    { name := "pause", kind := .function, mutability := .call,
      selector? := some "8456cb59", params := #[], retType := .unit,
      body := #[
        .assert (.compare .eq (.stateRead "paused") (u64 0)) "already paused",
        .stateWrite "paused" (u64 1)] },
    { name := "unpause", kind := .function, mutability := .call,
      selector? := some "3f4ba83a", params := #[], retType := .unit,
      body := #[
        .assert (.compare .ne (.stateRead "paused") (u64 0)) "not paused",
        .stateWrite "paused" (u64 0)] }
  ]
  constructorParams := #[]
  constructorBindings := #[]
}

/-- Portable critical-section lock expressed directly in Surface v2. -/
def reentrancyGuard : SurfaceContract := {
  name := "ReentrancyGuard"
  structs := #[]
  state := #[{ name := "lock", kind := .scalar .u64 }]
  events := #[]
  errors := #[]
  entrypoints := #[
    { name := "acquire", kind := .function, mutability := .call,
      selector? := some "a7134f73", params := #[], retType := .unit,
      body := #[
        .assert (.compare .eq (.stateRead "lock") (u64 0)) "reentrant call",
        .stateWrite "lock" (u64 1)] },
    { name := "release", kind := .function, mutability := .call,
      selector? := some "86d1a69f", params := #[], retType := .unit,
      body := #[
        .assert (.compare .ne (.stateRead "lock") (u64 0)) "lock not held",
        .stateWrite "lock" (u64 0)] },
    { name := "locked", kind := .function, mutability := .view,
      selector? := some "cf309012", params := #[], retType := .u64,
      body := #[.returnExpr (.stateRead "lock")] }
  ]
  constructorParams := #[]
  constructorBindings := #[]
}

private def roleKey (role account : SurfaceExpr) : SurfaceExpr :=
  .hashPair (.hash role) (.hash account)

/-- Compact portable role membership policy expressed directly in Surface v2. -/
def accessControl : SurfaceContract := {
  name := "AccessControl"
  structs := #[]
  state := #[{ name := "roleMembers", kind := .map .hash .u64 (some 256) }]
  events := #[]
  errors := #[]
  entrypoints := #[
    { name := "init", kind := .function, mutability := .call,
      selector? := some "e1c7392a", params := #[], retType := .unit,
      body := #[.mapWrite "roleMembers" (roleKey (u64 0) sender) (u64 1)] },
    { name := "hasRole", kind := .function, mutability := .view,
      selector? := some "d1f856ee",
      params := #[{ name := "role", type := .u64 }, { name := "who", type := .address }],
      retType := .bool,
      body := #[.returnExpr (.compare .ne
        (.mapRead "roleMembers" (roleKey (.local "role") (.local "who"))) (u64 0))] },
    { name := "grantRole", kind := .function, mutability := .call,
      selector? := some "b428b0b0",
      params := #[{ name := "role", type := .u64 }, { name := "who", type := .address }],
      retType := .unit,
      body := #[
        .assert (.compare .ne (.mapRead "roleMembers" (roleKey (u64 0) sender)) (u64 0))
          "missing admin role",
        .mapWrite "roleMembers" (roleKey (.local "role") (.local "who")) (u64 1)] },
    { name := "revokeRole", kind := .function, mutability := .call,
      selector? := some "b7d2b162",
      params := #[{ name := "role", type := .u64 }, { name := "who", type := .address }],
      retType := .unit,
      body := #[
        .assert (.compare .ne (.mapRead "roleMembers" (roleKey (u64 0) sender)) (u64 0))
          "missing admin role",
        .mapWrite "roleMembers" (roleKey (.local "role") (.local "who")) (u64 0)] }
  ]
  constructorParams := #[]
  constructorBindings := #[]
}

private def zeroHash : SurfaceExpr :=
  .literal (.hashLit
    "0x0000000000000000000000000000000000000000000000000000000000000000")

/-- Hash-width ownership policy for hosts whose identities exceed one word. -/
def ownableHash : SurfaceContract := {
  name := "OwnableHash"
  structs := #[]
  state := #[{ name := "owner", kind := .scalar .hash }]
  events := #[]
  errors := #[]
  entrypoints := #[
    { name := "init", kind := .function, mutability := .call,
      selector? := some "e1c7392a", params := #[], retType := .unit,
      body := #[
        .assert (.compare .eq (.stateRead "owner") zeroHash) "already initialized",
        .stateWrite "owner" (.hash sender)] },
    { name := "owner", kind := .function, mutability := .view,
      selector? := some "8da5cb5b", params := #[], retType := .hash,
      body := #[.returnExpr (.stateRead "owner")] },
    { name := "renounceOwnership", kind := .function, mutability := .call,
      selector? := some "715018a6", params := #[], retType := .unit,
      body := #[
        .assert (.compare .eq (.stateRead "owner") (.hash sender)) "caller is not owner",
        .stateWrite "owner" zeroHash] }
  ]
  constructorParams := #[]
  constructorBindings := #[]
}

private def senderU64 : SurfaceExpr :=
  .cast .u64 sender

/-- Owner-gated emergency-stop composition expressed directly in Surface v2. -/
def ownablePausable : SurfaceContract := {
  name := "OwnablePausable"
  structs := #[]
  state := #[
    { name := "owner", kind := .scalar .u64 },
    { name := "paused", kind := .scalar .u64 }
  ]
  events := #[]
  errors := #[]
  entrypoints := #[
    { name := "init", kind := .function, mutability := .call,
      selector? := some "e1c7392a", params := #[], retType := .unit,
      body := #[
        .assert (.compare .eq (.stateRead "owner") (u64 0)) "already initialized",
        .stateWrite "owner" senderU64] },
    { name := "owner", kind := .function, mutability := .view,
      selector? := some "8da5cb5b", params := #[], retType := .u64,
      body := #[.returnExpr (.stateRead "owner")] },
    { name := "paused", kind := .function, mutability := .view,
      selector? := some "5c975abb", params := #[], retType := .u64,
      body := #[.returnExpr (.stateRead "paused")] },
    { name := "pause", kind := .function, mutability := .call,
      selector? := some "8456cb59", params := #[], retType := .unit,
      body := #[
        .assert (.compare .eq (.stateRead "owner") senderU64) "caller is not owner",
        .assert (.compare .eq (.stateRead "paused") (u64 0)) "already paused",
        .stateWrite "paused" (u64 1)] },
    { name := "unpause", kind := .function, mutability := .call,
      selector? := some "3f4ba83a", params := #[], retType := .unit,
      body := #[
        .assert (.compare .eq (.stateRead "owner") senderU64) "caller is not owner",
        .assert (.compare .ne (.stateRead "paused") (u64 0)) "not paused",
        .stateWrite "paused" (u64 0)] },
    { name := "renounceOwnership", kind := .function, mutability := .call,
      selector? := some "715018a6", params := #[], retType := .unit,
      body := #[
        .assert (.compare .eq (.stateRead "owner") senderU64) "caller is not owner",
        .stateWrite "owner" (u64 0)] }
  ]
  constructorParams := #[]
  constructorBindings := #[]
}

end ProofForge.Contract.Stdlib.Surface.Policies
