/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Wrap IR-rendered ERC-20 runtime Yul with creation code that seeds supply/decimals.
-/
import ProofForge.Contract.Token
import ProofForge.Compiler.Yul.Printer

namespace ProofForge.Contract.Token.EvmWrap

open ProofForge.Contract.Token
open Lean.Compiler.Yul

private def line (indent : Nat) (text : String) : String :=
  String.ofList (List.replicate (indent * 2) ' ') ++ text ++ "\n"

private def block (indent : Nat) (lines : Array String) : String :=
  lines.foldl (fun acc text => acc ++ line indent text) ""

private def initialSupplyLiteral (spec : TokenSpec) : String :=
  toString (spec.initialSupply?.getD 0)

private def decimalsLiteral (spec : TokenSpec) : String :=
  toString spec.decimals

/-- Wrap a lowered runtime Yul object with ERC-20 creation initialization.
    Storage layout matches `ProofForge.Contract.Stdlib.ERC20` after IR lowering:
    slot 0 packs totalSupply and decimals as u64 scalar fields, slot 1 roots
    balances, and slot 2 roots allowances. -/
def wrapRuntimeObject (objectName runtimeName : String) (runtimeObject : Object)
    (spec : TokenSpec) : Except String String := do
  let _ ← ProofForge.Contract.FixedPoint.validateDecimals spec.decimals
  validateEvmTokenFeatures spec
  let runtimeYul := Printer.renderCode 2 runtimeObject.code
  let u64Mask := "18446744073709551615"
  let packedScalarSlot :=
    "or(and(" ++ initialSupplyLiteral spec ++ ", " ++ u64Mask ++ "), shl(64, and(" ++
      decimalsLiteral spec ++ ", " ++ u64Mask ++ ")))"
  let datacopyLine :=
    "  datacopy(0x00, dataoffset(\"" ++ runtimeName ++ "\"), datasize(\"" ++ runtimeName ++ "\"))"
  let returnLine := "  return(0x00, datasize(\"" ++ runtimeName ++ "\"))"
  let creation :=
    block 1 #[
      "code {",
      "  function mapSlot(root, key) -> slot {",
      "    mstore(0x00, key)",
      "    mstore(0x20, root)",
      "    slot := keccak256(0x00, 0x40)",
      "  }",
      "  sstore(0, " ++ packedScalarSlot ++ ")",
      "  sstore(mapSlot(1, caller()), " ++ initialSupplyLiteral spec ++ ")",
      datacopyLine,
      returnLine,
      "}"
    ]
  .ok <|
    "object \"" ++ objectName ++ "\" {\n" ++
      creation ++
      line 1 ("object \"" ++ runtimeName ++ "\" {") ++
      runtimeYul ++
      line 1 "}" ++
      "}\n"

end ProofForge.Contract.Token.EvmWrap
