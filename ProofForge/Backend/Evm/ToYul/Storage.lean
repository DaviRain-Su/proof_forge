import ProofForge.Backend.Evm.Plan
import ProofForge.Backend.Evm.ToYul.Common
import ProofForge.Backend.Evm.ToYul.Helpers
import ProofForge.Backend.Evm.ToYul.Effect
import ProofForge.Compiler.Yul.AST

/-! # EVM storage and effect-plan Yul emission

Storage, map, array, struct-field, storage-path, and memory-array effect
lowering helpers used by the plan-driven EVM Yul backend.
-/

namespace ProofForge.Backend.Evm.ToYul

open ProofForge.IR
open ProofForge.Backend.Evm.Plan

def scalarStorageWriteStatements
    (storageSlot valueExpr : Lean.Compiler.Yul.Expr)
    (byteOffset byteWidth : Nat) : Array Lean.Compiler.Yul.Statement :=
  if byteWidth >= 32 || byteOffset == 0 && byteWidth == 32 then
    #[
      .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[storageSlot, valueExpr])
    ]
  else
    let shiftBits := (32 - (byteOffset + byteWidth)) * 8
    let mask := (2^(byteWidth * 8 : Nat)) - 1
    let shiftedMask := Lean.Compiler.Yul.builtin "shl" #[
      Lean.Compiler.Yul.Expr.num shiftBits,
      Lean.Compiler.Yul.Expr.num mask
    ]
    #[
      .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
        storageSlot,
        Lean.Compiler.Yul.builtin "or" #[
          Lean.Compiler.Yul.builtin "and" #[
            Lean.Compiler.Yul.builtin "sload" #[storageSlot],
            Lean.Compiler.Yul.builtin "not" #[shiftedMask]
          ],
          Lean.Compiler.Yul.builtin "shl" #[
            Lean.Compiler.Yul.Expr.num shiftBits,
            valueExpr
          ]
        ]
      ])
    ]

def scalarStoragePackedReadExpr
    (storageSlot : Lean.Compiler.Yul.Expr)
    (byteOffset byteWidth : Nat) : Lean.Compiler.Yul.Expr :=
  if byteWidth >= 32 || byteOffset == 0 && byteWidth == 32 then
    Lean.Compiler.Yul.builtin "sload" #[storageSlot]
  else
    let shiftBits := (32 - (byteOffset + byteWidth)) * 8
    let mask := (2^(byteWidth * 8 : Nat)) - 1
    Lean.Compiler.Yul.builtin "and" #[
      Lean.Compiler.Yul.builtin "shr" #[
        Lean.Compiler.Yul.Expr.num shiftBits,
        Lean.Compiler.Yul.builtin "sload" #[storageSlot]
      ],
      Lean.Compiler.Yul.Expr.num mask
    ]

def scalarStorageTargetReadExpr
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (target : ScalarStorageTargetPlan) : Except ε Lean.Compiler.Yul.Expr := do
  .ok <| scalarStoragePackedReadExpr
    (← storageSlotExpr mkError lowerExpr target.slot)
    target.byteOffset
    target.byteWidth

def scalarStorageAssignOpStatements
    (overflowChecked : Bool)
    (op : AssignOp)
    (storageSlot valueExpr : Lean.Compiler.Yul.Expr)
    (byteOffset byteWidth : Nat) : Array Lean.Compiler.Yul.Statement :=
  let packedRead := scalarStoragePackedReadExpr storageSlot byteOffset byteWidth
  let computedValue := arithExpr overflowChecked op packedRead valueExpr
  scalarStorageWriteStatements storageSlot computedValue byteOffset byteWidth

def scalarStorageEffectPlanStatements
    {ε : Type}
    (overflowChecked : Bool)
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (storageSlotFor : String → Except ε Lean.Compiler.Yul.Expr)
    (packingFor : String → Except ε (Nat × Nat)) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .storageScalarWrite stateId value => do
      let storageSlot ← storageSlotFor stateId
      let valueExpr ← exprPlanExpr mkError lowerExpr lowerEffect value
      let (byteOffset, byteWidth) ← packingFor stateId
      .ok <| scalarStorageWriteStatements storageSlot valueExpr byteOffset byteWidth
  | .storageScalarAssignOp stateId op value => do
      let storageSlot ← storageSlotFor stateId
      let (byteOffset, byteWidth) ← packingFor stateId
      let rhs ← exprPlanExpr mkError lowerExpr lowerEffect value
      .ok <| scalarStorageAssignOpStatements overflowChecked op storageSlot rhs byteOffset byteWidth
  | _ =>
      .error (mkError "EVM EffectPlan-to-Yul scalar storage effect lowering expected storageScalarWrite/storageScalarAssignOp")

def scalarStorageEffectStmtPlanStatements
    {ε : Type}
    (overflowChecked : Bool)
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (storageSlotFor : String → Except ε Lean.Compiler.Yul.Expr)
    (packingFor : String → Except ε (Nat × Nat)) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect effect =>
      scalarStorageEffectPlanStatements overflowChecked mkError lowerExpr lowerEffect storageSlotFor packingFor effect
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul scalar storage effect lowering expected effect")

def scalarStorageTargetEffectPlanStatements
    {ε : Type}
    (overflowChecked : Bool)
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .storageScalarWriteTarget target value => do
      let targetSlot ← storageSlotExpr mkError lowerExpr target.slot
      let valueExpr ← exprPlanExpr mkError lowerExpr lowerEffect value
      .ok <| scalarStorageWriteStatements targetSlot valueExpr target.byteOffset target.byteWidth
  | .storageScalarAssignOpTarget target op value => do
      let targetSlot ← storageSlotExpr mkError lowerExpr target.slot
      let valueExpr ← exprPlanExpr mkError lowerExpr lowerEffect value
      .ok <| scalarStorageAssignOpStatements overflowChecked op targetSlot valueExpr target.byteOffset target.byteWidth
  | _ =>
      .error (mkError "EVM EffectPlan-to-Yul planned scalar storage lowering expected storageScalarWriteTarget/storageScalarAssignOpTarget")

def scalarStorageTargetEffectStmtPlanStatements
    {ε : Type}
    (overflowChecked : Bool)
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect effect =>
      scalarStorageTargetEffectPlanStatements overflowChecked mkError lowerExpr lowerEffect effect
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul planned scalar storage lowering expected effect")

def mapWriteEffectPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (mapRootSlotFor : String → Except ε Lean.Compiler.Yul.Expr) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .storageMapInsert stateId key value
  | .storageMapSet stateId key value => do
      .ok #[
        .exprStmt (helperCall Helper.mapWrite #[
          ← mapRootSlotFor stateId,
          ← exprPlanExpr mkError lowerExpr lowerEffect key,
          ← exprPlanExpr mkError lowerExpr lowerEffect value
        ])
      ]
  | _ =>
      .error (mkError "EVM EffectPlan-to-Yul map write lowering expected storageMapInsert/storageMapSet")

def mapWriteEffectStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (mapRootSlotFor : String → Except ε Lean.Compiler.Yul.Expr) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect effect =>
      mapWriteEffectPlanStatements mkError lowerExpr lowerEffect mapRootSlotFor effect
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul map write lowering expected effect")

def mapSetReturnTargetExpr
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (target : MapWriteTargetPlan)
    (key value : ExprPlan) : Except ε Lean.Compiler.Yul.Expr := do
  .ok (helperCall Helper.mapSetReturn #[
    slotExpr target.rootSlot,
    ← exprPlanExpr mkError lowerExpr lowerEffect key,
    ← exprPlanExpr mkError lowerExpr lowerEffect value
  ])

def mapContainsExpr
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (rootSlot : Nat)
    (key : ExprPlan) : Except ε Lean.Compiler.Yul.Expr := do
  let presenceSlot := helperCall Helper.mapPresenceSlot #[
    slotExpr rootSlot,
    ← exprPlanExpr mkError lowerExpr lowerEffect key
  ]
  .ok (Lean.Compiler.Yul.builtin "iszero" #[
    Lean.Compiler.Yul.builtin "iszero" #[
      Lean.Compiler.Yul.builtin "sload" #[presenceSlot]
    ]
  ])

def mapContainsTargetExpr
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (target : MapReadTargetPlan)
    (key : ExprPlan) : Except ε Lean.Compiler.Yul.Expr :=
  mapContainsExpr mkError lowerExpr lowerEffect target.rootSlot key

def mapGetExpr
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (rootSlot : Nat)
    (key : ExprPlan) : Except ε Lean.Compiler.Yul.Expr := do
  let valueSlot := helperCall Helper.mapSlot #[
    slotExpr rootSlot,
    ← exprPlanExpr mkError lowerExpr lowerEffect key
  ]
  .ok (Lean.Compiler.Yul.builtin "sload" #[valueSlot])

def mapGetTargetExpr
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (target : MapReadTargetPlan)
    (key : ExprPlan) : Except ε Lean.Compiler.Yul.Expr :=
  mapGetExpr mkError lowerExpr lowerEffect target.rootSlot key

def mapWriteTargetEffectPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .storageMapInsertTarget target key value
  | .storageMapSetTarget target key value => do
      .ok #[
        .exprStmt (helperCall Helper.mapWrite #[
          slotExpr target.rootSlot,
          ← exprPlanExpr mkError lowerExpr lowerEffect key,
          ← exprPlanExpr mkError lowerExpr lowerEffect value
        ])
      ]
  | _ =>
      .error (mkError "EVM EffectPlan-to-Yul planned map write lowering expected storageMapInsertTarget/storageMapSetTarget")

def mapWriteTargetEffectStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect effect =>
      mapWriteTargetEffectPlanStatements mkError lowerExpr lowerEffect effect
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul planned map write lowering expected effect")

def arrayWriteEffectPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (arraySlotFor : String → ExprPlan → Except ε Lean.Compiler.Yul.Expr) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .storageArrayWrite stateId index value => do
      .ok #[
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
          ← arraySlotFor stateId index,
          ← exprPlanExpr mkError lowerExpr lowerEffect value
        ])
      ]
  | _ =>
      .error (mkError "EVM EffectPlan-to-Yul array write lowering expected storageArrayWrite")

def arrayWriteEffectStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (arraySlotFor : String → ExprPlan → Except ε Lean.Compiler.Yul.Expr) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect effect =>
      arrayWriteEffectPlanStatements mkError lowerExpr lowerEffect arraySlotFor effect
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul array write lowering expected effect")

def arrayReadExpr
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (rootSlot length : Nat)
    (index : ExprPlan) : Except ε Lean.Compiler.Yul.Expr := do
  let elementSlot := helperCall Helper.arraySlot #[
    slotExpr rootSlot,
    Lean.Compiler.Yul.Expr.num length,
    ← exprPlanExpr mkError lowerExpr lowerEffect index
  ]
  .ok (Lean.Compiler.Yul.builtin "sload" #[elementSlot])

def arrayReadTargetExpr
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (target : ArrayReadTargetPlan)
    (index : ExprPlan) : Except ε Lean.Compiler.Yul.Expr :=
  arrayReadExpr mkError lowerExpr lowerEffect target.rootSlot target.length index

def arrayWriteTargetEffectPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .storageArrayWriteTarget target index value => do
      .ok #[
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
          helperCall Helper.arraySlot #[
            slotExpr target.rootSlot,
            Lean.Compiler.Yul.Expr.num target.length,
            ← exprPlanExpr mkError lowerExpr lowerEffect index
          ],
          ← exprPlanExpr mkError lowerExpr lowerEffect value
        ])
      ]
  | _ =>
      .error (mkError "EVM EffectPlan-to-Yul planned array write lowering expected storageArrayWriteTarget")

def arrayWriteTargetEffectStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect effect =>
      arrayWriteTargetEffectPlanStatements mkError lowerExpr lowerEffect effect
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul planned array write lowering expected effect")

def dynamicArraySlotTargetExpr
    (target : DynamicArrayTargetPlan)
    (index : Lean.Compiler.Yul.Expr) : Lean.Compiler.Yul.Expr :=
  helperCall Helper.dynamicArraySlot #[slotExpr target.rootSlot, index]

def dynamicArrayPushTargetEffectPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .storageDynamicArrayPushTarget target value => do
      let baseSlot := slotExpr target.rootSlot
      let lenExpr := Lean.Compiler.Yul.Expr.id "__proof_forge_dyn_array_len"
      let newLenExpr := Lean.Compiler.Yul.Expr.id "__proof_forge_dyn_array_new_len"
      .ok #[
        .varDecl #[{ name := "__proof_forge_dyn_array_len" }] (some (Lean.Compiler.Yul.builtin "sload" #[baseSlot])),
        .varDecl #[{ name := "__proof_forge_dyn_array_new_len" }]
          (some (Lean.Compiler.Yul.builtin "add" #[lenExpr, Lean.Compiler.Yul.Expr.num 1])),
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
          dynamicArraySlotTargetExpr target lenExpr,
          ← exprPlanExpr mkError lowerExpr lowerEffect value
        ]),
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[baseSlot, newLenExpr])
      ]
  | _ =>
      .error (mkError "EVM EffectPlan-to-Yul planned dynamic array push lowering expected storageDynamicArrayPushTarget")

def dynamicArrayPushTargetEffectStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect effect =>
      dynamicArrayPushTargetEffectPlanStatements mkError lowerExpr lowerEffect effect
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul planned dynamic array push lowering expected effect")

def dynamicArrayPopTargetEffectPlanStatements
    {ε : Type}
    (mkError : String → ε) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .storageDynamicArrayPopTarget target => do
      let baseSlot := slotExpr target.rootSlot
      let lenExpr := Lean.Compiler.Yul.Expr.id "__proof_forge_dyn_array_len"
      let newLenExpr := Lean.Compiler.Yul.Expr.id "__proof_forge_dyn_array_new_len"
      .ok #[
        .varDecl #[{ name := "__proof_forge_dyn_array_len" }] (some (Lean.Compiler.Yul.builtin "sload" #[baseSlot])),
        .ifStmt (Lean.Compiler.Yul.builtin "iszero" #[lenExpr])
          { statements := #[.exprStmt (Lean.Compiler.Yul.builtin "revert" #[Lean.Compiler.Yul.Expr.num 0, Lean.Compiler.Yul.Expr.num 0])] },
        .varDecl #[{ name := "__proof_forge_dyn_array_new_len" }]
          (some (Lean.Compiler.Yul.builtin "sub" #[lenExpr, Lean.Compiler.Yul.Expr.num 1])),
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[baseSlot, newLenExpr])
      ]
  | _ =>
      .error (mkError "EVM EffectPlan-to-Yul planned dynamic array pop lowering expected storageDynamicArrayPopTarget")

def dynamicArrayPopTargetEffectStmtPlanStatements
    {ε : Type}
    (mkError : String → ε) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect effect =>
      dynamicArrayPopTargetEffectPlanStatements mkError effect
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul planned dynamic array pop lowering expected effect")

def structFieldWriteEffectPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (structFieldSlotFor : String → String → Except ε Lean.Compiler.Yul.Expr)
    (structArrayFieldSlotFor : String → ExprPlan → String → Except ε Lean.Compiler.Yul.Expr) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .storageStructFieldWrite stateId fieldName value => do
      .ok #[
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
          ← structFieldSlotFor stateId fieldName,
          ← exprPlanExpr mkError lowerExpr lowerEffect value
        ])
      ]
  | .storageArrayStructFieldWrite stateId index fieldName value => do
      .ok #[
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
          ← structArrayFieldSlotFor stateId index fieldName,
          ← exprPlanExpr mkError lowerExpr lowerEffect value
        ])
      ]
  | _ =>
      .error (mkError "EVM EffectPlan-to-Yul struct field write lowering expected storageStructFieldWrite/storageArrayStructFieldWrite")

def structFieldWriteEffectStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (structFieldSlotFor : String → String → Except ε Lean.Compiler.Yul.Expr)
    (structArrayFieldSlotFor : String → ExprPlan → String → Except ε Lean.Compiler.Yul.Expr) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect effect =>
      structFieldWriteEffectPlanStatements mkError lowerExpr lowerEffect structFieldSlotFor structArrayFieldSlotFor effect
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul struct field write lowering expected effect")

def structFieldWriteTargetEffectPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .storageStructFieldWriteTarget target value => do
      .ok #[
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
          ← storageSlotExpr mkError lowerExpr target.slot,
          ← exprPlanExpr mkError lowerExpr lowerEffect value
        ])
      ]
  | _ =>
      .error (mkError "EVM EffectPlan-to-Yul planned struct field write lowering expected storageStructFieldWriteTarget")

def structFieldWriteTargetEffectStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect effect =>
      structFieldWriteTargetEffectPlanStatements mkError lowerExpr lowerEffect effect
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul planned struct field write lowering expected effect")

def structArrayFieldWriteTargetEffectPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .storageArrayStructFieldWriteTarget target index value => do
      .ok #[
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
          helperCall Helper.structArraySlot #[
            slotExpr target.rootSlot,
            Lean.Compiler.Yul.Expr.num target.length,
            Lean.Compiler.Yul.Expr.num target.fieldCount,
            Lean.Compiler.Yul.Expr.num target.fieldOffset,
            ← exprPlanExpr mkError lowerExpr lowerEffect index
          ],
          ← exprPlanExpr mkError lowerExpr lowerEffect value
        ])
      ]
  | _ =>
      .error (mkError "EVM EffectPlan-to-Yul planned struct-array field write lowering expected storageArrayStructFieldWriteTarget")

def structArrayFieldWriteTargetEffectStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect effect =>
      structArrayFieldWriteTargetEffectPlanStatements mkError lowerExpr lowerEffect effect
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul planned struct-array field write lowering expected effect")

def structFieldReadExpr (slot : Nat) : Lean.Compiler.Yul.Expr :=
  Lean.Compiler.Yul.builtin "sload" #[slotExpr slot]

def structFieldReadTargetExpr
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (target : StructFieldReadTargetPlan) : Except ε Lean.Compiler.Yul.Expr := do
  .ok (Lean.Compiler.Yul.builtin "sload" #[← storageSlotExpr mkError lowerExpr target.slot])

def structArrayFieldReadExpr
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (rootSlot length fieldCount fieldOffset : Nat)
    (index : ExprPlan) : Except ε Lean.Compiler.Yul.Expr := do
  let fieldSlot := helperCall Helper.structArraySlot #[
    slotExpr rootSlot,
    Lean.Compiler.Yul.Expr.num length,
    Lean.Compiler.Yul.Expr.num fieldCount,
    Lean.Compiler.Yul.Expr.num fieldOffset,
    ← exprPlanExpr mkError lowerExpr lowerEffect index
  ]
  .ok (Lean.Compiler.Yul.builtin "sload" #[fieldSlot])

def structArrayFieldReadTargetExpr
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (target : StructArrayFieldReadTargetPlan)
    (index : ExprPlan) : Except ε Lean.Compiler.Yul.Expr :=
  structArrayFieldReadExpr
    mkError lowerExpr lowerEffect
    target.rootSlot target.length target.fieldCount target.fieldOffset
    index

structure StorageStructWriteField where
  slot : Lean.Compiler.Yul.Expr
  fieldName : String
  value : Lean.Compiler.Yul.Expr
  deriving Inhabited

def storageStructAssignTempName (stateId fieldName : String) : String :=
  s!"__proof_forge_assign_storage_struct_{stateId}_{fieldName}"

def storageStructWriteStatements
    (stateId : String)
    (fields : Array StorageStructWriteField) : Array Lean.Compiler.Yul.Statement :=
  Id.run do
    let mut statements : Array Lean.Compiler.Yul.Statement := #[]
    for field in fields do
      statements := statements.push <|
        .varDecl #[{ name := storageStructAssignTempName stateId field.fieldName }] (some field.value)
    for field in fields do
      statements := statements.push <|
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
          field.slot,
          Lean.Compiler.Yul.Expr.id (storageStructAssignTempName stateId field.fieldName)
        ])
    pure statements

def storageStructWriteFieldFromPlan
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (field : StorageStructWriteFieldPlan) : Except ε StorageStructWriteField := do
  .ok {
    slot := slotExpr field.slot
    fieldName := field.fieldName
    value := ← exprPlanExpr mkError lowerExpr lowerEffect field.value
  }

def storageStructWriteFieldPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (stateId : String)
    (fields : Array StorageStructWriteFieldPlan) :
    Except ε (Array Lean.Compiler.Yul.Statement) := do
  .ok #[
    .block {
      statements :=
        storageStructWriteStatements stateId
          (← fields.mapM (storageStructWriteFieldFromPlan mkError lowerExpr lowerEffect))
    }
  ]

inductive StoragePathWriteTarget where
  | mapWrite (rootSlot key : Lean.Compiler.Yul.Expr)
  | singleSlot (slot : Lean.Compiler.Yul.Expr)
  | mapValuePresence (valueSlot presenceSlot : Lean.Compiler.Yul.Expr)
  deriving Inhabited

def storagePathWriteTargetFromPlan
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr) :
    StoragePathWriteTargetPlan → Except ε StoragePathWriteTarget
  | .mapWrite rootSlot key => do
      .ok (.mapWrite (slotExpr rootSlot) (← lowerValuePlan lowerExpr key))
  | .singleSlot slot => do
      .ok (.singleSlot (← storageSlotExpr mkError lowerExpr slot))
  | .mapValuePresence valueSlot presenceSlot => do
      .ok (.mapValuePresence
        (← storageSlotExpr mkError lowerExpr valueSlot)
        (← storageSlotExpr mkError lowerExpr presenceSlot))

def storagePathWriteExprTargetFromPlan
    {ε : Type}
    (mkError : String → ε)
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr) :
    StoragePathWriteExprTargetPlan → Except ε StoragePathWriteTarget
  | .mapWrite rootSlot key => do
      .ok (.mapWrite (slotExpr rootSlot) (← lowerPlanExpr key))
  | .singleSlot slot => do
      .ok (.singleSlot (← storageSlotExprPlan mkError lowerPlanExpr slot))
  | .mapValuePresence valueSlot presenceSlot => do
      .ok (.mapValuePresence
        (← storageSlotExprPlan mkError lowerPlanExpr valueSlot)
        (← storageSlotExprPlan mkError lowerPlanExpr presenceSlot))

def storagePathWriteTargetStatements
    (value : Lean.Compiler.Yul.Expr) :
    StoragePathWriteTarget → Array Lean.Compiler.Yul.Statement
  | .mapWrite rootSlot key =>
      #[
        .exprStmt (helperCall Helper.mapWrite #[rootSlot, key, value])
      ]
  | .singleSlot slot =>
      #[
        .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[slot, value])
      ]
  | .mapValuePresence valueSlot presenceSlot =>
      #[
        .block { statements := #[
          .varDecl #[{ name := "_slot" }] (some valueSlot),
          .varDecl #[{ name := "_presence_slot" }] (some presenceSlot),
          .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
            Lean.Compiler.Yul.Expr.id "_slot",
            value
          ]),
          .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
            Lean.Compiler.Yul.Expr.id "_presence_slot",
            Lean.Compiler.Yul.Expr.num 1
          ])
        ]}
      ]

def storagePathWriteTargetEffectPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .storagePathWriteTarget target value => do
      .ok <| storagePathWriteTargetStatements
        (← exprPlanExpr mkError lowerExpr lowerEffect value)
        (← storagePathWriteTargetFromPlan mkError lowerExpr target)
  | _ =>
      .error (mkError "EVM EffectPlan-to-Yul planned storage path write lowering expected storagePathWriteTarget")

def storagePathWriteTargetEffectStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect effect =>
      storagePathWriteTargetEffectPlanStatements mkError lowerExpr lowerEffect effect
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul planned storage path write lowering expected effect")

def storagePathWriteExprTargetEffectPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .storagePathWriteExprTarget target value => do
      .ok <| storagePathWriteTargetStatements
        (← exprPlanExpr mkError lowerExpr lowerEffect value)
        (← storagePathWriteExprTargetFromPlan mkError lowerPlanExpr target)
  | _ =>
      .error (mkError "EVM EffectPlan-to-Yul planned storage path write expr lowering expected storagePathWriteExprTarget")

def storagePathWriteExprTargetEffectStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect effect =>
      storagePathWriteExprTargetEffectPlanStatements mkError lowerExpr lowerEffect lowerPlanExpr effect
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul planned storage path write expr lowering expected effect")

def storagePathAssignOpTargetStatements
    (overflowChecked : Bool)
    (op : AssignOp)
    (value : Lean.Compiler.Yul.Expr) :
    StoragePathWriteTarget → Array Lean.Compiler.Yul.Statement
  | .mapWrite rootSlot key =>
      #[
        .exprStmt (helperCall (Helper.mapAssign op) #[rootSlot, key, value])
      ]
  | .singleSlot slot =>
      #[
        .block { statements := #[
          .varDecl #[{ name := "_slot" }] (some slot),
          .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
            Lean.Compiler.Yul.Expr.id "_slot",
            arithExpr overflowChecked op
              (Lean.Compiler.Yul.builtin "sload" #[Lean.Compiler.Yul.Expr.id "_slot"])
              value
          ])
        ]}
      ]
  | .mapValuePresence valueSlot presenceSlot =>
      #[
        .block { statements := #[
          .varDecl #[{ name := "_slot" }] (some valueSlot),
          .varDecl #[{ name := "_presence_slot" }] (some presenceSlot),
          .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
            Lean.Compiler.Yul.Expr.id "_slot",
            arithExpr overflowChecked op
              (Lean.Compiler.Yul.builtin "sload" #[Lean.Compiler.Yul.Expr.id "_slot"])
              value
          ]),
          .exprStmt (Lean.Compiler.Yul.builtin "sstore" #[
            Lean.Compiler.Yul.Expr.id "_presence_slot",
            Lean.Compiler.Yul.Expr.num 1
          ])
        ]}
      ]

def storagePathAssignOpTargetEffectPlanStatements
    {ε : Type}
    (overflowChecked : Bool)
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .storagePathAssignOpTarget target op value => do
      .ok <| storagePathAssignOpTargetStatements overflowChecked op
        (← exprPlanExpr mkError lowerExpr lowerEffect value)
        (← storagePathWriteTargetFromPlan mkError lowerExpr target)
  | _ =>
      .error (mkError "EVM EffectPlan-to-Yul planned storage path assign_op lowering expected storagePathAssignOpTarget")

def storagePathAssignOpTargetEffectStmtPlanStatements
    {ε : Type}
    (overflowChecked : Bool)
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect effect =>
      storagePathAssignOpTargetEffectPlanStatements overflowChecked mkError lowerExpr lowerEffect effect
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul planned storage path assign_op lowering expected effect")

def storagePathAssignOpExprTargetEffectPlanStatements
    {ε : Type}
    (overflowChecked : Bool)
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .storagePathAssignOpExprTarget target op value => do
      .ok <| storagePathAssignOpTargetStatements
        overflowChecked op
        (← exprPlanExpr mkError lowerExpr lowerEffect value)
        (← storagePathWriteExprTargetFromPlan mkError lowerPlanExpr target)
  | _ =>
      .error (mkError "EVM EffectPlan-to-Yul planned storage path assign_op expr lowering expected storagePathAssignOpExprTarget")

def storagePathAssignOpExprTargetEffectStmtPlanStatements
    {ε : Type}
    (overflowChecked : Bool)
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr)
    (lowerPlanExpr : ExprPlan → Except ε Lean.Compiler.Yul.Expr) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect effect =>
      storagePathAssignOpExprTargetEffectPlanStatements overflowChecked mkError lowerExpr lowerEffect lowerPlanExpr effect
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul planned storage path assign_op expr lowering expected effect")

def memoryArraySetEffectPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    EffectPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .memoryArraySet array index value => do
      let arrayExpr ← exprPlanExpr mkError lowerExpr lowerEffect array
      let indexExpr ← exprPlanExpr mkError lowerExpr lowerEffect index
      let valueExpr ← exprPlanExpr mkError lowerExpr lowerEffect value
      let lengthExpr := Lean.Compiler.Yul.builtin "mload" #[arrayExpr]
      let inBounds := Lean.Compiler.Yul.builtin "lt" #[indexExpr, lengthExpr]
      let revertGuard := Lean.Compiler.Yul.Statement.ifStmt
        (Lean.Compiler.Yul.builtin "iszero" #[inBounds])
        { statements := #[revertStatement] }
      let elementPtr := Lean.Compiler.Yul.builtin "add" #[
        Lean.Compiler.Yul.builtin "add" #[arrayExpr, Lean.Compiler.Yul.Expr.num 32],
        Lean.Compiler.Yul.builtin "mul" #[indexExpr, Lean.Compiler.Yul.Expr.num 32]
      ]
      .ok #[
        revertGuard,
        .exprStmt (Lean.Compiler.Yul.builtin "mstore" #[elementPtr, valueExpr])
      ]
  | _ =>
      .error (mkError "EVM EffectPlan-to-Yul memory array set lowering expected memoryArraySet")

def memoryArraySetEffectStmtPlanStatements
    {ε : Type}
    (mkError : String → ε)
    (lowerExpr : Expr → Except ε Lean.Compiler.Yul.Expr)
    (lowerEffect : EffectPlan → Except ε Lean.Compiler.Yul.Expr) :
    StmtPlan → Except ε (Array Lean.Compiler.Yul.Statement)
  | .effect effect =>
      memoryArraySetEffectPlanStatements mkError lowerExpr lowerEffect effect
  | _ =>
      .error (mkError "EVM StmtPlan-to-Yul memory array set lowering expected effect")

end ProofForge.Backend.Evm.ToYul
