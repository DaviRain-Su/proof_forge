/-
  Psy DPN Schema V1 — engineering model of official `psy_vm` DPN shapes.

  Authority: PsyProtocol/psy-node @ `psyNodeDpnAuthorityRevV1`, crate
  `psy_vm`:
    * `DPNFunctionCircuitDefinition` — dpn/vm/def.rs
    * `DPNOpType` / `DPNIndexedVarDef` — dpn/ops/op_types.rs
    * `DPNStateCmd` — dpn/ops/state_cmd/data.rs
    * method_id: `psy_crypto::hash::utils::gen_dapen_contract_function_method_id`

  This is the direct target-owned schema / method_id authority pin, not an
  executable tool provision. Finalization is zero-tool. Supply-chain
  annotation: `supply-chain/psy-node-dpn-authority.v1.json`.

  This module is **not** formal semantics. Exact `u16` / `u8` discriminants
  follow the upstream enums (including holes).
-/
namespace ProofForgeV2.Targets.Psy.Dpn.SchemaV1

/-- Exact 40-hex git rev of PsyProtocol/psy-node used as DPN schema +
    `gen_dapen` method_id algorithm authority. Documentation/engineering pin
    only — not an executable tool asset. Changing this without revalidating
    Schema discriminants and Counter method_id goldens is fail closed by suite. -/
def psyNodeDpnAuthorityRevV1 : String :=
  "79e0b82422ebdd1173a7b4b3751eb3186aad83e5"

/-- Canonical repository URL for `psyNodeDpnAuthorityRevV1`. -/
def psyNodeDpnAuthorityRepoV1 : String :=
  "https://github.com/PsyProtocol/psy-node"

/-- Official `DPNBuiltInDataType` (`repr(u8)`-style ordinals). -/
inductive DataTypeV1 where
  | target       -- 0
  | bool         -- 1
  | u32Target    -- 2
  | hashOut      -- 3
  | hashOut160   -- 4
  | targetArray  -- 5
  | boolArray    -- 6
  | u32TargetArray -- 7
  | unknown      -- 63
  deriving DecidableEq, Repr, Inhabited

def DataTypeV1.toUInt8 : DataTypeV1 → UInt8
  | .target => 0
  | .bool => 1
  | .u32Target => 2
  | .hashOut => 3
  | .hashOut160 => 4
  | .targetArray => 5
  | .boolArray => 6
  | .u32TargetArray => 7
  | .unknown => 63

def DataTypeV1.ofUInt8? : UInt8 → Option DataTypeV1
  | 0 => some .target
  | 1 => some .bool
  | 2 => some .u32Target
  | 3 => some .hashOut
  | 4 => some .hashOut160
  | 5 => some .targetArray
  | 6 => some .boolArray
  | 7 => some .u32TargetArray
  | 63 => some .unknown
  | _ => none

/-- Official `DPNOpType` with **exact** `u16` values (holes preserved). -/
inductive OpTypeV1 where
  | inputTarget                              -- 0
  | constant                                 -- 1
  | constantTrue                             -- 2
  | constantFalse                            -- 3
  | add | sub | mul | div                   -- 4-7
  | boolNot | boolAnd | boolOr | xor | nor   -- 8-12
  | eq | lte | gte | gt | lt                 -- 13-17
  | splitBits | sumBits | targetAt           -- 18-20
  | hashNoPad | hashPad | select             -- 21-23
  | exp | expConstantPower | expConstantBase -- 24-26
  | mod_ | modConstantDividend | modConstantDivisor | divRem4 -- 27-30
  | castU32                                  -- 31
  | u32And | u32AndConstant                  -- 32-33
  | u32Or | u32OrConstant                    -- 34-35
  | u32Xor | u32XorConstant                  -- 36-37
  | u32ShiftLeft                             -- 38
  -- 39 hole
  | u32ShiftLeftConstantBitDistance          -- 40
  | u32ShiftLeftConstantValue                -- 41
  | u32ShiftRight                            -- 42
  | u32ShiftRightConstantBitDistance         -- 43
  | u32ShiftRightConstantValue               -- 44
  | calculateMerkleRoot                      -- 45
  | getUserId | getContractId | getCheckpointId | getNonce | getUserPublicKeyHash -- 46-50
  | getStateQueryResult | getStateQueryResultSingle -- 51-52
  | getStateCommandResultHash | getStateCommandResultSingle | getStateCommandResultArray -- 53-55
  -- 56-63 hole
  | unaryInverse | unaryNegative             -- 64-65
  | u32InputTarget | constantU32             -- 66-67
  | u32Add | u32Sub | u32Mul | u32Div        -- 68-71
  | castFelt | castBool | boolInputTarget    -- 72-74
  | u32Mod | u32Exp                          -- 75-76
  | secp256k1Verify | hashTwoToOne           -- 77-78
  | getCallerContractId | getSessionProofTreeRoot | keccak256 -- 79-81
  deriving DecidableEq, Repr, Inhabited

def OpTypeV1.toUInt16 : OpTypeV1 → UInt16
  | .inputTarget => 0
  | .constant => 1
  | .constantTrue => 2
  | .constantFalse => 3
  | .add => 4 | .sub => 5 | .mul => 6 | .div => 7
  | .boolNot => 8 | .boolAnd => 9 | .boolOr => 10 | .xor => 11 | .nor => 12
  | .eq => 13 | .lte => 14 | .gte => 15 | .gt => 16 | .lt => 17
  | .splitBits => 18 | .sumBits => 19 | .targetAt => 20
  | .hashNoPad => 21 | .hashPad => 22 | .select => 23
  | .exp => 24 | .expConstantPower => 25 | .expConstantBase => 26
  | .mod_ => 27 | .modConstantDividend => 28 | .modConstantDivisor => 29 | .divRem4 => 30
  | .castU32 => 31
  | .u32And => 32 | .u32AndConstant => 33
  | .u32Or => 34 | .u32OrConstant => 35
  | .u32Xor => 36 | .u32XorConstant => 37
  | .u32ShiftLeft => 38
  | .u32ShiftLeftConstantBitDistance => 40
  | .u32ShiftLeftConstantValue => 41
  | .u32ShiftRight => 42
  | .u32ShiftRightConstantBitDistance => 43
  | .u32ShiftRightConstantValue => 44
  | .calculateMerkleRoot => 45
  | .getUserId => 46 | .getContractId => 47 | .getCheckpointId => 48
  | .getNonce => 49 | .getUserPublicKeyHash => 50
  | .getStateQueryResult => 51 | .getStateQueryResultSingle => 52
  | .getStateCommandResultHash => 53
  | .getStateCommandResultSingle => 54
  | .getStateCommandResultArray => 55
  | .unaryInverse => 64 | .unaryNegative => 65
  | .u32InputTarget => 66 | .constantU32 => 67
  | .u32Add => 68 | .u32Sub => 69 | .u32Mul => 70 | .u32Div => 71
  | .castFelt => 72 | .castBool => 73 | .boolInputTarget => 74
  | .u32Mod => 75 | .u32Exp => 76
  | .secp256k1Verify => 77 | .hashTwoToOne => 78
  | .getCallerContractId => 79 | .getSessionProofTreeRoot => 80 | .keccak256 => 81

def OpTypeV1.ofUInt16? : UInt16 → Option OpTypeV1
  | 0 => some .inputTarget | 1 => some .constant
  | 2 => some .constantTrue | 3 => some .constantFalse
  | 4 => some .add | 5 => some .sub | 6 => some .mul | 7 => some .div
  | 8 => some .boolNot | 9 => some .boolAnd | 10 => some .boolOr
  | 11 => some .xor | 12 => some .nor
  | 13 => some .eq | 14 => some .lte | 15 => some .gte | 16 => some .gt | 17 => some .lt
  | 18 => some .splitBits | 19 => some .sumBits | 20 => some .targetAt
  | 21 => some .hashNoPad | 22 => some .hashPad | 23 => some .select
  | 24 => some .exp | 25 => some .expConstantPower | 26 => some .expConstantBase
  | 27 => some .mod_ | 28 => some .modConstantDividend | 29 => some .modConstantDivisor
  | 30 => some .divRem4 | 31 => some .castU32
  | 32 => some .u32And | 33 => some .u32AndConstant
  | 34 => some .u32Or | 35 => some .u32OrConstant
  | 36 => some .u32Xor | 37 => some .u32XorConstant
  | 38 => some .u32ShiftLeft
  | 40 => some .u32ShiftLeftConstantBitDistance
  | 41 => some .u32ShiftLeftConstantValue
  | 42 => some .u32ShiftRight
  | 43 => some .u32ShiftRightConstantBitDistance
  | 44 => some .u32ShiftRightConstantValue
  | 45 => some .calculateMerkleRoot
  | 46 => some .getUserId | 47 => some .getContractId | 48 => some .getCheckpointId
  | 49 => some .getNonce | 50 => some .getUserPublicKeyHash
  | 51 => some .getStateQueryResult | 52 => some .getStateQueryResultSingle
  | 53 => some .getStateCommandResultHash
  | 54 => some .getStateCommandResultSingle
  | 55 => some .getStateCommandResultArray
  | 64 => some .unaryInverse | 65 => some .unaryNegative
  | 66 => some .u32InputTarget | 67 => some .constantU32
  | 68 => some .u32Add | 69 => some .u32Sub | 70 => some .u32Mul | 71 => some .u32Div
  | 72 => some .castFelt | 73 => some .castBool | 74 => some .boolInputTarget
  | 75 => some .u32Mod | 76 => some .u32Exp
  | 77 => some .secp256k1Verify | 78 => some .hashTwoToOne
  | 79 => some .getCallerContractId | 80 => some .getSessionProofTreeRoot
  | 81 => some .keccak256
  | _ => none

/-- Encoded operand / wire id: `(dataType << 32) | index` (official INDEX_BITS=32). -/
def encodeIndexedId (dataType : DataTypeV1) (index : Nat) : UInt64 :=
  (UInt64.ofNat dataType.toUInt8.toNat <<< 32) ||| UInt64.ofNat (index &&& 0xffffffff)

def decodeIndexedId (id : UInt64) : Option (DataTypeV1 × Nat) :=
  let tyBits := (id >>> 32).toNat
  let idx := (id &&& 0xffffffff).toNat
  match DataTypeV1.ofUInt8? (UInt8.ofNat tyBits) with
  | none => none
  | some ty => some (ty, idx)

structure IndexedVarDefV1 where
  dataType : DataTypeV1
  index : Nat
  opType : OpTypeV1
  inputs : Array UInt64
  deriving DecidableEq, Repr, Inhabited

structure AssertEqV1 where
  left : UInt64
  right : UInt64
  message : String
  deriving DecidableEq, Repr, Inhabited

/-- Official `DPNEventRecord` (psy_vm op_types). `condition` is a full
    `(dataType<<32)|index` bool id; `checkpoint_id` / `user_id` /
    `contract_id` / `data` are Target-typed wire ids (raw index when type=0).
    Product emit is PARTIAL: no ordered-event runtime gate. -/
structure EventRecordV1 where
  condition : UInt64
  checkpointId : UInt64
  userId : UInt64
  contractId : UInt64
  data : Array UInt64
  deriving DecidableEq, Repr, Inhabited

/-- State commands used by product Counter (and DPN-6 effect leaves).
    Others remain unmodeled until admit; unknown JSON tags fail closed at decode. -/
inductive StateCmdV1 where
  | getSelfUserCurrentContractStateSlotSingle (subSlotIndex : UInt64)
  | setContractStateSlotSingle (condition subSlotIndex value : UInt64)
  | getSelfUserCurrentContractStateSlotHash (slotIndex : UInt64)
  | setContractStateSlotHash (condition slotIndex : UInt64) (value : Array UInt64)
  /-- Void sync `call` → `InvokeExternalContractFunctionSync` (DPN-6 PARTIAL).
      Direct DPN operation with hashed QN; no deployment-address / response /
      runtime gate. `numOutputs=0` for void. -/
  | invokeExternalContractFunctionSync
      (condition contractId methodId : UInt64)
      (inputArgs : Array UInt64) (numOutputs : UInt32)
  deriving DecidableEq, Repr

structure FunctionCircuitDefV1 where
  name : String
  methodId : UInt32
  circuitInputs : Array UInt64
  circuitOutputs : Array UInt64
  stateCommands : Array StateCmdV1
  stateCommandResolutionIndices : Array Nat
  assertions : Array AssertEqV1
  definitions : Array IndexedVarDefV1
  events : Array EventRecordV1 := #[]
  deriving DecidableEq, Repr, Inhabited

/-- Package artifact = ordered array of per-method DPN definitions. -/
abbrev PackageV1 := Array FunctionCircuitDefV1

/-- Hand-built Counter package freezing the target-owned canonical JSON shape
    (get, increment, initialize — name-sorted).

    Operand wiring:
    * `definitions[].inputs` often carry raw same-type indices (small u64).
    * `assertions` left/right use full `(dataType<<32)|index` encoding.
    * `SetContractStateSlotSingle.condition` uses full bool encoding; `value`
      and bare `sub_slot_index` use raw indices / literals.
    * View `get` uses sub-slot 0; init/increment writes use sub-slot 1.
-/
def counterPackageGoldenV1 : PackageV1 :=
  let b0 := encodeIndexedId .bool 0
  let b1 := encodeIndexedId .bool 1
  #[
    { name := "get"
      methodId := 1459926901
      circuitInputs := #[]
      circuitOutputs := #[1]
      stateCommands := #[.getSelfUserCurrentContractStateSlotSingle 0]
      stateCommandResolutionIndices := #[1]
      assertions := #[]
      definitions := #[
        { dataType := .target, index := 0, opType := .constant, inputs := #[0] },
        { dataType := .target, index := 1, opType := .getStateCommandResultSingle, inputs := #[0] }
      ]
      events := #[] },
    { name := "increment"
      methodId := 1990357658
      circuitInputs := #[0]
      circuitOutputs := #[4]
      stateCommands := #[
        .getSelfUserCurrentContractStateSlotSingle 1,
        .setContractStateSlotSingle b0 1 3,
        .getSelfUserCurrentContractStateSlotSingle 1
      ]
      stateCommandResolutionIndices := #[2, 5, 5]
      assertions := #[{ left := b1, right := b0, message := "u64 add overflow" }]
      definitions := #[
        { dataType := .target, index := 0, opType := .inputTarget, inputs := #[0] },
        { dataType := .target, index := 1, opType := .constant, inputs := #[0] },
        { dataType := .bool, index := 0, opType := .constantTrue, inputs := #[1] },
        { dataType := .target, index := 2, opType := .getStateCommandResultSingle, inputs := #[0] },
        { dataType := .target, index := 3, opType := .add, inputs := #[2, 0] },
        { dataType := .bool, index := 1, opType := .gte, inputs := #[3, 2] },
        { dataType := .target, index := 4, opType := .getStateCommandResultSingle, inputs := #[2] }
      ]
      events := #[] },
    { name := "initialize"
      methodId := 202172507
      circuitInputs := #[0]
      circuitOutputs := #[]
      stateCommands := #[
        .getSelfUserCurrentContractStateSlotSingle 1,
        .setContractStateSlotSingle b0 1 0
      ]
      stateCommandResolutionIndices := #[2, 3]
      assertions := #[]
      definitions := #[
        { dataType := .target, index := 0, opType := .inputTarget, inputs := #[0] },
        { dataType := .target, index := 1, opType := .constant, inputs := #[0] },
        { dataType := .bool, index := 0, opType := .constantTrue, inputs := #[1] }
      ]
      events := #[] }
  ]

end ProofForgeV2.Targets.Psy.Dpn.SchemaV1
