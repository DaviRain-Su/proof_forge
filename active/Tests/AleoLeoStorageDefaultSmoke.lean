import ProofForge.Backend.Aleo.IR
import ProofForge.IR.Contract

/-! Regression tests for honest Leo `Mapping::get_or_use` defaults. -/

namespace ProofForge.Tests.AleoLeoStorageDefaultSmoke

open ProofForge.IR
open ProofForge.Backend.Aleo.IR

def readScalarAddress : Entrypoint :=
  { name := "read_scalar_address"
    body := #[
      .letBind "stored" .address (.effect (.storageScalarRead "recipient"))
    ] }

def scalarAddressReadModule : Module :=
  { name := "ScalarAddressRead"
    state := #[{ id := "recipient", kind := .scalar, type := .address }]
    entrypoints := #[readScalarAddress] }

def readMapAddress : Entrypoint :=
  { name := "read_map_address"
    body := #[
      .letBind "stored" .address
        (.effect (.storageMapGet "recipients" (.literal (.u64 0))))
    ] }

def mapAddressReadModule : Module :=
  { name := "MapAddressRead"
    state := #[{ id := "recipients", kind := .map .u64 8, type := .address }]
    entrypoints := #[readMapAddress] }

def contactValue : StructDecl :=
  { name := "Contact"
    fields := #[{ id := "account", type := .address }] }

def envelopeValue : StructDecl :=
  { name := "Envelope"
    fields := #[
      { id := "contact", type := .structType "Contact" },
      { id := "nonce", type := .u64 }
    ] }

def readNestedAddress : Entrypoint :=
  { name := "read_nested_address"
    body := #[
      .letBind "stored" (.structType "Envelope")
        (.effect (.storageScalarRead "envelope"))
    ] }

def nestedAddressReadModule : Module :=
  { name := "NestedAddressRead"
    structs := #[contactValue, envelopeValue]
    state := #[{ id := "envelope", kind := .scalar, type := .structType "Envelope" }]
    entrypoints := #[readNestedAddress] }

def readNestedNumericPath : Entrypoint :=
  { name := "read_nested_numeric_path"
    body := #[
      .letBind "nonce" .u64
        (.effect (.storagePathRead "envelope" #[.field "nonce"]))
    ] }

def nestedAddressPathReadModule : Module :=
  { nestedAddressReadModule with
    name := "NestedAddressPathRead"
    entrypoints := #[readNestedNumericPath] }

def rejectsAddressDefault (module : Module) (pathMarker : String) : Bool :=
  match renderModule module with
  | .error error =>
      error.message.contains "storage default" &&
      error.message.contains "address" &&
      error.message.contains pathMarker
  | .ok _ => false

/-- `none` is not an address in Leo 4.0.2. Direct scalar and map reads must
fail closed instead of inventing an account identity. -/
def directAddressDefaultsFailClosed : Bool :=
  rejectsAddressDefault scalarAddressReadModule "Mapping::get_or_use" &&
  rejectsAddressDefault mapAddressReadModule "Mapping::get_or_use"

theorem direct_address_defaults_fail_closed : directAddressDefaultsFailClosed = true := by
  native_decide

/-- Default construction is recursive, so an address nested in ordinary value
structs must report the complete field path. -/
def nestedAddressDefaultFailsClosed : Bool :=
  rejectsAddressDefault nestedAddressReadModule "Envelope.contact.account" &&
  rejectsAddressDefault nestedAddressPathReadModule "Envelope.contact.account"

theorem nested_address_default_fails_closed : nestedAddressDefaultFailsClosed = true := by
  native_decide

def writeScalarAddress : Entrypoint :=
  { name := "write_scalar_address"
    params := #[("recipient", .address)]
    body := #[
      .effect (.storageScalarWrite "stored" (.local "recipient"))
    ] }

def writeOnlyAddressModule : Module :=
  { name := "WriteOnlyAddress"
    state := #[{ id := "stored", kind := .scalar, type := .address }]
    entrypoints := #[writeScalarAddress] }

/-- Address storage itself remains valid when no fallback value is needed. -/
def writeOnlyAddressStillLowers : Bool :=
  match renderModule writeOnlyAddressModule with
  | .ok source =>
      source.contains "mapping stored: u64 => address;" &&
      source.contains "Mapping::set(stored, 0u64, recipient);" &&
      !source.contains "none"
  | .error _ => false

theorem write_only_address_still_lowers : writeOnlyAddressStillLowers = true := by
  native_decide

example : True := by
  have _ := @direct_address_defaults_fail_closed
  have _ := @nested_address_default_fails_closed
  have _ := @write_only_address_still_lowers
  exact True.intro

end ProofForge.Tests.AleoLeoStorageDefaultSmoke

def main : IO UInt32 := do
  IO.println "aleo-leo-storage-default-smoke: address defaults fail closed; write-only address remains valid"
  return 0
