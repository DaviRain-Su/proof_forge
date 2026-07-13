/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import ProofForge.Backend.Stylus.Plan

namespace ProofForge.Backend.Stylus.RustSdk

open ProofForge.Backend.Stylus

inductive RustReceiver where
  | shared
  | mutable
  deriving Repr, BEq

inductive RustReturnType where
  | unit
  | value (typeName : String)
  | resultUnit
  | resultValue (typeName : String)
  deriving Repr, BEq

inductive RustStmt where
  | letLiteral (name typeName value : String)
  | letStorageGet (name field : String) (type : StylusAbiType)
  | letMapGet (name field : String) (keys : Array String) (type : StylusAbiType)
  | letAdd (name typeName lhs rhs : String) (mode : StylusOverflowMode)
  | letArithmetic (name typeName lhs rhs method : String) (mode : StylusOverflowMode)
  | letContext (name expression : String)
  | letCompare (name lhs rhs : String) (op : StylusCompareOp)
  | assert_ (condition message : String)
  | emitEvent (signature : String)
      (indexed data : Array (String × StylusAbiType))
  | storageSet (field value : String) (type : StylusAbiType)
  | mapSet (field : String) (keys : Array String) (value : String) (type : StylusAbiType)
  | returnValue (value : String)
  | okValue (value : String)
  | okUnit
  deriving Repr, BEq

structure RustStorageField where
  name : String
  typeName : String
  deriving Repr, BEq

structure RustParam where
  name : String
  typeName : String
  localName : String
  deriving Repr, BEq

structure RustFunction where
  name : String
  receiver : RustReceiver
  params : Array RustParam := #[]
  returnType : RustReturnType
  payable : Bool := false
  body : Array RustStmt
  deriving Repr, BEq

structure RustContract where
  name : String
  storage : Array RustStorageField
  functions : Array RustFunction
  deriving Repr, BEq

structure RustFile where
  path : String
  content : String
  deriving Repr, BEq

structure RustCrate where
  name : String
  files : Array RustFile
  deriving Repr, BEq

def RustCrate.find? (crate : RustCrate) (path : String) : Option String :=
  (crate.files.find? fun file => file.path == path).map (fun file => file.content)

end ProofForge.Backend.Stylus.RustSdk
