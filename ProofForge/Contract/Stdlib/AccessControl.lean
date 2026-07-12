/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

AccessControl role mixin for `contract_source` composition.
Uses nested map storage `(role, account) → membership` and `guard_role` checks.

## Product boundary (T1.4)

Nested role maps are **portable** on EVM · Solana · NEAR · Soroban:
- EmitWat uses compound keys (`__pf_map_*_nested_*`) for `pathWriteRole` /
  `pathReadRole`.
- Soroban maps use host `_get`/`_put` (not NEAR `storage_*`).
- Account params here are `.address` (EVM ABI ergonomics); for pure u64
  handles see `Examples/Product/RoleGatedToken.lean`.
-/
import ProofForge.Contract.Source

namespace ProofForge.Contract.Stdlib.AccessControl

open ProofForge.Contract.Source

namespace Spec

def hasMembership (member : Nat) : Prop := member ≠ 0

theorem zero_not_member : ¬ hasMembership 0 := by simp [hasMembership]

end Spec

/-- Default admin role id (OpenZeppelin `DEFAULT_ADMIN_ROLE` is bytes32 zero). -/
def defaultAdminRole : ProofForge.IR.Expr :=
  ProofForge.Contract.Surface.hash4 0 0 0 0

/-- `keccak256("MINTER_ROLE")`, used by demos and smokes. -/
def minterRole : ProofForge.IR.Expr :=
  ProofForge.Contract.Surface.hash4
    11470088803231168072 16021661935289273552
    9334983156050275148 17217135584914003622

def roleMembers : MapRef :=
  { id := "roleMembers", keyType := .hash, valueType := .u64 }

def roleAdmins : MapRef :=
  { id := "roleAdmins", keyType := .hash, valueType := .hash }

def initialized : ScalarRef :=
  ProofForge.Contract.Surface.slot "accessControlInitialized" .u64

def roleMemberKey (role who : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  .hashTwoToOne role (.hashValue who (.literal (.u64 0)) (.literal (.u64 0)) (.literal (.u64 0)))

def hasRoleExpr (members : MapRef) (role who : ProofForge.IR.Expr) : ProofForge.IR.Expr :=
  ProofForge.Contract.Surface.ne
    (ProofForge.Contract.Surface.mapGet members (roleMemberKey role who)) (.literal (.u64 0))

def requireRoleMember (members : MapRef) (role who : ProofForge.IR.Expr) : EntryM Unit :=
  ProofForge.Contract.Surface.assertCondition (hasRoleExpr members role who) "missing role"

def writeRoleMember (members : MapRef) (role who value : ProofForge.IR.Expr) : EntryM Unit :=
  ProofForge.Contract.Surface.mapSet members (roleMemberKey role who) value

contract_mixin AccessControlMixin do
  use ProofForge.Contract.Surface.mapState roleMembers
  use ProofForge.Contract.Surface.mapState roleAdmins
  use ProofForge.Contract.Surface.scalar initialized

  event RoleAdminChanged
  event RoleGranted abi #[
    ("role", "bytes32"),
    ("account", "address"),
    ("sender", "address")
  ]
  event RoleRevoked abi #[
    ("role", "bytes32"),
    ("account", "address"),
    ("sender", "address")
  ]

  query hasRole (role : .bytes32, who : .address) returns(.bool) do
    return hasRoleExpr roleMembers (ProofForge.Contract.Surface.ref role)
      (ProofForge.Contract.Surface.ref who);

  query getRoleAdmin (role : .bytes32) returns(.hash) do
    return mapRead roleAdmins role;

  entry grantRole (role : .bytes32, who : .address) do
    let adminRole : .hash := mapRead roleAdmins role;
    do requireRoleMember roleMembers (ProofForge.Contract.Surface.ref adminRole) caller;
    do ProofForge.Contract.Surface.requireEq
      (ProofForge.Contract.Surface.mapGet roleMembers
        (roleMemberKey (ProofForge.Contract.Surface.ref role)
          (ProofForge.Contract.Surface.ref who))) (u64 0) "role already granted";
    do writeRoleMember roleMembers (ProofForge.Contract.Surface.ref role)
      (ProofForge.Contract.Surface.ref who) (u64 1);
    emit RoleGranted indexed #[
      fieldAsName "role" role,
      fieldAsName "account" (ProofForge.Contract.Surface.ref who),
      fieldAsName "sender" caller
    ] data #[];

  entry revokeRole (role : .bytes32, who : .address) do
    let adminRole : .hash := mapRead roleAdmins role;
    do requireRoleMember roleMembers (ProofForge.Contract.Surface.ref adminRole) caller;
    do requireRoleMember roleMembers (ProofForge.Contract.Surface.ref role)
      (ProofForge.Contract.Surface.ref who);
    do writeRoleMember roleMembers (ProofForge.Contract.Surface.ref role)
      (ProofForge.Contract.Surface.ref who) (u64 0);
    emit RoleRevoked indexed #[
      fieldAsName "role" role,
      fieldAsName "account" (ProofForge.Contract.Surface.ref who),
      fieldAsName "sender" caller
    ] data #[];

  entry renounceRole (role : .bytes32, callerConfirmation : .address) do
    do ProofForge.Contract.Surface.requireEq
      (ProofForge.Contract.Surface.ref callerConfirmation) caller "bad role confirmation";
    do requireRoleMember roleMembers (ProofForge.Contract.Surface.ref role) caller;
    do writeRoleMember roleMembers (ProofForge.Contract.Surface.ref role) caller (u64 0);
    emit RoleRevoked indexed #[
      fieldAsName "role" role,
      fieldAsName "account" caller,
      fieldAsName "sender" caller
    ] data #[];

  entry setRoleAdmin (role : .bytes32, newAdminRole : .bytes32) do
    let previousAdminRole : .hash := mapRead roleAdmins role;
    do requireRoleMember roleMembers (ProofForge.Contract.Surface.ref previousAdminRole) caller;
    do mapWrite roleAdmins role newAdminRole;
    emit RoleAdminChanged indexed #[
      fieldAsName "role" role,
      fieldAsName "previousAdminRole" previousAdminRole,
      fieldAsName "newAdminRole" newAdminRole
    ] data #[];

contract_source AccessControl do
  event RoleGranted
  use mixin
  entry init do
    do ProofForge.Contract.Surface.requireZero initialized "already initialized";
    initialized := u64 1;
    let admin : .address := caller;
    do writeRoleMember roleMembers defaultAdminRole
      (ProofForge.Contract.Surface.ref admin) (u64 1);
    emit RoleGranted indexed #[
      fieldAsName "role" defaultAdminRole,
      fieldAsName "account" caller,
      fieldAsName "sender" caller
    ] data #[];

end ProofForge.Contract.Stdlib.AccessControl
