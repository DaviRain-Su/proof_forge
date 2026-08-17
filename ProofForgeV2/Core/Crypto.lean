namespace ProofForgeV2.Crypto

private def rotateRight (value : UInt32) (amount : Nat) : UInt32 :=
  UInt32.shiftRight value (UInt32.ofNat amount) |||
    UInt32.shiftLeft value (UInt32.ofNat (32 - amount))

private def choose (x y z : UInt32) : UInt32 :=
  (x &&& y) ^^^ ((~~~x) &&& z)

private def majority (x y z : UInt32) : UInt32 :=
  (x &&& y) ^^^ (x &&& z) ^^^ (y &&& z)

private def bigSigma0 (value : UInt32) : UInt32 :=
  rotateRight value 2 ^^^ rotateRight value 13 ^^^ rotateRight value 22

private def bigSigma1 (value : UInt32) : UInt32 :=
  rotateRight value 6 ^^^ rotateRight value 11 ^^^ rotateRight value 25

private def smallSigma0 (value : UInt32) : UInt32 :=
  rotateRight value 7 ^^^ rotateRight value 18 ^^^ UInt32.shiftRight value 3

private def smallSigma1 (value : UInt32) : UInt32 :=
  rotateRight value 17 ^^^ rotateRight value 19 ^^^ UInt32.shiftRight value 10

private def roundConstants : Array UInt32 := #[
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
  0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
  0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
  0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
  0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
  0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
]

private def initialState : Array UInt32 := #[
  0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
  0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
]

private def appendUInt64BE (bytes : ByteArray) (value : UInt64) : ByteArray :=
  bytes
    |>.push (UInt64.shiftRight value 56).toUInt8
    |>.push (UInt64.shiftRight value 48).toUInt8
    |>.push (UInt64.shiftRight value 40).toUInt8
    |>.push (UInt64.shiftRight value 32).toUInt8
    |>.push (UInt64.shiftRight value 24).toUInt8
    |>.push (UInt64.shiftRight value 16).toUInt8
    |>.push (UInt64.shiftRight value 8).toUInt8
    |>.push value.toUInt8

private def pushZeroBytes : Nat → ByteArray → ByteArray
  | 0, bytes => bytes
  | count + 1, bytes => pushZeroBytes count (bytes.push 0)

private def pad (input : ByteArray) : ByteArray :=
  let bitLength := UInt64.ofNat input.size * 8
  let zeroCount := (119 - input.size % 64) % 64
  appendUInt64BE (pushZeroBytes zeroCount (input.push 0x80)) bitLength

private def wordAt (bytes : ByteArray) (offset : Nat) : UInt32 :=
  UInt32.shiftLeft bytes[offset]!.toUInt32 24 |||
    UInt32.shiftLeft bytes[offset + 1]!.toUInt32 16 |||
    UInt32.shiftLeft bytes[offset + 2]!.toUInt32 8 |||
    bytes[offset + 3]!.toUInt32

private def loadScheduleWords (bytes : ByteArray) (offset : Nat) :
    Nat → Nat → Array UInt32 → Array UInt32
  | 0, _, schedule => schedule
  | count + 1, index, schedule =>
      loadScheduleWords bytes offset count (index + 1)
        (schedule.set! index (wordAt bytes (offset + index * 4)))

private def extendScheduleWords : Nat → Nat → Array UInt32 → Array UInt32
  | 0, _, schedule => schedule
  | count + 1, index, schedule =>
      let value := smallSigma1 schedule[index - 2]! + schedule[index - 7]! +
        smallSigma0 schedule[index - 15]! + schedule[index - 16]!
      extendScheduleWords count (index + 1) (schedule.set! index value)

private def scheduleFor (bytes : ByteArray) (offset : Nat) : Array UInt32 :=
  let schedule := loadScheduleWords bytes offset 16 0 (Array.replicate 64 0)
  extendScheduleWords 48 16 schedule

private structure CompressionRegisters where
  a : UInt32
  b : UInt32
  c : UInt32
  d : UInt32
  e : UInt32
  f : UInt32
  g : UInt32
  h : UInt32

private def compressRounds (schedule : Array UInt32) :
    Nat → Nat → CompressionRegisters → CompressionRegisters
  | 0, _, registers => registers
  | count + 1, index, registers =>
      let temp1 := registers.h + bigSigma1 registers.e +
        choose registers.e registers.f registers.g + roundConstants[index]! +
        schedule[index]!
      let temp2 := bigSigma0 registers.a +
        majority registers.a registers.b registers.c
      compressRounds schedule count (index + 1) {
        a := temp1 + temp2
        b := registers.a
        c := registers.b
        d := registers.c
        e := registers.d + temp1
        f := registers.e
        g := registers.f
        h := registers.g
      }

private def compress (state : Array UInt32) (schedule : Array UInt32) : Array UInt32 :=
  let registers := compressRounds schedule 64 0 {
    a := state[0]!
    b := state[1]!
    c := state[2]!
    d := state[3]!
    e := state[4]!
    f := state[5]!
    g := state[6]!
    h := state[7]!
  }
  #[
    state[0]! + registers.a, state[1]! + registers.b,
    state[2]! + registers.c, state[3]! + registers.d,
    state[4]! + registers.e, state[5]! + registers.f,
    state[6]! + registers.g, state[7]! + registers.h
  ]

private def appendUInt32BE (bytes : ByteArray) (value : UInt32) : ByteArray :=
  bytes
    |>.push (UInt32.shiftRight value 24).toUInt8
    |>.push (UInt32.shiftRight value 16).toUInt8
    |>.push (UInt32.shiftRight value 8).toUInt8
    |>.push value.toUInt8

/-- Public proof boundary for the eight SHA-256 chaining words. -/
abbrev Sha256State := Array UInt32

/-- Initial SHA-256 chaining state used by production hashing and block
    certificates. -/
def sha256InitialState : Sha256State :=
  initialState

/-- FIPS 180-4 padding used by production hashing and block certificates. -/
def sha256PaddedBytes (input : ByteArray) : ByteArray :=
  pad input

/-- One production SHA-256 compression transition over the 64-byte block at
    `offset`. Certificate states never carry or copy the input block. -/
def sha256CompressBlockAt (bytes : ByteArray) (offset : Nat)
    (state : Sha256State) : Sha256State :=
  compress state (scheduleFor bytes offset)

/-- Encode one final eight-word chaining state as the raw 32-byte digest. -/
def sha256StateDigest (state : Sha256State) : ByteArray :=
  appendUInt32BE
    (appendUInt32BE
      (appendUInt32BE
        (appendUInt32BE
          (appendUInt32BE
            (appendUInt32BE
              (appendUInt32BE
                (appendUInt32BE ByteArray.empty state[0]!) state[1]!)
              state[2]!)
            state[3]!)
          state[4]!)
        state[5]!)
      state[6]!)
    state[7]!

/-- SHA-256's production state renderer always emits eight 32-bit words. -/
theorem sha256StateDigest_size (state : Sha256State) :
    (sha256StateDigest state).size = 32 := by
  simp [sha256StateDigest, appendUInt32BE]

private def compressChunks (bytes : ByteArray) :
    Nat → Nat → Sha256State → Sha256State
  | 0, _, state => state
  | count + 1, offset, state =>
      compressChunks bytes count (offset + 64)
        (sha256CompressBlockAt bytes offset state)

/-- Pure SHA-256 over bytes. This implementation performs no IO and has no
    toolchain dependency. -/
def sha256 (input : ByteArray) : ByteArray :=
  let padded := sha256PaddedBytes input
  let state := compressChunks padded (padded.size / 64) 0 sha256InitialState
  sha256StateDigest state

/-- Production SHA-256 always returns the fixed 32-byte digest width. -/
theorem sha256_size (input : ByteArray) : (sha256 input).size = 32 := by
  simp only [sha256, sha256StateDigest_size]

private def hexDigit (value : Nat) : Char :=
  if value < 10 then Char.ofNat (48 + value) else Char.ofNat (87 + value)

/-- Lower-case hexadecimal SHA-256 digest over bytes. -/
private def bytesToHex (bytes : ByteArray) : Nat → Nat → String → String
  | 0, _, output => output
  | count + 1, index, output =>
      let byte := bytes[index]!
      bytesToHex bytes count (index + 1) <|
        output.push (hexDigit (byte.toNat / 16))
          |>.push (hexDigit (byte.toNat % 16))

/-- Canonical lower-case hexadecimal rendering of a raw 32-byte SHA-256
    digest. This is shared by production hashing and kernel certificates. -/
def sha256DigestHex (digest : ByteArray) : String :=
  bytesToHex digest 32 0 ""

def sha256Hex (input : ByteArray) : String :=
  sha256DigestHex (sha256 input)

/-- Proof-carrying bytes-to-SHA-256 identity. The raw digest equation keeps
    expensive block compression separate from the cheap canonical rendering
    equation while both refer to the sole production SHA implementation. -/
structure Sha256HexCertificate (input : ByteArray) (expectedHex : String) where
  digest : ByteArray
  digest_eq : sha256 input = digest
  hex_eq : sha256DigestHex digest = expectedHex

/-- A SHA-256 certificate proves the exact production `sha256Hex` equation;
    it is not a runtime Boolean or a second hash implementation. -/
theorem Sha256HexCertificate.sound
    (certificate : Sha256HexCertificate input expectedHex) :
    sha256Hex input = expectedHex := by
  rw [sha256Hex, certificate.digest_eq, certificate.hex_eq]

/-- Kernel proof chain for a sequence of exact production compression steps.
    The bytes are a parameter, so a certificate cannot substitute copied blocks
    for emitter-owned input. -/
inductive Sha256BlockTrace (bytes : ByteArray) :
    Nat → Nat → Sha256State → Sha256State → Prop where
  | done (offset state) : Sha256BlockTrace bytes 0 offset state state
  | step (count offset state nextState finalState)
      (transition :
        sha256CompressBlockAt bytes offset state = nextState)
      (remaining : Sha256BlockTrace bytes count (offset + 64)
        nextState finalState) :
      Sha256BlockTrace bytes (count + 1) offset state finalState

/-- A block trace is extensionally equal to the recursive production
    compressor. -/
theorem Sha256BlockTrace.sound
    (trace : Sha256BlockTrace bytes count offset state finalState) :
    compressChunks bytes count offset state = finalState := by
  induction trace with
  | done => rfl
  | step _ _ _ _ _ transition _ inductionHypothesis =>
      simp only [compressChunks]
      rw [transition]
      exact inductionHypothesis

/-- Scalable SHA-256 certificate: one kernel-checkable transition per block,
    followed by the canonical digest rendering equation. -/
structure Sha256BlockCertificate (input : ByteArray) (expectedHex : String) where
  finalState : Sha256State
  trace : Sha256BlockTrace (sha256PaddedBytes input)
    ((sha256PaddedBytes input).size / 64) 0 sha256InitialState finalState
  hex_eq : sha256DigestHex (sha256StateDigest finalState) = expectedHex

/-- Convert a block certificate into the common raw-digest certificate. -/
def Sha256BlockCertificate.toHexCertificate
    (certificate : Sha256BlockCertificate input expectedHex) :
    Sha256HexCertificate input expectedHex := {
  digest := sha256StateDigest certificate.finalState
  digest_eq := by
    unfold sha256
    exact congrArg sha256StateDigest certificate.trace.sound
  hex_eq := certificate.hex_eq
}

theorem Sha256BlockCertificate.sound
    (certificate : Sha256BlockCertificate input expectedHex) :
    sha256Hex input = expectedHex :=
  certificate.toHexCertificate.sound

end ProofForgeV2.Crypto
