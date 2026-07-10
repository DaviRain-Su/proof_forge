namespace EvmRefinement.HexWitness

def hexNibble? : Char → Option UInt8
  | '0' => some 0
  | '1' => some 1
  | '2' => some 2
  | '3' => some 3
  | '4' => some 4
  | '5' => some 5
  | '6' => some 6
  | '7' => some 7
  | '8' => some 8
  | '9' => some 9
  | 'a' | 'A' => some 10
  | 'b' | 'B' => some 11
  | 'c' | 'C' => some 12
  | 'd' | 'D' => some 13
  | 'e' | 'E' => some 14
  | 'f' | 'F' => some 15
  | _ => none

def decodeHexChars? : List Char → Option (List UInt8)
  | [] => some []
  | high :: low :: rest => do
      let high ← hexNibble? high
      let low ← hexNibble? low
      let tail ← decodeHexChars? rest
      return (high * 16 + low) :: tail
  | _ => none

def decodeHex? (source : String) : Option ByteArray := do
  let bytes ← decodeHexChars? source.trimAscii.toString.toList
  return ByteArray.mk bytes.toArray

end EvmRefinement.HexWitness
