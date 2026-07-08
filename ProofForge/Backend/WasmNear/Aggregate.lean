/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import ProofForge.IR.Contract
import ProofForge.Compiler.Wasm.AST
import ProofForge.Backend.WasmNear.ArrayHeap
import ProofForge.Backend.WasmNear.Plan
import ProofForge.Backend.WasmNear.Struct
import ProofForge.Backend.WasmNear.Types

namespace ProofForge.Backend.WasmNear.Aggregate

open ProofForge.IR
open ProofForge.Compiler.Wasm
open ProofForge.Backend.WasmNear.ArrayHeap
open ProofForge.Backend.WasmNear.Plan
open ProofForge.Backend.WasmNear.Struct
open ProofForge.Backend.WasmNear.Types

/-! Helper generation for fixed-array literals/equality and struct literals. -/

def arrayLitName (elemType : ValueType) (len : Nat) : String :=
  "__pf_arr_lit_" ++ typeSuffix elemType ++ "_" ++ toString len

def arrEqName (elemType : ValueType) (len : Nat) : String :=
  "__pf_arr_eq_" ++ typeSuffix elemType ++ "_" ++ toString len

mutual
  partial def collectArrayLitsPathSegment (segment : StoragePathSegment) : Array (ValueType × Nat) :=
    match segment with
    | .field _ => #[]
    | .index index => collectArrayLitsExpr index
    | .mapKey key => collectArrayLitsExpr key

  partial def collectArrayLitsPath (path : Array StoragePathSegment) : Array (ValueType × Nat) :=
    path.foldl (fun acc segment => acc ++ collectArrayLitsPathSegment segment) #[]

  partial def collectArrayLitsExpr (e : Expr) : Array (ValueType × Nat) :=
    match e with
    | .literal _ => #[]
    | .local _ => #[]
    | .arrayLit elementType values =>
        #[(elementType, values.size)] ++ values.foldl (fun acc v => acc ++ collectArrayLitsExpr v) #[]
    | .arrayGet array index => collectArrayLitsExpr array ++ collectArrayLitsExpr index
    | .memoryArrayNew _ length => collectArrayLitsExpr length
    | .memoryArrayLength array => collectArrayLitsExpr array
    | .memoryArrayGet array index => collectArrayLitsExpr array ++ collectArrayLitsExpr index
    | .structLit _ fields => fields.foldl (fun acc f => acc ++ collectArrayLitsExpr f.snd) #[]
    | .field base _ => collectArrayLitsExpr base
    | .add a b _ | .sub a b _ | .mul a b _ | .div a b | .mod a b | .pow a b
    | .bitAnd a b | .bitOr a b | .bitXor a b | .shiftLeft a b | .shiftRight a b
    | .eq a b | .ne a b | .lt a b | .le a b | .gt a b | .ge a b
    | .boolAnd a b | .boolOr a b => collectArrayLitsExpr a ++ collectArrayLitsExpr b
    | .cast value _ => collectArrayLitsExpr value
    | .boolNot value => collectArrayLitsExpr value
    | .hashValue a b c d => collectArrayLitsExpr a ++ collectArrayLitsExpr b ++ collectArrayLitsExpr c ++ collectArrayLitsExpr d
    | .hash preimage => collectArrayLitsExpr preimage
    | .hashTwoToOne a b => collectArrayLitsExpr a ++ collectArrayLitsExpr b
    | .nativeValue => #[]
    | .crosscallInvoke t m args => collectArrayLitsExpr t ++ collectArrayLitsExpr m ++ args.foldl (fun acc a => acc ++ collectArrayLitsExpr a) #[]
    | .crosscallInvokeTyped t m args _
    | .crosscallInvokeStaticTyped t m args _
    | .crosscallInvokeDelegateTyped t m args _ =>
        collectArrayLitsExpr t ++ collectArrayLitsExpr m ++ args.foldl (fun acc a => acc ++ collectArrayLitsExpr a) #[]
    | .crosscallInvokeValueTyped t m v args _ =>
        collectArrayLitsExpr t ++ collectArrayLitsExpr m ++ collectArrayLitsExpr v ++ args.foldl (fun acc a => acc ++ collectArrayLitsExpr a) #[]
    | .crosscallCreate value _ => collectArrayLitsExpr value
    | .crosscallCreate2 value salt _ => collectArrayLitsExpr value ++ collectArrayLitsExpr salt
    | .nearCrosscallInvokePool accountIndex methodId args deposit =>
        collectArrayLitsExpr accountIndex ++ collectArrayLitsExpr methodId ++
          collectArrayLitsExpr deposit ++ args.foldl (fun acc a => acc ++ collectArrayLitsExpr a) #[]
    | .nearPromiseThen parentPromise callbackMethod args deposit =>
        collectArrayLitsExpr parentPromise ++ collectArrayLitsExpr callbackMethod ++
          collectArrayLitsExpr deposit ++ args.foldl (fun acc a => acc ++ collectArrayLitsExpr a) #[]
    | .nearPromiseResultsCount => #[]
    | .nearPromiseResultStatus index => collectArrayLitsExpr index
    | .nearPromiseResultU64 index => collectArrayLitsExpr index
    | .effect eff => collectArrayLitsEffect eff

  partial def collectArrayLitsEffect (eff : Effect) : Array (ValueType × Nat) :=
    match eff with
    | .storageScalarWrite _ v => collectArrayLitsExpr v
    | .storageScalarAssignOp _ _ v => collectArrayLitsExpr v
    | .storageMapContains _ k => collectArrayLitsExpr k
    | .storageMapGet _ k => collectArrayLitsExpr k
    | .storageMapInsert _ k v | .storageMapSet _ k v => collectArrayLitsExpr k ++ collectArrayLitsExpr v
    | .storageArrayRead _ i => collectArrayLitsExpr i
    | .storageArrayWrite _ i v => collectArrayLitsExpr i ++ collectArrayLitsExpr v
    | .storageArrayStructFieldRead _ i _ => collectArrayLitsExpr i
    | .storageArrayStructFieldWrite _ i _ v => collectArrayLitsExpr i ++ collectArrayLitsExpr v
    | .storageDynamicArrayPush _ v => collectArrayLitsExpr v
    | .storageDynamicArrayPop _ => #[]
    | .memoryArraySet _ i v => collectArrayLitsExpr i ++ collectArrayLitsExpr v
    | .storageStructFieldRead _ _ => #[]
    | .storageStructFieldWrite _ _ v => collectArrayLitsExpr v
    | .storagePathRead _ path => collectArrayLitsPath path
    | .storagePathWrite _ path v => collectArrayLitsPath path ++ collectArrayLitsExpr v
    | .storagePathAssignOp _ path _ v => collectArrayLitsPath path ++ collectArrayLitsExpr v
    | .contextRead _ => #[]
    | .eventEmit _ fields => fields.foldl (fun acc f => acc ++ collectArrayLitsExpr f.snd) #[]
    | .eventEmitIndexed _ indexedFields dataFields =>
        let indexed := indexedFields.foldl (fun acc f => acc ++ collectArrayLitsExpr f.snd) #[]
        dataFields.foldl (fun acc f => acc ++ collectArrayLitsExpr f.snd) indexed
    | .storageScalarRead _ => #[]

  partial def collectStructLitsExpr (e : Expr) : Array String :=
    match e with
    | .literal _ | .local _ | .nativeValue => #[]
    | .arrayLit _ values => values.foldl (fun acc v => acc ++ collectStructLitsExpr v) #[]
    | .arrayGet a i => collectStructLitsExpr a ++ collectStructLitsExpr i
    | .memoryArrayNew _ length => collectStructLitsExpr length
    | .memoryArrayLength array => collectStructLitsExpr array
    | .memoryArrayGet array index => collectStructLitsExpr array ++ collectStructLitsExpr index
    | .structLit typeName fields => #[typeName] ++ fields.foldl (fun acc f => acc ++ collectStructLitsExpr f.snd) #[]
    | .field base _ => collectStructLitsExpr base
    | .add a b _ | .sub a b _ | .mul a b _ | .div a b | .mod a b | .pow a b
    | .bitAnd a b | .bitOr a b | .bitXor a b | .shiftLeft a b | .shiftRight a b
    | .eq a b | .ne a b | .lt a b | .le a b | .gt a b | .ge a b
    | .boolAnd a b | .boolOr a b => collectStructLitsExpr a ++ collectStructLitsExpr b
    | .cast value _ | .boolNot value => collectStructLitsExpr value
    | .hash preimage => collectStructLitsExpr preimage
    | .hashValue a b c d => collectStructLitsExpr a ++ collectStructLitsExpr b ++ collectStructLitsExpr c ++ collectStructLitsExpr d
    | .hashTwoToOne a b => collectStructLitsExpr a ++ collectStructLitsExpr b
    | .crosscallInvoke t m args => collectStructLitsExpr t ++ collectStructLitsExpr m ++ args.foldl (fun acc a => acc ++ collectStructLitsExpr a) #[]
    | .crosscallInvokeTyped t m args _
    | .crosscallInvokeStaticTyped t m args _
    | .crosscallInvokeDelegateTyped t m args _ =>
        collectStructLitsExpr t ++ collectStructLitsExpr m ++ args.foldl (fun acc a => acc ++ collectStructLitsExpr a) #[]
    | .crosscallInvokeValueTyped t m v args _ =>
        collectStructLitsExpr t ++ collectStructLitsExpr m ++ collectStructLitsExpr v ++ args.foldl (fun acc a => acc ++ collectStructLitsExpr a) #[]
    | .crosscallCreate value _ => collectStructLitsExpr value
    | .crosscallCreate2 value salt _ => collectStructLitsExpr value ++ collectStructLitsExpr salt
    | .nearCrosscallInvokePool accountIndex methodId args deposit =>
        collectStructLitsExpr accountIndex ++ collectStructLitsExpr methodId ++
          collectStructLitsExpr deposit ++ args.foldl (fun acc a => acc ++ collectStructLitsExpr a) #[]
    | .nearPromiseThen parentPromise callbackMethod args deposit =>
        collectStructLitsExpr parentPromise ++ collectStructLitsExpr callbackMethod ++
          collectStructLitsExpr deposit ++ args.foldl (fun acc a => acc ++ collectStructLitsExpr a) #[]
    | .nearPromiseResultsCount => #[]
    | .nearPromiseResultStatus index => collectStructLitsExpr index
    | .nearPromiseResultU64 index => collectStructLitsExpr index
    | .effect eff => collectStructLitsEffect eff

  partial def collectStructLitsPathSegment (segment : StoragePathSegment) : Array String :=
    match segment with
    | .field _ => #[]
    | .index index => collectStructLitsExpr index
    | .mapKey key => collectStructLitsExpr key

  partial def collectStructLitsPath (path : Array StoragePathSegment) : Array String :=
    path.foldl (fun acc segment => acc ++ collectStructLitsPathSegment segment) #[]

  partial def collectStructLitsEffect (eff : Effect) : Array String :=
    match eff with
    | .storageScalarWrite _ v | .storageScalarAssignOp _ _ v => collectStructLitsExpr v
    | .storageMapContains _ k | .storageMapGet _ k => collectStructLitsExpr k
    | .storageMapInsert _ k v | .storageMapSet _ k v => collectStructLitsExpr k ++ collectStructLitsExpr v
    | .storageArrayRead _ i => collectStructLitsExpr i
    | .storageArrayWrite _ i v => collectStructLitsExpr i ++ collectStructLitsExpr v
    | .storageArrayStructFieldRead _ i _ => collectStructLitsExpr i
    | .storageArrayStructFieldWrite _ i _ v => collectStructLitsExpr i ++ collectStructLitsExpr v
    | .storageDynamicArrayPush _ v => collectStructLitsExpr v
    | .storageDynamicArrayPop _ => #[]
    | .memoryArraySet _ i v => collectStructLitsExpr i ++ collectStructLitsExpr v
    | .storageStructFieldRead _ _ => #[]
    | .storageStructFieldWrite _ _ v => collectStructLitsExpr v
    | .storagePathRead _ path => collectStructLitsPath path
    | .storagePathWrite _ path v => collectStructLitsPath path ++ collectStructLitsExpr v
    | .storagePathAssignOp _ path _ v => collectStructLitsPath path ++ collectStructLitsExpr v
    | .contextRead _ => #[]
    | .eventEmit _ fields => fields.foldl (fun acc f => acc ++ collectStructLitsExpr f.snd) #[]
    | .eventEmitIndexed _ indexedFields dataFields =>
        let indexed := indexedFields.foldl (fun acc f => acc ++ collectStructLitsExpr f.snd) #[]
        dataFields.foldl (fun acc f => acc ++ collectStructLitsExpr f.snd) indexed
    | .storageScalarRead _ => #[]
end

partial def collectArrayLitsStmt (s : Statement) : Array (ValueType × Nat) :=
  match s with
  | .letBind _ _ v | .letMutBind _ _ v => collectArrayLitsExpr v
  | .assign _ v | .assignOp _ _ v => collectArrayLitsExpr v
  | .effect eff => collectArrayLitsEffect eff
  | .assert c _ _ => collectArrayLitsExpr c
  | .assertEq a b _ _ => collectArrayLitsExpr a ++ collectArrayLitsExpr b
  | .ifElse c t e => collectArrayLitsExpr c ++ t.foldl (fun acc st => acc ++ collectArrayLitsStmt st) #[] ++ e.foldl (fun acc st => acc ++ collectArrayLitsStmt st) #[]
  | .boundedFor _ _ _ body => body.foldl (fun acc st => acc ++ collectArrayLitsStmt st) #[]
  | .whileLoop c body => collectArrayLitsExpr c ++ body.foldl (fun acc st => acc ++ collectArrayLitsStmt st) #[]
  | .release _ | .revert _ | .revertWithError _ => #[]
  | .return v => collectArrayLitsExpr v

def dedupArrayLits (xs : Array (ValueType × Nat)) : Array (ValueType × Nat) :=
  xs.foldl (fun acc x => if acc.any (fun y => y.1 == x.1 && y.2 == x.2) then acc else acc.push x) #[]

def moduleArrayLits (mod : ProofForge.IR.Module) : Array (ValueType × Nat) :=
  dedupArrayLits (mod.entrypoints.foldl (fun acc ep => acc ++ ep.body.foldl (fun a st => a ++ collectArrayLitsStmt st) #[]) #[])

def arrLitFunc (elemType : ValueType) (len : Nat) : Func :=
  let w := scalarWidth elemType
  { name := arrayLitName elemType len,
    params := (Array.range len).map (fun i => { name := s!"e{i}", type := wasmTypeOf elemType }),
    results := #[.i32],
    locals := #[{ name := "p", type := .i32 }],
    body := { insns :=
      #[.i64Const (len * w), .call arrAllocName, .localSet "p"] ++
      ((Array.range len).map fun i => #[
        .i32Const (w * i), .localGet "p", .plain "i32.add",
        .localGet s!"e{i}", .store (storeOpFor elemType) 0
      ]).flatten ++ #[.localGet "p"] } }

def arrLitHelperFuncs (mod : ProofForge.IR.Module) : Array Func :=
  moduleArrayLits mod |>.map (fun (e, n) => arrLitFunc e n)

/-- `__pf_arr_eq_<elem>_<len>(pa, pb) -> i32`: element-wise equality.
    Returns 1 if all len elements match, 0 on first mismatch. -/
def arrEqFunc (elemType : ValueType) (len : Nat) : Func :=
  let w   := scalarWidth elemType
  let lop := loadOpFor elemType
  let neq := if elemType == .u64 then "i64.ne" else "i32.ne"
  { name := arrEqName elemType len,
    params := #[{ name := "pa", type := .i32 }, { name := "pb", type := .i32 }],
    results := #[.i32],
    locals := #[{ name := "eq", type := .i32 }, { name := "i", type := .i32 }],
    body := { insns := #[.i32Const 1, .localSet "eq",
      .block_ { insns := #[ .loop_ { insns := #[
        .localGet "i", .i32Const len, .plain "i32.ge_u", .brIf 1,
        .localGet "pa", .localGet "i", .i32Const w, .plain "i32.mul", .plain "i32.add", .load lop 0,
        .localGet "pb", .localGet "i", .i32Const w, .plain "i32.mul", .plain "i32.add", .load lop 0,
        .plain neq,
        .if_ { insns := #[.i32Const 0, .localSet "eq", .br 2] } { insns := #[] },
        .localGet "i", .i32Const 1, .plain "i32.add", .localSet "i", .br 0
      ] } ] },
      .localGet "eq"] } }

def arrEqHelperFuncs (mod : ProofForge.IR.Module) : Array Func :=
  moduleArrayLits mod |>.map (fun (e, n) => arrEqFunc e n)

/-- `__pf_struct_lit_<name>(f0,f1,..) -> i32`: alloc totalSize bytes, store each
    field at its cumulative offset, return the base pointer. -/
def structLitFunc (s : ProofForge.IR.StructDecl) : Func :=
  let total := structTotalSize s
  let stores : Array Insn :=
    (s.fields.foldl (fun st f =>
        (st.1 + scalarWidth f.type,
         st.2 ++ #[.i32Const st.1, .localGet "p", .plain "i32.add",
                   .localGet f.id, .store (storeOpFor f.type) 0]))
      (0, (#[] : Array Insn))).2
  { name := structLitName s.name,
    params := s.fields.map (fun f => { name := f.id, type := wasmTypeOf f.type }),
    results := #[.i32],
    locals := #[{ name := "p", type := .i32 }],
    body := { insns :=
      #[.i64Const total, .call arrAllocName, .localSet "p"] ++ stores ++ #[.localGet "p"] } }

partial def collectStructLitsStmt (s : Statement) : Array String :=
  match s with
  | .letBind _ _ v | .letMutBind _ _ v => collectStructLitsExpr v
  | .assign _ v | .assignOp _ _ v => collectStructLitsExpr v
  | .effect eff => collectStructLitsEffect eff
  | .assert c _ _ => collectStructLitsExpr c
  | .assertEq a b _ _ => collectStructLitsExpr a ++ collectStructLitsExpr b
  | .ifElse c t e => collectStructLitsExpr c ++ t.foldl (fun acc st => acc ++ collectStructLitsStmt st) #[] ++ e.foldl (fun acc st => acc ++ collectStructLitsStmt st) #[]
  | .boundedFor _ _ _ body => body.foldl (fun acc st => acc ++ collectStructLitsStmt st) #[]
  | .whileLoop c body => collectStructLitsExpr c ++ body.foldl (fun acc st => acc ++ collectStructLitsStmt st) #[]
  | .release _ | .revert _ | .revertWithError _ => #[]
  | .return v => collectStructLitsExpr v

def dedupStrings (xs : Array String) : Array String :=
  xs.foldl (fun acc x => if acc.any (fun y => y == x) then acc else acc.push x) #[]

def moduleStructLitNames (mod : ProofForge.IR.Module) : Array String :=
  dedupStrings (mod.entrypoints.foldl (fun acc ep => acc ++ ep.body.foldl (fun a st => a ++ collectStructLitsStmt st) #[]) #[])

def structLitHelperFuncs (mod : ProofForge.IR.Module) : Array Func :=
  moduleStructLitNames mod |>.filterMap (fun name => (mod.structs.find? (fun s => s.name == name)).map structLitFunc)

def arrayLitFuncsForModulePlan (plan : ModulePlan) : Array Func :=
  plan.arrayLitShapes.map (fun (elemType, len) => arrLitFunc elemType len)

def arrayEqFuncsForModulePlan (plan : ModulePlan) : Array Func :=
  plan.arrayEqShapes.map (fun (elemType, len) => arrEqFunc elemType len)

def structLitFuncsForModulePlan (plan : ModulePlan) (mod : ProofForge.IR.Module) : Array Func :=
  plan.structLitNames.filterMap (fun name => (mod.structs.find? (fun s => s.name == name)).map structLitFunc)

def aggregateHelperFuncsForModulePlan (plan : ModulePlan) (mod : ProofForge.IR.Module) : Array Func :=
  arrayLitFuncsForModulePlan plan ++ arrayEqFuncsForModulePlan plan ++
    structLitFuncsForModulePlan plan mod ++ arrHeapHelperFuncsForModulePlan plan mod.allocator

end ProofForge.Backend.WasmNear.Aggregate
