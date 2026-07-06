import ProofForge.Target

namespace ProofForge.Cli.Fixture

/-- Built-in fixture ids used by the target-first CLI surface. -/
def ids : Array String := #[
  "counter",
  "value-vault",
  "context",
  "hash",
  "map",
  "assert",
  "assignment",
  "conditional",
  "else-if",
  "arithmetic",
  "bitwise",
  "loop",
  "array",
  "struct",
  "crosscall",
  "event",
  "expression-predicate",
  "generic-entrypoint",
  "bool-storage-scalar",
  "bool-storage-array",
  "hash-storage",
  "nested-aggregate",
  "storage-nested-aggregate",
  "abi-aggregate",
  "abi-scalar",
  "evm-assign-op",
  "evm-event",
  "evm-crosscall",
  "evm-expression",
  "evm-hash",
  "evm-loop",
  "evm-map",
  "evm-storage-array",
  "evm-storage-struct",
  "evm-typed-map",
  "evm-typed-storage",
  "evm-array-value",
  "evm-struct-array-value",
  "evm-struct-value",
  "evm-abi-aggregate",
  "u32-arithmetic",
  "u32-hash-packing",
  "u32-storage-scalar",
  "u32-storage-array",
  "pure-math",
  "control",
  "error-ref",
  "canned-entrypoint",
  "solana-sdk",
  "solana-clock-sysvar",
  "solana-rent-sysvar",
  "solana-epoch-schedule-sysvar",
  "solana-epoch-rewards-sysvar",
  "solana-last-restart-slot-sysvar",
  "solana-memory",
  "solana-memo-cpi",
  "solana-crypto-hash",
  "solana-return-data-compute",
  "spl-token-transfer-cpi",
  "spl-token-ops-cpi",
  "spl-token-close-account-cpi",
  "spl-token-authority-cpi",
  "associated-token-cpi",
  "spl-token-2022-cpi",
  "spl-token-2022-pausable-cpi",
  "spl-token-2022-transfer-hook",
  "system-cpi",
  "system-create-account-cpi",
  "log-event"
]

def isValidId (id : String) : Bool :=
  ids.contains id

def listIds : String :=
  String.intercalate ", " ids.toList

/-- Intermediate artifact format requested by `proof-forge emit`. -/
inductive Format where
  | yul
  | bytecode
  | wat
  | s
  | psy
  | ts
  | leo
  | cosmwasm
  | aptos
  | sui
  | elf
  | qnt
  | scenario
  deriving BEq, Inhabited, Repr

def Format.id : Format → String
  | .yul => "yul"
  | .bytecode => "bytecode"
  | .wat => "wat"
  | .s => "s"
  | .psy => "psy"
  | .ts => "ts"
  | .leo => "leo"
  | .cosmwasm => "cosmwasm"
  | .aptos => "aptos"
  | .sui => "sui"
  | .elf => "elf"
  | .qnt => "qnt"
  | .scenario => "scenario"

def parseFormat? (s : String) : Option Format :=
  match s with
  | "yul" => some .yul
  | "bytecode" | "bin" => some .bytecode
  | "wat" => some .wat
  | "s" | "sbpf-asm" => some .s
  | "psy" => some .psy
  | "ts" => some .ts
  | "leo" => some .leo
  | "cosmwasm" => some .cosmwasm
  | "aptos" => some .aptos
  | "sui" | "move" => some .sui
  | "elf" | "so" => some .elf
  | "qnt" => some .qnt
  | "scenario" | "toml" => some .scenario
  | _ => none

/-- Target ids that participate in the new `build|emit|check` surface. This is
a subset of `ProofForge.Target.Registry` focused on implemented compiler
routes. -/
def supportedTargetIds : Array String := #[
  "evm",
  "solana-sbpf-asm",
  "wasm-near",
  "wasm-cosmwasm",
  "psy-dpn",
  "aleo-leo",
  "move-aptos",
  "move-sui",
  "quint"
]

/-- Default format for a (target, fixture) pair when `--format` is omitted. -/
def defaultFormatFor (targetId fixtureId : String) : Option Format :=
  match targetId with
  | "evm" =>
      if fixtureId == "counter" || fixtureId == "value-vault" then some .bytecode
      else some .yul
  | "solana-sbpf-asm" => some .s
  | "wasm-near" | "wasm-cosmwasm" => some .wat
  | "psy-dpn" => some .psy
  | "aleo-leo" => some .leo
  | "move-aptos" => some .aptos
  | "move-sui" => some .sui
  | "quint" => some .qnt
  | _ => none

/-- Conservative whitelist of supported (target, fixture, format) triples.
Unsupported triples fail early with a diagnostic. -/
def supportsFormat (targetId fixtureId : String) (format : Format) : Bool :=
  match targetId, fixtureId, format with
  | "evm", "counter", _ => true
  | "evm", "value-vault", _ => true
  | "evm", "error-ref", _ => true
  | "evm", "context", _ => true
  | "evm", "hash", _ => true
  | "evm", "map", _ => true
  | "evm", "assert", _ => true
  | "evm", "assignment", _ => true
  | "evm", "conditional", _ => true
  | "evm", f, _ => f.startsWith "evm-" || f == "abi-scalar"
  | "solana-sbpf-asm", "counter", _ => true
  | "solana-sbpf-asm", "value-vault", _ => true
  | "solana-sbpf-asm", "error-ref", _ => true
  | "solana-sbpf-asm", "control", _ => true
  | "solana-sbpf-asm", f, _ =>
      f.startsWith "solana-" || f.startsWith "spl-token-" || f.startsWith "system-" ||
      f == "associated-token-cpi" || f == "log-event" || f == "canned-entrypoint"
  | "wasm-near", "counter", _ => true
  | "wasm-near", "error-ref", _ => true
  | "wasm-near", "context", _ => true
  | "wasm-near", "hash", _ => true
  | "wasm-near", "map", _ => true
  | "wasm-cosmwasm", "counter", .wat => true
  | "psy-dpn", f, .psy =>
      f == "counter" || f == "crosscall" || f == "event" || f == "expression-predicate" ||
      f == "generic-entrypoint" || f.startsWith "arithmetic" || f.startsWith "bitwise" ||
      f.startsWith "bool-" || f.startsWith "conditional" || f == "else-if" || f.startsWith "context" ||
      f.startsWith "hash" || f.startsWith "loop" || f.startsWith "map" ||
      f == "assert" || f.startsWith "array" || f.startsWith "struct" ||
      f.startsWith "abi-" || f.startsWith "nested-" || f.startsWith "storage-nested" ||
      f.startsWith "u32-"
  | "aleo-leo", "counter", .leo => true
  | "aleo-leo", "pure-math", .leo => true
  | "move-aptos", "counter", .aptos => true
  | "move-sui", "counter", .sui => true
  | "quint", "counter", .qnt => true
  | "quint", "value-vault", .qnt => true
  | _, _, _ => false

/-- Conservative capability demand for a fixture. Used by `proof-forge check` to
produce a clear diagnostic when a target profile lacks a required capability. -/
def capabilitiesFor (id : String) : Array ProofForge.Target.Capability :=
  match id with
  | "counter" => #[.storageScalar, .callerSender, .envBlock, .controlConditional, .controlBoundedLoop]
  | "value-vault" => #[.storageScalar, .storageMap, .callerSender, .envBlock, .controlConditional]
  | "error-ref" => #[.storageScalar, .assertions]
  | "context" => #[.callerSender, .envBlock, .valueNative]
  | "hash" | "hash-storage" | "u32-hash-packing" => #[.cryptoHash]
  | "map" => #[.storageMap]
  | "assert" => #[.assertions]
  | "assignment" | "evm-assign-op" => #[.storageScalar]
  | "conditional" | "else-if" => #[.controlConditional]
  | "loop" | "evm-loop" => #[.controlBoundedLoop]
  | "array" | "evm-array-value" | "u32-storage-array" | "evm-storage-array" => #[.dataFixedArray]
  | "struct" | "evm-struct-value" | "evm-storage-struct" | "evm-struct-array-value" => #[.dataStruct]
  | "crosscall" | "evm-crosscall" => #[.crosscallInvoke]
  | "event" | "evm-event" => #[.eventsEmit]
  | "bool-storage-scalar" | "bool-storage-array" | "u32-storage-scalar" => #[.storageScalar]
  | "nested-aggregate" | "storage-nested-aggregate" => #[.dataFixedArray, .dataStruct]
  | "control" => #[.controlConditional, .controlBoundedLoop]
  | f =>
      if f.startsWith "solana-" || f.startsWith "spl-token-" || f.startsWith "system-" ||
         f == "associated-token-cpi" || f == "log-event" then
        #[.crosscallCpi, .storagePda, .runtimeMemory, .runtimeComputeUnits, .runtimeReturnData]
      else
        #[]

end ProofForge.Cli.Fixture
