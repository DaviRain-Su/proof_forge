import ProofForge.Frontend.Surface

/-! internal Surface fixture ValueVault matching the product contract's public behavior. -/

open ProofForge.Frontend.Surface

namespace TestFixtures.SurfaceProducts.ValueVault

def contract : SurfaceContract := {
  name := "ValueVault"
  structs := #[]
  state := #[
    { name := "balance", kind := .scalar .u64 },
    { name := "released", kind := .scalar .u64 },
    { name := "fees", kind := .scalar .u64 },
    { name := "last_value", kind := .scalar .u64 },
    { name := "last_checkpoint", kind := .scalar .u64 },
    { name := "operations", kind := .scalar .u64 }
  ]
  events := #[
    { name := "VaultInitialized", fields := #[
      { name := "initial", type := .u64, indexed := false },
      { name := "checkpoint", type := .u64, indexed := false }] },
    { name := "ValueDeposited", fields := #[
      { name := "amount", type := .u64, indexed := false },
      { name := "balance", type := .u64, indexed := false },
      { name := "operations", type := .u64, indexed := false }] },
    { name := "ValueCharged", fields := #[
      { name := "gross", type := .u64, indexed := false },
      { name := "fee", type := .u64, indexed := false },
      { name := "net", type := .u64, indexed := false },
      { name := "balance", type := .u64, indexed := false }] },
    { name := "ValueReleased", fields := #[
      { name := "amount", type := .u64, indexed := false },
      { name := "balance", type := .u64, indexed := false },
      { name := "released", type := .u64, indexed := false }] },
    { name := "ValueSnapshot", fields := #[
      { name := "balance", type := .u64, indexed := false },
      { name := "released", type := .u64, indexed := false },
      { name := "fees", type := .u64, indexed := false },
      { name := "checkpoint", type := .u64, indexed := false }] }
  ]
  errors := #[]
  entrypoints := #[
    { name := "initialize", kind := .function, mutability := .call,
      selector? := some "8129fc1c",
      params := #[{ name := "initial", type := .u64 }], retType := .unit,
      body := #[
        .bind "checkpoint" .u64 (.contextRead .blockNumber),
        .stateWrite "balance" (.local "initial"),
        .stateWrite "released" (.literal (.u64Lit 0)),
        .stateWrite "fees" (.literal (.u64Lit 0)),
        .stateWrite "last_value" (.local "initial"),
        .stateWrite "last_checkpoint" (.local "checkpoint"),
        .stateWrite "operations" (.literal (.u64Lit 1)),
        .emit "VaultInitialized" #[.local "initial", .local "checkpoint"]] },
    { name := "deposit", kind := .function, mutability := .call,
      selector? := some "d09de08a",
      params := #[{ name := "amount", type := .u64 }], retType := .unit,
      body := #[
        .bind "current" .u64 (.stateRead "balance"),
        .bind "next" .u64 (.arith .add true (.local "current") (.local "amount")),
        .bind "ops" .u64 (.stateRead "operations"),
        .bind "next_ops" .u64 (.arith .add true (.local "ops") (.literal (.u64Lit 1))),
        .stateWrite "balance" (.local "next"),
        .stateWrite "last_value" (.local "amount"),
        .stateWrite "operations" (.local "next_ops"),
        .emit "ValueDeposited" #[.local "amount", .local "next", .local "next_ops"]] },
    { name := "charge_fee", kind := .function, mutability := .call,
      selector? := some "4ef4885b",
      params := #[
        { name := "gross", type := .u64 }, { name := "fee_bps", type := .u64 }], retType := .unit,
      body := #[
        .bind "fee" .u64 (.arith .div false
          (.arith .mul true (.local "gross") (.local "fee_bps")) (.literal (.u64Lit 10000))),
        .bind "net" .u64 (.arith .sub true (.local "gross") (.local "fee")),
        .bind "current" .u64 (.stateRead "balance"),
        .bind "next" .u64 (.arith .add true (.local "current") (.local "net")),
        .bind "current_fees" .u64 (.stateRead "fees"),
        .bind "next_fees" .u64 (.arith .add true (.local "current_fees") (.local "fee")),
        .bind "ops" .u64 (.stateRead "operations"),
        .bind "next_ops" .u64 (.arith .add true (.local "ops") (.literal (.u64Lit 1))),
        .stateWrite "balance" (.local "next"), .stateWrite "fees" (.local "next_fees"),
        .stateWrite "last_value" (.local "net"), .stateWrite "operations" (.local "next_ops"),
        .emit "ValueCharged" #[.local "gross", .local "fee", .local "net", .local "next"]] },
    { name := "release", kind := .function, mutability := .call,
      selector? := some "b214faa5",
      params := #[{ name := "amount", type := .u64 }], retType := .unit,
      body := #[
        .bind "current" .u64 (.stateRead "balance"),
        .bind "next" .u64 (.arith .sub true (.local "current") (.local "amount")),
        .bind "released_before" .u64 (.stateRead "released"),
        .bind "released_next" .u64 (.arith .add true (.local "released_before") (.local "amount")),
        .bind "ops" .u64 (.stateRead "operations"),
        .bind "next_ops" .u64 (.arith .add true (.local "ops") (.literal (.u64Lit 1))),
        .stateWrite "balance" (.local "next"), .stateWrite "released" (.local "released_next"),
        .stateWrite "last_value" (.local "amount"), .stateWrite "operations" (.local "next_ops"),
        .emit "ValueReleased" #[.local "amount", .local "next", .local "released_next"]] },
    { name := "snapshot", kind := .function, mutability := .call,
      selector? := some "0c2d8b55",
      params := #[], retType := .u64,
      body := #[
        .bind "checkpoint" .u64 (.contextRead .blockNumber),
        .bind "balance_now" .u64 (.stateRead "balance"),
        .bind "released_now" .u64 (.stateRead "released"),
        .bind "fees_now" .u64 (.stateRead "fees"),
        .stateWrite "last_checkpoint" (.local "checkpoint"),
        .emit "ValueSnapshot" #[.local "balance_now", .local "released_now", .local "fees_now", .local "checkpoint"],
        .returnExpr (.local "balance_now")] },
    { name := "get_balance", kind := .function, mutability := .view,
      selector? := some "f8a8fd6d",
      params := #[], retType := .u64,
      body := #[.returnExpr (.stateRead "balance")] },
    { name := "get_net_value", kind := .function, mutability := .view,
      selector? := some "1a381be1",
      params := #[], retType := .u64,
      body := #[.bind "balance_now" .u64 (.stateRead "balance"),
        .bind "fees_now" .u64 (.stateRead "fees"),
        .returnExpr (.arith .sub true (.local "balance_now") (.local "fees_now"))] }
  ]
  constructorParams := #[]
  constructorBindings := #[]
}

end TestFixtures.SurfaceProducts.ValueVault
