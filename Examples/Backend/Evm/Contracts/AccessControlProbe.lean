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
  event RoleGranted
  import ProofForge.Contract.Stdlib.AccessControl;

  state touches : .u64

  entry init do
    do ProofForge.Contract.Surface.requireZero initialized "already initialized";
    initialized := u64 1;
    let admin : .address := caller;
    do writeRoleMember roleMembers defaultAdminRole (ProofForge.Contract.Surface.ref admin) (u64 1);
    emit RoleGranted indexed #[
      fieldAsName "role" defaultAdminRole,
      fieldAsName "account" caller,
      fieldAsName "sender" caller
    ] data #[];

  entry grantMinter (who : .address) do
    do requireRoleMember roleMembers defaultAdminRole caller;
    do writeRoleMember roleMembers minterRole (ProofForge.Contract.Surface.ref who) (u64 1);

  entry touch do
    do requireRoleMember roleMembers minterRole caller;
    touches := touches +! (u64 1);

  query getTouches returns(.u64) do
    return touches;

end AccessControlProbe
