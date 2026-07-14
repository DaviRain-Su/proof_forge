import ProofForge.Frontend.Surface

open ProofForge.Frontend.Surface

namespace Examples.Product.Canonical.VestingVault

private def u64 (value : Nat) : SurfaceExpr := .literal (.u64Lit value)

private def state (name : String) : SurfaceStateDecl :=
  { name, kind := .scalar .u64 }

private def computeVested : Array SurfaceStmt := #[
  .bind "now" .u64 (.contextRead .blockTimestamp),
  .bind "start" .u64 (.stateRead "startTime"),
  .bind "duration" .u64 (.stateRead "duration"),
  .bind "total" .u64 (.stateRead "totalAllocation"),
  .bind "elapsed" .u64 (.arith .sub true (.local "now") (.local "start")),
  .stateWrite "vestedScratch" (.local "total"),
  .branch (.compare .lt (.local "elapsed") (.local "duration")) #[
    .assert (.compare .ne (.local "duration") (u64 0)) "zero duration",
    .stateWrite "vestedScratch" (.arith .div true
      (.arith .mul true (.local "total") (.local "elapsed")) (.local "duration"))
  ] #[]
]

private def view (name selector stateName : String) : SurfaceEntrypoint := {
  name, kind := .function, mutability := .view, selector? := some selector,
  params := #[], retType := .u64, body := #[.returnExpr (.stateRead stateName)] }

def contract : SurfaceContract := {
  name := "VestingVault"
  structs := #[]
  state := #[state "beneficiary", state "totalAllocation", state "released",
    state "startTime", state "duration", state "claimBalance", state "vestedScratch"]
  events := #[{
    name := "Released"
    fields := #[
      { name := "beneficiary", type := .u64, indexed := true },
      { name := "amount", type := .u64, indexed := false }
    ]
  }]
  errors := #[]
  entrypoints := #[
    { name := "init", kind := .function, mutability := .call,
      selector? := some "1f663530",
      params := #[
        { name := "who", type := .u64 }, { name := "total", type := .u64 },
        { name := "start", type := .u64 }, { name := "duration", type := .u64 }],
      retType := .unit,
      body := #[
        .assert (.compare .ne (.local "total") (u64 0)) "zero total",
        .assert (.compare .ne (.local "duration") (u64 0)) "zero duration",
        .stateWrite "beneficiary" (.local "who"),
        .stateWrite "totalAllocation" (.local "total"),
        .stateWrite "released" (u64 0), .stateWrite "startTime" (.local "start"),
        .stateWrite "duration" (.local "duration"), .stateWrite "claimBalance" (u64 0),
        .stateWrite "vestedScratch" (u64 0)] },
    { name := "vested", kind := .function, mutability := .call,
      selector? := some "fea5657c", params := #[], retType := .u64,
      body := computeVested ++ #[.returnExpr (.stateRead "vestedScratch")] },
    { name := "releasable", kind := .function, mutability := .call,
      selector? := some "fbccedae", params := #[], retType := .u64,
      body := computeVested ++ #[
        .bind "vested" .u64 (.stateRead "vestedScratch"),
        .bind "released" .u64 (.stateRead "released"),
        .returnExpr (.arith .sub true (.local "vested") (.local "released"))] },
    view "claim_balance" "8068092a" "claimBalance",
    view "total_allocation" "79bbaefc" "totalAllocation",
    view "released_amount" "3ded1000" "released",
    { name := "release", kind := .function, mutability := .call,
      selector? := some "86d1a69f", params := #[], retType := .unit,
      body := computeVested ++ #[
        .bind "vested" .u64 (.stateRead "vestedScratch"),
        .bind "releasedBefore" .u64 (.stateRead "released"),
        .bind "amount" .u64 (.arith .sub true (.local "vested") (.local "releasedBefore")),
        .assert (.compare .ne (.local "amount") (u64 0)) "nothing releasable",
        .stateWrite "released" (.arith .add true (.local "releasedBefore") (.local "amount")),
        .bind "balance" .u64 (.stateRead "claimBalance"),
        .stateWrite "claimBalance" (.arith .add true (.local "balance") (.local "amount")),
        .emit "Released" #[.stateRead "beneficiary", .local "amount"]] }
  ]
  constructorParams := #[]
  constructorBindings := #[]
}

end Examples.Product.Canonical.VestingVault
