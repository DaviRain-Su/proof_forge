/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Shared hex/string helpers for CLI codegen. These pure functions are used by
constructor ABI encoding, bytecode initcode assembly, solc/cast output parsing,
and artifact hex emission.

Previously `trimAsciiString` was duplicated across `Cli.lean`, `Cli/Check.lean`,
`Cli/Deploy.lean`, and `Contract/SdkSchema.lean`; `stripHexPrefix` across
`Cli.lean` and three `Backend/Evm/*` modules. This module is the single source
of truth for CLI-side hex helpers; backend modules keep their own copies for
now to avoid cross-layer import churn.
-/

import ProofForge.Util.StringUtil

namespace ProofForge.Cli.HexUtil

open ProofForge.Util.StringUtil

/-- Alias re-exported so CLI code that `open HexUtil` keeps seeing `trimAsciiString`.
The implementation lives in `ProofForge.Util.StringUtil` and is shared with the
Contract and Backend layers. -/
def trimAsciiString (s : String) : String := trimAscii s

/-- Alias re-exported so CLI code that `open HexUtil` keeps seeing `stripHexPrefix`.
The implementation lives in `ProofForge.Util.StringUtil`. -/
def stripHexPrefix (s : String) : String := ProofForge.Util.StringUtil.stripHexPrefix s

def lowerHexString (s : String) : String :=
  String.intercalate "" <| s.toList.map fun ch =>
    match ch with
    | 'A' => "a"
    | 'B' => "b"
    | 'C' => "c"
    | 'D' => "d"
    | 'E' => "e"
    | 'F' => "f"
    | _ => ch.toString

def isHexChar (c : Char) : Bool :=
  c.isDigit || "abcdefABCDEF".contains c

def isHexString (s : String) : Bool :=
  !s.isEmpty && s.all isHexChar

def repeatString : Nat → String → String
  | 0, _ => ""
  | n+1, s => s ++ repeatString n s

def hexDigit (value : Nat) : String :=
  match value with
  | 0 => "0"
  | 1 => "1"
  | 2 => "2"
  | 3 => "3"
  | 4 => "4"
  | 5 => "5"
  | 6 => "6"
  | 7 => "7"
  | 8 => "8"
  | 9 => "9"
  | 10 => "a"
  | 11 => "b"
  | 12 => "c"
  | 13 => "d"
  | 14 => "e"
  | _ => "f"

partial def natToHex (value : Nat) : String :=
  if value < 16 then
    hexDigit value
  else
    natToHex (value / 16) ++ hexDigit (value % 16)

def byteLimit : Nat → Nat
  | 0 => 1
  | n+1 => 256 * byteLimit n

def fixedHexBytes (byteCount value : Nat) : String :=
  let raw := natToHex value
  repeatString (byteCount * 2 - raw.length) "0" ++ raw

def hexCharValue! : Char → Nat
  | '0' => 0
  | '1' => 1
  | '2' => 2
  | '3' => 3
  | '4' => 4
  | '5' => 5
  | '6' => 6
  | '7' => 7
  | '8' => 8
  | '9' => 9
  | 'a' | 'A' => 10
  | 'b' | 'B' => 11
  | 'c' | 'C' => 12
  | 'd' | 'D' => 13
  | 'e' | 'E' => 14
  | _ => 15

def parseHexNat (value name : String) : Except String Nat :=
  let hex := stripHexPrefix (trimAsciiString value)
  if hex.isEmpty then
    .error s!"{name} must not be empty"
  else if !hex.all isHexChar then
    .error s!"{name} must contain only hex digits"
  else
    .ok (hex.toList.foldl (fun acc ch => acc * 16 + hexCharValue! ch) 0)

def parseUnsignedNat (value name : String) : Except String Nat :=
  let value := trimAsciiString value
  if value.startsWith "0x" || value.startsWith "0X" then
    parseHexNat value name
  else
    match value.toNat? with
    | some n => .ok n
    | none => .error s!"{name} must be an unsigned decimal integer or 0x-prefixed hex integer"

def normalizeExactHexBytes (value name : String) (bytes : Nat) : Except String String :=
  let hex := stripHexPrefix (trimAsciiString value)
  if hex.length != bytes * 2 then
    .error s!"{name} must be exactly {bytes} byte(s)"
  else if !hex.all isHexChar then
    .error s!"{name} must contain only hex digits"
  else
    .ok (lowerHexString hex)

def normalizeConstructorArgsHex (value : String) : Except String String :=
  let hex := stripHexPrefix (trimAsciiString value)
  if hex.isEmpty then
    .ok ""
  else if hex.length % 2 != 0 then
    .error "--evm-constructor-args-hex must have an even number of hex digits"
  else if !hex.all isHexChar then
    .error "--evm-constructor-args-hex must contain only hex digits"
  else
    .ok (lowerHexString hex)

def byteToHex (byte : UInt8) : String :=
  let value := byte.toNat
  hexDigit (value / 16) ++ hexDigit (value % 16)

def byteArrayToHex (bytes : ByteArray) : String := Id.run do
  let mut hex := ""
  for idx in [0:bytes.size] do
    hex := hex ++ byteToHex (bytes[idx]!)
  return hex

def padHexTo32ByteBoundary (hex : String) : String :=
  let byteCount := hex.length / 2
  let rem := byteCount % 32
  if rem == 0 then
    hex
  else
    hex ++ repeatString ((32 - rem) * 2) "0"

end ProofForge.Cli.HexUtil