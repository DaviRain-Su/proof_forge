/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Full EmitSBPF Counter on the solanalib host driver

Runs the **complete** lowered Counter program (account scan, owner checks,
discriminator dispatch, entrypoint bodies) through the syscall-aware host
step driver — not just the core-tail.

## Bridging conventions (vs pure solanalib)

| Concern | ProofForge `SbpfInterpreter` | This host |
|---------|------------------------------|-----------|
| `r10` | `stackBase = 1_000_000` | same |
| Unmapped load | reads as `0` | zero-default `ldx` |
| Stack mem off | AST positive distance; address `r10 - off` | BpfEncode emits negative i16; solanalib `base+off` |
| Syscalls | name-based | imm hash stubs (`HostBridge.stepSyscall`) |
| Account input | word-sparse `initialMemory` | expanded LE words + zero-default |

Portable IR remains the source: we lower `IR.Examples.Counter.module` with
`SbpfAsm.lowerModule`, encode, then execute.
-/

import ProofForge.Backend.Refinement.Core
import ProofForge.Backend.Solana.BpfEncode
import ProofForge.Backend.Solana.CounterSbpfExec
import ProofForge.Backend.Solana.LabeledSbpf
import ProofForge.Backend.Solana.SbpfAsm
import ProofForge.Backend.Solana.SbpfInterpreter
import ProofForge.Backend.Solana.StateLayout
import ProofForge.Backend.Solana.Refinement
import ProofForge.IR.Examples.Counter
import ProofForge.Contract.Examples.ValueVaultInvariant
import ProofForgeFormal.Solana.HostBridge
import ProofForgeFormal.Solana.LabeledToSolanalib
import ProofForgeFormal.Solana.SolanalibAdapter
import Solanalib.SBPF.CommType
import Solanalib.SBPF.Syntax
import Solanalib.SBPF.Memory
import Solanalib.SBPF.State
import Solanalib.SBPF.Interpreter
import Solanalib.SBPF.Decoder
import Solanalib.SBPF.Verifier

namespace ProofForge.Backend.Solana.FullProgramHost

open ProofForge.IR
open ProofForge.Backend.Refinement
open ProofForge.Backend.Solana.BpfEncode
open ProofForge.Backend.Solana.CounterSbpfExec
open ProofForge.Backend.Solana.LabeledSbpf
open ProofForge.Backend.Solana.SbpfInterpreter
open ProofForge.Backend.Solana.StateLayout
open ProofForge.Backend.Solana.HostBridge
open ProofForge.Backend.Solana.LabeledToSolanalib
open ProofForge.Backend.Solana.SolanalibAdapter
open Solanalib.SBPF

/-- Encoded full Counter program + label → slot map. -/
structure FullProgram where
  bin : BpfBin
  labels : Array (String × Nat)
  slots : Array ResolvedInst

def labelSlot? (p : FullProgram) (name : String) : Option Nat :=
  match p.labels.find? (fun b => b.fst == name) with
  | some b => some b.snd
  | none => none

def lowerFullModule (module : Module) : Except String FullProgram :=
  match fromModule module with
  | .error e => .error e
  | .ok lp =>
      if !labeledProgramOk lp then
        .error "full program: labeled view ill-formed"
      else
        match liftSlots lp.slots with
        | .error e => .error e
        | .ok insns =>
            if !verifyAll insns .v1 then
              .error "full program: verifyInstr failed"
            else
              .ok {
                bin := toBpfBin lp.bytes
                labels := lp.labels
                slots := lp.slots
              }

/-- Initial host state for a full-program entrypoint: PF `initialMemory` +
`r1 = inputBase`, `r10 = stackBase`, PC at `entrypoint` label. -/
def initFullHost (p : FullProgram) (module : Module) (baseMemory : Memory)
    (call : TraceCall) (fuel : Nat := defaultFuel) : Except String HostState := do
  let entrySlot ←
    match labelSlot? p "entrypoint" with
    | some s => pure s
    | none => .error "full program missing `entrypoint` label"
  let memory ← initialMemory module baseMemory call
  let m := memOfPfMemory memory
  let rs0 := setReg initRegMap .br1 (BitVec.ofNat 64 inputBase)
  let rs1 := setReg rs0 .br10 (BitVec.ofNat 64 stackBase)
  let bpf : BpfState :=
    .ok (BitVec.ofNat 64 entrySlot) rs1 m initStackState .v1 initFuncMap 0
      (BitVec.ofNat 64 fuel)
  pure { bpf, returnData := none, lastMem := m }

/-- Zero-default load: unmapped bytes read as 0 (ProofForge sparse memory). -/
def loadvZero (chk : MemoryChunk) (m : Mem) (addr : U64) : Val :=
  match loadv chk m addr with
  | some v => v
  | none =>
      match chk with
      | .m8 => .vbyte 0
      | .m16 => .vshort 0
      | .m32 => .vint 0
      | .m64 => .vlong 0

def regFromVal (dst : BpfIReg) (rs : RegMap) : Val → RegMap
  | .vlong v => setReg rs dst v
  | .vint v => setReg rs dst (v.setWidth 64)
  | .vshort v => setReg rs dst (v.setWidth 64)
  | .vbyte v => setReg rs dst (v.setWidth 64)
  | .vundef => setReg rs dst 0

/-- Full-program host step: zero-default loads + syscall stubs + solanalib ALU. -/
def stepFull (bin : BpfBin) (hs : HostState) : HostState :=
  match hs.bpf with
  | .eflag | .err | .success _ => hs
  | .ok pc rs m ss sv fm curCu remainCu =>
      if insnSize * pc.toNat ≥ bin.length then
        { hs with bpf := .eflag }
      else if curCu.toNat ≥ remainCu.toNat then
        { hs with bpf := .eflag }
      else
        match findInstr pc.toNat bin with
        | none => { hs with bpf := .eflag }
        | some (.callImm src imm) =>
            match stepSyscall imm pc rs m ss sv fm curCu remainCu hs.returnData with
            | some (bpf', rd) =>
                let last :=
                  match bpf' with
                  | .ok _ _ m' _ _ _ _ _ => m'
                  | _ => m
                { bpf := bpf', returnData := rd, lastMem := last }
            | none =>
                let bpf' := step pc (.callImm src imm) rs m ss sv fm false 0 curCu remainCu
                { hs with bpf := bpf', lastMem := m }
        | some (.ldx chk dst src off) =>
            let addr := rs src + off.signExtend 64
            let rs' := regFromVal dst rs (loadvZero chk m addr)
            let bpf' := advanceOk pc rs' m ss sv fm curCu remainCu
            { hs with bpf := bpf', lastMem := m }
        | some .exit =>
            if ss.callDepth = 0 then
              { bpf := .success (rs .br0), returnData := hs.returnData, lastMem := m }
            else
              let bpf' := step pc .exit rs m ss sv fm false 0 curCu remainCu
              { hs with bpf := bpf', lastMem := m }
        | some ins =>
            let bpf' := step pc ins rs m ss sv fm false 0 curCu remainCu
            match bpf' with
            | .ok _ _ m' _ _ _ _ _ =>
                { hs with bpf := bpf', lastMem := m' }
            | .success v =>
                { bpf := .success v, returnData := hs.returnData, lastMem := m }
            | other =>
                { hs with bpf := other, lastMem := m }

def runToHaltFull (bin : BpfBin) (hs : HostState) (fuel : Nat := defaultFuel) : HostState :=
  go fuel hs
where
  go : Nat → HostState → HostState
    | 0, hs => hs
    | n + 1, hs =>
        match hs.bpf with
        | .ok .. => go n (stepFull bin hs)
        | _ => hs

/-- Project host memory back to a ProofForge word-sparse `Memory` for chaining.

Copies every scalar state-field offset from the module layout (and any
pre-existing base words). Counter only needs `count`; ValueVault needs the
full multi-field state. -/
def memoryAfter (module : Module) (base : Memory) (hs : HostState) : Memory :=
  let schema := ProofForge.Backend.Solana.SbpfAsm.buildModuleInputSchema module {}
  match schema.inputLayout.accounts[0]? with
  | none => base
  | some accountLayout =>
      let fields := buildStateOffsetsAtBase module accountLayout.dataStart
      fields.foldl (init := base) fun mem field =>
        match loadWordLE? hs.lastMem field.absOff with
        | some w => mem.write field.absOff w
        | none => mem

/-- Run one full entrypoint; on success return updated sparse memory + host. -/
def runFullEntrypoint (p : FullProgram) (module : Module) (baseMemory : Memory)
    (call : TraceCall) : Except String (Memory × HostState) := do
  let hs0 ← initFullHost p module baseMemory call
  let hs := runToHaltFull p.bin hs0
  match hs.bpf with
  | .success v =>
      if v.toNat != 0 then
        .error s!"full entrypoint `{call.entrypoint.name}` r0={v.toNat}"
      else
        .ok (memoryAfter module baseMemory hs, hs)
  | _ => .error s!"full entrypoint `{call.entrypoint.name}` did not succeed"

def observeHost (entrypoint : Entrypoint) (hs : HostState) :
    Except String ObservableReturn :=
  match entrypoint.returns with
  | .unit => .ok .none
  | .u64 =>
      match hs.returnData with
      | some value => .ok (.u64 value)
      | none => .error s!"full entrypoint `{entrypoint.name}` produced no return data"
  | other =>
      .error s!"full host only models Unit/U64 returns, got `{other.name}`"

def runFullTraceList (p : FullProgram) (module : Module) :
    List TraceCall → Memory → Except String (Memory × Array ObservableStep)
  | [], memory => .ok (memory, #[])
  | call :: rest, memory => do
      let (memory, hs) ← runFullEntrypoint p module memory call
      let ret ← observeHost call.entrypoint hs
      let step : ObservableStep := {
        entrypointName := call.entrypoint.name
        returnValue := ret
      }
      let (memory, steps) ← runFullTraceList p module rest memory
      .ok (memory, #[step] ++ steps)

/-- Counter scenario: initialize → get → increment → get. -/
def counterFullTraceOk : Bool :=
  match lowerFullModule ProofForge.IR.Examples.Counter.module with
  | .error _ => false
  | .ok p =>
      let calls : List TraceCall := [
        { entrypoint := ProofForge.IR.Examples.Counter.initializeEntrypoint },
        { entrypoint := ProofForge.IR.Examples.Counter.get },
        { entrypoint := ProofForge.IR.Examples.Counter.increment },
        { entrypoint := ProofForge.IR.Examples.Counter.get }
      ]
      match runFullTraceList p ProofForge.IR.Examples.Counter.module calls #[] with
      | .error _ => false
      | .ok (_, steps) =>
          steps == #[
            { entrypointName := "initialize", returnValue := .none },
            { entrypointName := "get", returnValue := .u64 0 },
            { entrypointName := "increment", returnValue := .none },
            { entrypointName := "get", returnValue := .u64 1 }
          ]

/-- Differential: full-program host matches PF interpreter on the same
Counter scenario (both produce the canonical observable array). -/
def counterFullDiffOk : Bool :=
  counterFullTraceOk &&
    (match ProofForge.Backend.Solana.SbpfAsm.lowerModule
        ProofForge.IR.Examples.Counter.module with
     | .error _ => false
     | .ok nodes =>
         let obligation : TraceObligation := {
           name := "counter-full-host-diff"
           module := ProofForge.IR.Examples.Counter.module
           calls := #[
             { entrypoint := ProofForge.IR.Examples.Counter.initializeEntrypoint },
             { entrypoint := ProofForge.IR.Examples.Counter.get },
             { entrypoint := ProofForge.IR.Examples.Counter.increment },
             { entrypoint := ProofForge.IR.Examples.Counter.get }
           ]
           expected := #[
             { entrypointName := "initialize", returnValue := .none },
             { entrypointName := "get", returnValue := .u64 0 },
             { entrypointName := "increment", returnValue := .none },
             { entrypointName := "get", returnValue := .u64 1 }
           ]
         }
         match ProofForge.Backend.Solana.SbpfInterpreter.runTrace nodes obligation with
         | .ok actual => actual == obligation.expected
         | .error _ => false)

theorem counter_full_program_host_ok :
    counterFullTraceOk = true := by
  native_decide

theorem counter_full_program_diff_ok :
    counterFullDiffOk = true := by
  native_decide

/-! ### ValueVault default scenario on full host -/

def valueVaultFullTraceOk : Bool :=
  match lowerFullModule ProofForge.Contract.Examples.ValueVaultInvariant.module with
  | .error _ => false
  | .ok p =>
      match runFullTraceList p ProofForge.Contract.Examples.ValueVaultInvariant.module
          ProofForge.Backend.Solana.Refinement.valueVaultTraceCalls.toList #[] with
      | .error _ => false
      | .ok (_, steps) =>
          steps == ProofForge.Backend.Solana.Refinement.valueVaultExpectedTrace

/-- Differential: host matches PF interpreter on the ValueVault default scenario. -/
def valueVaultFullDiffOk : Bool :=
  valueVaultFullTraceOk &&
    (match ProofForge.Backend.Solana.SbpfAsm.lowerModule
        ProofForge.Contract.Examples.ValueVaultInvariant.module with
     | .error _ => false
     | .ok nodes =>
         let obligation : TraceObligation :=
           ProofForge.Backend.Solana.Refinement.valueVaultTraceObligation
         match ProofForge.Backend.Solana.SbpfInterpreter.runTrace nodes obligation with
         | .ok actual => actual == obligation.expected
         | .error _ => false)

theorem value_vault_full_program_host_ok :
    valueVaultFullTraceOk = true := by
  native_decide

theorem value_vault_full_program_diff_ok :
    valueVaultFullDiffOk = true := by
  native_decide

end ProofForge.Backend.Solana.FullProgramHost
