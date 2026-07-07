/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

EVM stdlib fixture exercising AccessControl grant/revoke/hasRole and
`guard_role`.
-/
import ProofForge.Contract.Source
import ProofForge.Contract.Stdlib.AccessControl

namespace AccessControlProbe

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

end AccessControlProbe
