/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Portable StatusMessage aligned to the classic NEAR tutorial shape
(near-examples/rust-status-message): per-account status storage with set/get.

EmitWat does not yet lower dynamic UTF-8 strings into NEAR storage, so the
portable surface stores a **U64 status code** keyed by the caller identity
projection (same u64 sha256-prefix used elsewhere on NEAR). The near-sdk
reference uses AccountId → u64 for a fair dual-deploy compare.

  lake env proof-forge build --target wasm-near --root . \
    -o build/status-message Examples/Product/StatusMessage.lean

NEAR compare: `just near-compare-status-message` / `-live`
-/
import ProofForge.Contract.Source

namespace Examples.Product.StatusMessage

open ProofForge.Contract.Source

contract_source StatusMessage do
  state version : .u64
  mapping records from .u64 to .u64

  event StatusSet

  entry init do
    version := u64 1;

  entry set_status (status : .u64) do
    let who : .u64 := caller;
    do mapWrite records who status;
    emit StatusSet indexed #[fieldAsName "account" who] data #[fieldAsName "status" status];

  query get_status (who : .u64) returns(.u64) do
    return mapRead records who;

end Examples.Product.StatusMessage
