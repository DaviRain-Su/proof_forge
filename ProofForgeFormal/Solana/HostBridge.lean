/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Host bridge: ProofForge sBPF memory/regs ↔ solanalib machine state

Maps the mathlib-free `SbpfInterpreter` word-sparse `Memory` into solanalib's
byte-addressable `Mem`, and drives a **syscall-aware** step driver on Counter
core-tail programs (account prologue still omitted).

## Scope (honest)

| In scope | Out of scope (still on SbpfInterpreter / Mollusk) |
|----------|-----------------------------------------------------|
| `mov64` / `add64` / `ldxdw` / `stxdw` / `exit` | Full account-input layout / dispatch |
| Word at `countOff = 96` | PDA / CPI / full account model |
| `r1 = inputBase = 0` | Broad syscall surface |
| `sol_set_return_data` stub | `sol_log_64_` event payload fidelity |
| `sol_log_64_` / `sol_get_clock_sysvar` no-op stubs | Full EmitSBPF program end-to-end |
| Sequential init→get→inc→get core-tail | IR↔solanalib universal simulation |

Portable IR remains the multi-chain source. This bridge only deepens the
**Solana target** leg so CompileCorrect can eventually state:

```
IR.Semantics  ⇝  SbpfInterpreter  ⇝  solanalib.step (+ host stubs)
```

on the Counter core-tail fragment (including `get`'s return-data syscall).
-/

import ProofForge.Backend.Solana.Asm
import ProofForge.Backend.Solana.BpfEncode
import ProofForge.Backend.Solana.CounterSbpfExec
import ProofForge.Backend.Solana.SbpfInterpreter
import ProofForgeFormal.Solana.LabeledToSolanalib
import ProofForgeFormal.Solana.SolanalibAdapter
import Solanalib.SBPF.CommType
import Solanalib.SBPF.Syntax
import Solanalib.SBPF.Memory
import Solanalib.SBPF.State
import Solanalib.SBPF.Interpreter
import Solanalib.SBPF.Decoder
import Solanalib.SBPF.Verifier

namespace ProofForge.Backend.Solana.HostBridge

open ProofForge.Backend.Solana.Asm
open ProofForge.Backend.Solana.BpfEncode
open ProofForge.Backend.Solana.CounterSbpfExec
open ProofForge.Backend.Solana.SbpfInterpreter
open ProofForge.Backend.Solana.LabeledToSolanalib
open ProofForge.Backend.Solana.SolanalibAdapter
open Solanalib.SBPF

/-! ### Syscall ids (must match `BpfEncode.syscallId?`) -/

def solSetReturnDataId : Nat := 0xa226d3eb
def solLog64Id : Nat := 0x5c2a3178
def solGetClockSysvarId : Nat := 0xb7e96933

/-! ### Word-sparse Memory ↔ byte Mem -/

/-- Write one little-endian `u64` word into solanalib `Mem`. -/
def storeWordLE (m : Mem) (addr value : Nat) : Mem :=
  Id.run do
    let mut mem := m
    let mut x := value
    for i in [0:8] do
      let b : U8 := BitVec.ofNat 8 (x % 256)
      let a : U64 := BitVec.ofNat 64 (addr + i)
      mem := fun i' => if i' = a then some b else mem i'
      x := x / 256
    mem

/-- Read one little-endian `u64` word; missing any byte ⇒ `none`. -/
def loadWordLE? (m : Mem) (addr : Nat) : Option Nat :=
  Id.run do
    let mut acc : Nat := 0
    let mut shift : Nat := 1
    for i in [0:8] do
      let a : U64 := BitVec.ofNat 64 (addr + i)
      match m a with
      | none => return none
      | some b =>
          acc := acc + b.toNat * shift
          shift := shift * 256
    some acc

/-- Select the most specific sparse word covering a byte address.

Solana's serialized account header contains adjacent byte fields (duplicate,
signer, writable, executable) while the executable interpreter stores every
cell in the same `Nat`-valued sparse map. When a lower-address word overlaps a
more specific cell, the higher start address owns that byte. -/
def sparseByte? (memory : Memory) (addr : Nat) : Option Nat :=
  let covering := memory.foldl (init := none) fun best entry =>
    if entry.fst ≤ addr && addr < entry.fst + 8 then
      match best with
      | none => some entry
      | some current => if current.fst ≤ entry.fst then some entry else best
    else
      best
  covering.map fun entry =>
    (entry.snd / (256 ^ (addr - entry.fst))) % 256

/-- Convert ProofForge word-sparse memory into solanalib byte memory. -/
def memOfPfMemory (memory : Memory) : Mem := fun addr =>
  (sparseByte? memory addr.toNat).map fun byte => BitVec.ofNat 8 byte

/-! ### Host machine state (bpf + return-data + last memory) -/

/-- Extended machine: solanalib `BpfState` plus ProofForge-style return-data
and a memory snapshot that survives `.success` (so sequential entrypoints can
chain). -/
structure HostState where
  bpf : BpfState
  returnData : Option Nat := none
  lastMem : Mem := initMem

def HostState.ok? (hs : HostState) : Bool :=
  match hs.bpf with
  | .success _ | .ok .. => true
  | .eflag | .err => false

def HostState.r0? (hs : HostState) : Option Nat :=
  match hs.bpf with
  | .success v => some v.toNat
  | .ok _pc rs _m _ss _sv _fm _cur _remain => some (rs .br0).toNat
  | _ => none

def HostState.countWord? (hs : HostState) : Option Nat :=
  loadWordLE? hs.lastMem countOff

/-- Build a solanalib-backed host state for core-tail programs.

- PC = 0, `r1` = `inputBase` (0), `r10` via `initBpfState`
- Memory = word-sparse ProofForge memory expanded to bytes
- Version = v1 -/
def initHost (memory : Memory) (fuel : Nat := 256)
    (returnData : Option Nat := none) : HostState :=
  let rs1 := setReg initRegMap .br1 (BitVec.ofNat 64 inputBase)
  let m := memOfPfMemory memory
  let bpf := initBpfState rs1 m (BitVec.ofNat 64 fuel) .v1
  { bpf, returnData, lastMem := m }

/-- Advance PC by 1 and compute-unit counters (syscall stub convention). -/
def advanceOk (pc : U64) (rs : RegMap) (m : Mem) (ss : StackState)
    (sv : SBPFV) (fm : FuncMap) (curCu remainCu : U64) : BpfState :=
  .ok (pc + 1) rs m ss sv fm (curCu + 1) remainCu

/-- Model a covered Solana helper call without solanalib's call-frame jump.

Mirrors `SbpfInterpreter.stepInstCall` for the Counter core-tail fragment. -/
def stepSyscall
    (imm : U32) (pc : U64) (rs : RegMap) (m : Mem) (ss : StackState)
    (sv : SBPFV) (fm : FuncMap) (curCu remainCu : U64)
    (returnData : Option Nat) : Option (BpfState × Option Nat) :=
  let id := imm.toNat
  if id == solSetReturnDataId then
    let ptr := (rs .br1).toNat
    match loadWordLE? m ptr with
    | none => none
    | some value =>
        let rs' := setReg rs .br0 0
        some (advanceOk pc rs' m ss sv fm curCu remainCu, some value)
  else if id == solLog64Id then
    let rs' := setReg rs .br0 0
    some (advanceOk pc rs' m ss sv fm curCu remainCu, returnData)
  else if id == solGetClockSysvarId then
    let ptr := (rs .br1).toNat
    let m' := storeWordLE m ptr 0
    let rs' := setReg rs .br0 0
    some (advanceOk pc rs' m' ss sv fm curCu remainCu, returnData)
  else
    none

/-- Single host step: intercept known `callImm` syscalls; otherwise solanalib
`step`. On program `exit` at depth 0, freeze `lastMem` into the host state. -/
def stepHost (bin : BpfBin) (hs : HostState) : HostState :=
  match hs.bpf with
  | .eflag => hs
  | .err => hs
  | .success _ => hs
  | .ok pc rs m ss sv fm curCu remainCu =>
      if insnSize * pc.toNat ≥ bin.length then
        { hs with bpf := .eflag }
      else if curCu.toNat ≥ remainCu.toNat then
        { hs with bpf := .eflag }
      else
        match findInstr pc.toNat bin with
        | none => { hs with bpf := .eflag }
        | some (.callImm _src imm) =>
            match stepSyscall imm pc rs m ss sv fm curCu remainCu hs.returnData with
            | some (bpf', rd) =>
                let last :=
                  match bpf' with
                  | .ok _ _ m' _ _ _ _ _ => m'
                  | _ => m
                { bpf := bpf', returnData := rd, lastMem := last }
            | none =>
                -- Unknown helper: fall through to solanalib (typically eflag).
                let bpf' := step pc (.callImm _src imm) rs m ss sv fm false 0 curCu remainCu
                { hs with bpf := bpf', lastMem := m }
        | some .exit =>
            if ss.callDepth = 0 then
              -- Capture memory before solanalib drops it into `.success`.
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

def runStepsHost : Nat → BpfBin → HostState → HostState
  | 0, _, hs => hs
  | n + 1, bin, hs =>
      match hs.bpf with
      | .ok .. => runStepsHost n bin (stepHost bin hs)
      | _ => hs

def runToHaltHost (bin : BpfBin) (hs : HostState) (fuel : Nat := 256) : HostState :=
  go fuel hs
where
  go : Nat → HostState → HostState
    | 0, hs => hs
    | n + 1, hs =>
        match hs.bpf with
        | .ok .. => go n (stepHost bin hs)
        | _ => hs

/-! ### Encode a flat core-tail `SbpfProgram` to solanalib bytes -/

def encodeCoreProgram (program : SbpfProgram) : Except String BpfBin := do
  match resolveProgram program with
  | .error e => .error e.render
  | .ok (slots, bytes) =>
      if !bpfBinWellFormed bytes then
        .error "core-tail encode: ill-formed bytecode"
      else
        match liftSlots slots with
        | .error e => .error e
        | .ok insns =>
            if !verifyAll insns .v1 then
              .error "core-tail encode: verifyInstr failed"
            else
              .ok (toBpfBin bytes)

/-! ### Counter core-tail differentials -/

/-- initialize: empty memory → success r0=0, count=0. -/
def initializeSolanalibOk : Bool :=
  match encodeCoreProgram initializeProgram with
  | .error _ => false
  | .ok bin =>
      let hs := runToHaltHost bin (initHost #[]) 32
      match hs.bpf, hs.countWord? with
      | .success v, some c => v.toNat == 0 && c == 0
      | _, _ => false

/-- increment from count=n: success r0=0, count=n+1. -/
def incrementSolanalibOk (n : Nat) : Bool :=
  match encodeCoreProgram incrementProgram with
  | .error _ => false
  | .ok bin =>
      let hs := runToHaltHost bin (initHost #[(countOff, n)]) 32
      match hs.bpf, hs.countWord? with
      | .success v, some c => v.toNat == 0 && c == n + 1
      | _, _ => false

/-- get from count=n: success r0=0, returnData=n, count unchanged. -/
def getSolanalibOk (n : Nat) : Bool :=
  match encodeCoreProgram getProgram with
  | .error _ => false
  | .ok bin =>
      let hs := runToHaltHost bin (initHost #[(countOff, n)]) 32
      match hs.bpf, hs.returnData, hs.countWord? with
      | .success v, some rd, some c =>
          v.toNat == 0 && rd == n && c == n
      | _, _, _ => false

/-- Differential vs ProofForge core-tail finals. -/
def initializeDiffOk : Bool :=
  initializeSolanalibOk &&
    (initializeFinalState.entryR0 == 0) &&
    (initializeFinalState.memory.read countOff == 0)

def incrementDiffOk (n : Nat) : Bool :=
  incrementSolanalibOk n &&
    ((incrementFinalState n).entryR0 == 0) &&
    ((incrementFinalState n).memory.read countOff == n + 1)

def getDiffOk (n : Nat) : Bool :=
  getSolanalibOk n &&
    ((getFinalState n).entryR0 == 0) &&
    ((getFinalState n).returnData == some n) &&
    ((getFinalState n).memory.read countOff == n)

/-- Sequential core-tail trace: initialize → get → increment → get.

Memory and return-data chain across entrypoints via `HostState.lastMem` /
`returnData`. Mirrors the Counter IR scenario observables
`none, u64 0, none, u64 1` at the core-tail level. -/
def sequentialTraceOk : Bool :=
  match encodeCoreProgram initializeProgram,
        encodeCoreProgram getProgram,
        encodeCoreProgram incrementProgram with
  | .ok initBin, .ok getBin, .ok incBin =>
      let afterInit := runToHaltHost initBin (initHost #[]) 32
      let mem1 : Memory :=
        match afterInit.countWord? with
        | some c => #[(countOff, c)]
        | none => #[]
      let afterGet0 :=
        runToHaltHost getBin (initHost mem1 32 afterInit.returnData) 32
      let mem2 : Memory :=
        match afterGet0.countWord? with
        | some c => #[(countOff, c)]
        | none => #[]
      let afterInc :=
        runToHaltHost incBin (initHost mem2 32 afterGet0.returnData) 32
      let mem3 : Memory :=
        match afterInc.countWord? with
        | some c => #[(countOff, c)]
        | none => #[]
      let afterGet1 :=
        runToHaltHost getBin (initHost mem3 32 afterInc.returnData) 32
      match afterInit.bpf, afterGet0.returnData, afterInc.bpf, afterGet1.returnData,
            afterGet1.countWord? with
      | .success r0i, some g0, .success r0inc, some g1, some cFinal =>
          r0i.toNat == 0 && g0 == 0 && r0inc.toNat == 0 && g1 == 1 && cFinal == 1
      | _, _, _, _, _ => false
  | _, _, _ => false

def counterCoreTailBridgeOk : Bool :=
  initializeDiffOk &&
    incrementDiffOk 0 &&
    incrementDiffOk 1 &&
    incrementDiffOk 41 &&
    getDiffOk 0 &&
    getDiffOk 1 &&
    getDiffOk 41 &&
    sequentialTraceOk

theorem counter_core_tail_bridge_ok :
    counterCoreTailBridgeOk = true := by
  native_decide

theorem initialize_solanalib_ok :
    initializeSolanalibOk = true := by
  native_decide

theorem increment_solanalib_zero_ok :
    incrementSolanalibOk 0 = true := by
  native_decide

theorem get_solanalib_zero_ok :
    getSolanalibOk 0 = true := by
  native_decide

theorem get_solanalib_one_ok :
    getSolanalibOk 1 = true := by
  native_decide

theorem sequential_core_tail_trace_ok :
    sequentialTraceOk = true := by
  native_decide

end ProofForge.Backend.Solana.HostBridge
