/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Lean model of Psy `DPNFunctionCircuitDefinition` (Counter-subset first).
Matches the normalized golden shape under `Examples/Backend/Psy/dpn/`.
-/

namespace ProofForge.Backend.Psy.Dpn

/-- One definition node in the DPN opcode DAG. -/
structure IndexedVarDef where
  dataType : Nat
  index : Nat
  opType : Nat
  inputs : Array Nat
  deriving Repr, BEq, Inhabited

/-- State command variants observed on Counter / Arithmetic / Assert goldens. -/
inductive StateCommand where
  | getSelfUserCurrentContractStateSlotSingle (subSlotIndex : Nat)
  | setContractStateSlotSingle (condition : Nat) (subSlotIndex : Nat) (value : Nat)
  | other (typeName : String) (rawFields : Array (String × Nat))
  deriving Repr, BEq, Inhabited

/-- One method circuit (`DPNFunctionCircuitDefinition`). -/
structure FunctionCircuit where
  name : String
  methodId : Nat
  circuitInputs : Array Nat
  circuitOutputs : Array Nat
  stateCommands : Array StateCommand
  stateCommandResolutionIndices : Array Nat
  assertions : Array (Array (String × Nat))
  definitions : Array IndexedVarDef
  events : Array (Array (String × Nat))
  deriving Repr, BEq, Inhabited

/-- Full dargo compile document: array of method circuits. -/
abbrev CircuitDocument := Array FunctionCircuit

namespace CounterGolden

/-- Hand-encoded Counter DPN circuit matching `Counter.golden.dpn.json`. -/
def document : CircuitDocument :=
  #[
    {
      name := "initialize"
      methodId := 2203611343
      circuitInputs := #[]
      circuitOutputs := #[]
      stateCommands := #[
        .getSelfUserCurrentContractStateSlotSingle 0,
        .setContractStateSlotSingle 4294967296 0 0
      ]
      stateCommandResolutionIndices := #[1, 2]
      assertions := #[]
      definitions := #[
        { dataType := 0, index := 0, opType := 1, inputs := #[0] },
        { dataType := 1, index := 0, opType := 2, inputs := #[1] }
      ]
      events := #[]
    },
    {
      name := "increment"
      methodId := 3203482200
      circuitInputs := #[]
      circuitOutputs := #[]
      stateCommands := #[
        .getSelfUserCurrentContractStateSlotSingle 0,
        .setContractStateSlotSingle 4294967296 0 3
      ]
      stateCommandResolutionIndices := #[1, 5]
      assertions := #[]
      definitions := #[
        { dataType := 0, index := 0, opType := 1, inputs := #[0] },
        { dataType := 1, index := 0, opType := 2, inputs := #[1] },
        { dataType := 0, index := 1, opType := 54, inputs := #[0] },
        { dataType := 0, index := 2, opType := 1, inputs := #[1] },
        { dataType := 0, index := 3, opType := 4, inputs := #[1, 2] }
      ]
      events := #[]
    },
    {
      name := "get"
      methodId := 1459926901
      circuitInputs := #[]
      circuitOutputs := #[1]
      stateCommands := #[.getSelfUserCurrentContractStateSlotSingle 0]
      stateCommandResolutionIndices := #[1]
      assertions := #[]
      definitions := #[
        { dataType := 0, index := 0, opType := 1, inputs := #[0] },
        { dataType := 0, index := 1, opType := 54, inputs := #[0] }
      ]
      events := #[]
    }
  ]

end CounterGolden

end ProofForge.Backend.Psy.Dpn
