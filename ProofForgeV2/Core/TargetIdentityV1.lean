namespace ProofForgeV2

/-!
# Target identity types (engineering D3/S4)

External opaque `TargetId` / `CodegenProfileId` / `NetworkProfileId` with exact SPEC
grammars, plus an internal `TargetKind` witness for residual alpha dispatch.

**External string → identity authority is only** `TargetId.parse?` /
`CodegenProfileId.parse?` / `NetworkProfileId.parse?`. Product selection binds
`TargetKind` solely via the frozen `TargetRegistryV1` membership/default/profile
seed (`ResolvedBuildSelectionV1.kind`); there is no public string→`TargetKind`
parser and no `TargetId → TargetKind` conversion surface.

`TargetKind` remains a public Lean type because residual alpha
`Materializer`/`CompileError` still index by kind. That is an
internal dispatch witness, not a second product input face.

There is **no** public `CodegenProfileId.ofString!` bang constructor. Shipped
profiles are fixed well-known constants; arbitrary grammar-valid profiles are
built only via `parse?` (CLI/tests).

The engineering `TargetRegistryV1` kernel owns product membership, but its formal
root codec/digest, SupportClaim, and reachable BuildIdentity mint remain pending.
`NetworkProfileId` is typed for completeness but must not participate in build
selection.
-/

/-- Internal dispatch witness for the closed ten-target set. Wire labels match the
historical alpha enum. Not an external identity authority: product code must not
parse user strings into `TargetKind`; kind is taken only from a validated
build-selection registration. -/
inductive TargetKind where
  | evm
  | solana
  | near
  | cosmwasm
  | soroban
  | icp
  | noir
  | openvm
  | aleo
  | psy
  deriving BEq, DecidableEq, Hashable, Inhabited, Repr

namespace TargetKind

def toString : TargetKind → String
  | .evm => "evm"
  | .solana => "solana"
  | .near => "near"
  | .cosmwasm => "cosmwasm"
  | .soroban => "soroban"
  | .icp => "icp"
  | .noir => "noir"
  | .openvm => "openvm"
  | .aleo => "aleo"
  | .psy => "psy"

instance : ToString TargetKind := ⟨toString⟩

end TargetKind

private def isAsciiLower (c : Char) : Bool :=
  c.val ≥ 97 && c.val ≤ 122

private def isAsciiDigit (c : Char) : Bool :=
  c.val ≥ 48 && c.val ≤ 57

private def isAsciiLowerOrDigit (c : Char) : Bool :=
  isAsciiLower c || isAsciiDigit c

/-- Exact TargetId grammar: 1..32 ASCII bytes `[a-z][a-z0-9-]{0,31}`.
Trailing and consecutive hyphens are accepted by this exact regex. -/
private def validTargetIdGrammar (s : String) : Bool :=
  let n := s.length
  if n == 0 || n > 32 then
    false
  else
    match s.toList with
    | [] => false
    | first :: rest =>
        isAsciiLower first &&
          rest.all (fun c => isAsciiLowerOrDigit c || c == '-')

/-- Exact SPEC-COMMON profile ID grammar: 1..127 bytes
`[a-z][a-z0-9]*(?:[-.][a-z0-9]+)*`. Rejects trailing/consecutive separators. -/
private def validProfileIdGrammar (s : String) : Bool :=
  let n := s.length
  if n == 0 || n > 127 then
    false
  else
    match s.toList with
    | [] => false
    | first :: rest =>
        if !isAsciiLower first then
          false
        else
          let rec go : List Char → Bool
            | [] => true
            | c :: cs =>
                if isAsciiLowerOrDigit c then
                  go cs
                else if c == '-' || c == '.' then
                  match cs with
                  | [] => false
                  | n :: ns =>
                      if isAsciiLowerOrDigit n then go ns else false
                else
                  false
          go rest

/-- Opaque external target identity. Sole product TargetId authority. -/
structure TargetId where
  private mk ::
  value : String
  deriving BEq, DecidableEq, Hashable, Repr

namespace TargetId

-- No `Inhabited TargetId`: there is no legitimate default identity (not `evm`).

def toString (id : TargetId) : String := id.value

instance : ToString TargetId := ⟨toString⟩

def parse? (s : String) : Option TargetId :=
  if validTargetIdGrammar s then some ⟨s⟩ else none

/-- Closed well-known TargetIds (grammar-valid fixed labels). -/
def evm : TargetId := ⟨"evm"⟩
def solana : TargetId := ⟨"solana"⟩
def near : TargetId := ⟨"near"⟩
def cosmwasm : TargetId := ⟨"cosmwasm"⟩
def soroban : TargetId := ⟨"soroban"⟩
def icp : TargetId := ⟨"icp"⟩
def noir : TargetId := ⟨"noir"⟩
def openvm : TargetId := ⟨"openvm"⟩
def aleo : TargetId := ⟨"aleo"⟩
def psy : TargetId := ⟨"psy"⟩

/-- Map internal `TargetKind` to its well-known `TargetId`.
Not a product string parser — closed kind constructors only; no panic, no
arbitrary-string path. Used by BuildSelection seed rows and residual
Materializer kind↔identity joins. -/
def ofKind : TargetKind → TargetId
  | .evm => evm
  | .solana => solana
  | .near => near
  | .cosmwasm => cosmwasm
  | .soroban => soroban
  | .icp => icp
  | .noir => noir
  | .openvm => openvm
  | .aleo => aleo
  | .psy => psy

end TargetId

/-- Opaque codegen profile identity (SPEC-COMMON profile grammar). -/
structure CodegenProfileId where
  private mk ::
  value : String
  deriving BEq, DecidableEq, Hashable, Repr

namespace CodegenProfileId

-- No `Inhabited CodegenProfileId`: no default profile sentinel.

def toString (id : CodegenProfileId) : String := id.value

instance : ToString CodegenProfileId := ⟨toString⟩

def parse? (s : String) : Option CodegenProfileId :=
  if validProfileIdGrammar s then some ⟨s⟩ else none

/-- Shipped Phase-1 default profiles (private-ctor constants; no public bang). -/
def evmYulSolc0834V1 : CodegenProfileId := ⟨"evm-yul-solc-0.8.34-v1"⟩
def solanaSbpfPlanV1 : CodegenProfileId := ⟨"solana-sbpf-plan-v1"⟩
def nearWasmRawU64V1 : CodegenProfileId := ⟨"near-wasm-raw-u64-v1"⟩
def noirSourceU64RelationsV1 : CodegenProfileId := ⟨"noir-source-u64-relations-v1"⟩
def aleoLeoU64V1 : CodegenProfileId := ⟨"aleo-leo-4.0.2-u64-v1"⟩
def psyDargoU64V1 : CodegenProfileId := ⟨"psy-dargo-u64-v1"⟩

end CodegenProfileId

/-- Opaque network profile identity (SPEC-COMMON profile grammar). Typed for
completeness; must not participate in build selection. -/
structure NetworkProfileId where
  private mk ::
  value : String
  deriving BEq, DecidableEq, Hashable, Repr

namespace NetworkProfileId

-- No `Inhabited NetworkProfileId`: no default network sentinel.

def toString (id : NetworkProfileId) : String := id.value

instance : ToString NetworkProfileId := ⟨toString⟩

def parse? (s : String) : Option NetworkProfileId :=
  if validProfileIdGrammar s then some ⟨s⟩ else none

end NetworkProfileId

end ProofForgeV2
