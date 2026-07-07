/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Canonical shared AccessControlProbe source for role-gated stdlib composition.

Compile the same module to target artifacts by changing `--target`:

  lake env proof-forge build --target evm --root . \
    -o build/shared-access-control-probe/AccessControlProbe.bin \
    --yul-output build/shared-access-control-probe/AccessControlProbe.yul \
    --artifact-output build/shared-access-control-probe/AccessControlProbe.proof-forge-artifact.json \
    Examples/Shared/AccessControlProbe.lean

  lake env proof-forge build --target solana-sbpf-asm --root . \
    -o build/shared-access-control-probe/AccessControlProbe.s \
    --artifact-output build/shared-access-control-probe/AccessControlProbe.solana-artifact.json \
    Examples/Shared/AccessControlProbe.lean

NEAR/Wasm currently keeps address-keyed map composition behind backend
capability validation; this file remains the single source for that future
target rather than growing a separate NEAR copy.
-/
import ProofForge.Contract.Source
import ProofForge.Contract.Stdlib.AccessControl

namespace Examples.Shared.AccessControlProbe

open ProofForge.Contract.Source
open ProofForge.Contract.Stdlib.AccessControl

contract_source AccessControlProbe do
  import ProofForge.Contract.Stdlib.AccessControl;

  state touches : .u64

  entry init do
    let admin : .address := caller;
    do pathWriteRole roleMembers (u64 defaultAdminRole) admin (u64 1);

  entry grantMinter (who : .address) do
    guard_role defaultAdminRole;
    do pathWriteRole roleMembers (u64 minterRole) who (u64 1);

  entry touch do
    guard_role minterRole;
    touches := touches +! (u64 1);

  query getTouches returns(.u64) do
    return touches;

end Examples.Shared.AccessControlProbe

namespace AccessControlProbe

def spec : ProofForge.Contract.ContractSpec :=
  Examples.Shared.AccessControlProbe.spec

def module : ProofForge.IR.Module :=
  spec.module

end AccessControlProbe
