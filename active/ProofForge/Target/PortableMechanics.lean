/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Mechanical portable catalog batch (gap-analysis route steps 6–7)

Pure materialize-or-reject tables for mechanical gaps that ride the existing
HostRuntime + honesty machine:

* crypto hash / sig-verify
* portable error surface
* serialization schema vocabulary

FV discipline: every term either materializes on a target or honest-rejects
with a diagnostic naming `PortableMechanics`, the target, and the term id.
-/
import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.Target.HostRuntime

namespace ProofForge.Target.PortableMechanics

open ProofForge.Target.HostRuntime

/-- Mechanical portable terms beyond HostEnv. -/
inductive MechanicTerm where
  | cryptoKeccak
  | cryptoSha256
  | cryptoEcrecover
  | cryptoEd25519Verify
  | errorCode
  | errorMessage
  | serdeAbi
  | serdeBorsh
  | serdeJson
  deriving BEq, DecidableEq, Repr

def MechanicTerm.id : MechanicTerm → String
  | .cryptoKeccak => "mech.crypto.keccak"
  | .cryptoSha256 => "mech.crypto.sha256"
  | .cryptoEcrecover => "mech.crypto.ecrecover"
  | .cryptoEd25519Verify => "mech.crypto.ed25519_verify"
  | .errorCode => "mech.error.code"
  | .errorMessage => "mech.error.message"
  | .serdeAbi => "mech.serde.abi"
  | .serdeBorsh => "mech.serde.borsh"
  | .serdeJson => "mech.serde.json"

def allMechanicTerms : Array MechanicTerm := #[
  .cryptoKeccak, .cryptoSha256, .cryptoEcrecover, .cryptoEd25519Verify,
  .errorCode, .errorMessage, .serdeAbi, .serdeBorsh, .serdeJson
]

structure MechanicMaterialization where
  targetId : String
  term : MechanicTerm
  binding : NativeBinding
  note? : Option String := none
  deriving Repr, BEq

def mechanicReject (targetId : String) (term : MechanicTerm) (reason : String) : String :=
  s!"PortableMechanics: target `{targetId}` cannot materialize `{term.id}`: {reason}"

/-- Materialize mechanical terms for the primary triad. -/
def materializeMechanic (targetId : String) (term : MechanicTerm) :
    Except String MechanicMaterialization :=
  let mk (kind : NativeKind) (symbol : String) (note? : Option String := none) :
      MechanicMaterialization :=
    { targetId := targetId
      term := term
      binding := { targetId := targetId, kind := kind, symbol := symbol, note? := note? }
      note? := note? }
  match term, targetId with
  -- crypto hash
  | .cryptoKeccak, "evm" =>
      .ok (mk .opcode "keccak256")
  | .cryptoKeccak, "solana-sbpf-asm" =>
      .ok (mk .syscall "sol_keccak256")
  | .cryptoKeccak, "wasm-near" =>
      .ok (mk .hostImport "env.keccak256" (some "when capability crypto.hash enabled"))
  | .cryptoSha256, "evm" =>
      .ok (mk .opcode "sha256_precompile" (some "precompile 0x02"))
  | .cryptoSha256, "solana-sbpf-asm" =>
      .ok (mk .syscall "sol_sha256")
  | .cryptoSha256, "wasm-near" =>
      .ok (mk .hostImport "env.sha256")
  -- sig verify
  | .cryptoEcrecover, "evm" =>
      .ok (mk .opcode "ecrecover" (some "precompile 0x01"))
  | .cryptoEcrecover, "solana-sbpf-asm" =>
      .error (mechanicReject targetId term
        "secp256k1 ecrecover not a portable Solana path; use ed25519_verify or reject")
  | .cryptoEcrecover, "wasm-near" =>
      .error (mechanicReject targetId term
        "ecrecover is EVM-only; NEAR uses ed25519 / host crypto differently")
  | .cryptoEd25519Verify, "solana-sbpf-asm" =>
      .ok (mk .syscall "sol_ed25519_verify" (some "via ed25519 program / syscalls when enabled"))
  | .cryptoEd25519Verify, "wasm-near" =>
      .ok (mk .hostImport "env.ed25519_verify" (some "when host enables"))
  | .cryptoEd25519Verify, "evm" =>
      .error (mechanicReject targetId term
        "ed25519 verify not a native EVM precompile in portable path; use ecrecover")
  -- errors
  | .errorCode, "evm" =>
      .ok (mk .opcode "revert" (some "Error(string) / custom errors"))
  | .errorCode, "solana-sbpf-asm" =>
      .ok (mk .syscall "sol_panic_" (some "program error codes"))
  | .errorCode, "wasm-near" =>
      .ok (mk .hostImport "env.panic" (some "or panic_utf8"))
  | .errorMessage, "evm" =>
      .ok (mk .opcode "revert" (some "reason string ABI"))
  | .errorMessage, "solana-sbpf-asm" =>
      .ok (mk .syscall "sol_log_" (some "logs; panic has limited message"))
  | .errorMessage, "wasm-near" =>
      .ok (mk .hostImport "env.panic_utf8")
  -- serialization
  | .serdeAbi, "evm" =>
      .ok (mk .opcode "abi.encode" (some "Evm.AbiEncode"))
  | .serdeAbi, "solana-sbpf-asm" =>
      .error (mechanicReject targetId term "ABI is EVM; use borsh on Solana")
  | .serdeAbi, "wasm-near" =>
      .error (mechanicReject targetId term "ABI is EVM; use json on NEAR")
  | .serdeBorsh, "solana-sbpf-asm" =>
      .ok (mk .syscall "borsh" (some "instruction data / account layouts"))
  | .serdeBorsh, "evm" =>
      .error (mechanicReject targetId term "borsh is Solana/Rust; use abi on EVM")
  | .serdeBorsh, "wasm-near" =>
      .ok (mk .hostImport "borsh" (some "NEAR often Borsh for args; also JSON"))
  | .serdeJson, "wasm-near" =>
      .ok (mk .hostImport "json" (some "WasmHost.JsonEncode for promises/events"))
  | .serdeJson, "evm" =>
      .error (mechanicReject targetId term "JSON not native EVM contract surface; use abi")
  | .serdeJson, "solana-sbpf-asm" =>
      .error (mechanicReject targetId term "JSON not native sBPF surface; use borsh")
  | _, _ =>
      .error (mechanicReject targetId term s!"no PortableMechanics row for `{targetId}`")

def supportsMechanic (targetId : String) (term : MechanicTerm) : Bool :=
  match materializeMechanic targetId term with
  | .ok _ => true
  | .error _ => false

def primaryTargetIds : Array String := #["evm", "solana-sbpf-asm", "wasm-near"]

end ProofForge.Target.PortableMechanics
