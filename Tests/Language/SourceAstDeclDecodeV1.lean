import ProofForgeV2.Source.AstDeclCodecV1
import ProofForgeV2.Source.AstDeclDecodeV1
import ProofForgeV2.Source.AstDeclV1
import ProofForgeV2.Source.AstSupportV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.DecodeBudgetV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.QualifiedNameV1
import ProofForgeV2.Source.WireDecodeV1

namespace Tests.Language.SourceAstDeclDecodeV1
open ProofForgeV2.Source.AstDeclCodecV1
open ProofForgeV2.Source.AstDeclDecodeV1
open ProofForgeV2.Source.AstDeclV1
open ProofForgeV2.Source.AstSupportV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.DecodeBudgetV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.QualifiedNameV1
open ProofForgeV2.Source.WireDecodeV1

private def expect (c : Bool) (m : String) : IO Unit := unless c do throw <| IO.userError m
private def lift (lab : String) (r : Except String α) : IO α :=
  match r with | .ok v => pure v | .error e => throw <| IO.userError s!"{lab}: {e}"
private def err (lab want : String) (r : Except String α) : IO Unit :=
  match r with
  | .error e => expect (e == want) s!"{lab}: want {want}, got {e}"
  | .ok _ => throw <| IO.userError s!"{lab}: unexpectedly ok"
private def hv (c : Char) : Nat := if c ≤ '9' then c.toNat - '0'.toNat else c.toNat - 'a'.toNat + 10
private def hex (s : String) : ByteArray := Id.run do
  let cs := s.toList.toArray; let mut b := ByteArray.empty; let mut i := 0
  while i + 1 < cs.size do
    b := b.push (UInt8.ofNat (hv cs[i]! * 16 + hv cs[i + 1]!)); i := i + 2
  pure b
private def hx (b : ByteArray) : String :=
  b.foldl (fun s x =>
    let d (n : Nat) := Char.ofNat (if n < 10 then '0'.toNat + n else 'a'.toNat + n - 10)
    (s.push (d (x.toNat / 16))).push (d (x.toNat % 16))) ""
private def u16 (n : Nat) := ByteArray.mk #[UInt8.ofNat n, UInt8.ofNat (n / 256)]
private def u32 (n : Nat) :=
  ByteArray.mk #[UInt8.ofNat n, UInt8.ofNat (n / 256), UInt8.ofNat (n / 65536), UInt8.ofNat (n / 16777216)]
private def sbytes (s : String) := u32 s.utf8ByteSize ++ s.toUTF8
private def tg (s : String) (fs : Array ByteArray) :=
  sbytes s ++ u16 fs.size ++ fs.foldl (· ++ ·) ByteArray.empty
private def ident := sbytes
private def ty (s : String) (fs := #[]) := tg ("Type." ++ s) fs
private def vis (s : String) := tg ("Visibility." ++ s) #[]
private def fw (n : String) (t : ByteArray) := tg "FieldDecl" #[ident n, t]
private def vw (n : String) (ts : Array ByteArray) :=
  tg "EnumVariant" #[ident n, u32 ts.size ++ ts.foldl (· ++ ·) ByteArray.empty]
private def pw (v n : String) (t : ByteArray) := tg "Param" #[vis v, ident n, t]
private def bud (n : Nat) : DecodeBudgetV1 := { remainingNodes := n }
private def setFc (b : ByteArray) (n : Nat) : ByteArray :=
  let o := 4 + (b.get! 0).toNat
  (b.set! o (UInt8.ofNat n)).set! (o + 1) (UInt8.ofNat (n / 256))
private def noFc (b : ByteArray) := b.extract 0 (b.size - 2)
private def nm (s : String) : IO SourceNameComponentV1 := lift "name" (parseSourceNameComponentV1 s)
private def qn (ps : Array String) : IO SourceQualifiedNameV1 :=
  lift "qn" (parseSourceQualifiedNameV1 ps)
private def qidBytes (ps : Array String) : ByteArray :=
  u32 ps.size ++ ps.foldl (fun acc p => acc ++ ident p) ByteArray.empty
private def dState (d n : Nat) (b : ByteArray) := decodeStateDeclV1 d (bud n) (start b)
private def dStruct (d n : Nat) (b : ByteArray) := decodeStructDeclV1 d (bud n) (start b)
private def dEnum (d n : Nat) (b : ByteArray) := decodeEnumDeclV1 d (bud n) (start b)
private def dEvent (d n : Nat) (b : ByteArray) := decodeEventDeclV1 d (bud n) (start b)
private def dError (d n : Nat) (b : ByteArray) := decodeErrorDeclV1 d (bud n) (start b)
private def dExt (d n : Nat) (b : ByteArray) := decodeExtensionReqV1 d (bud n) (start b)
private def dProof (d n : Nat) (b : ByteArray) := decodeProofDeclV1 d (bud n) (start b)

private def rtState (h : String) (w : StateDeclV1) (spent : Nat) : IO Unit := do
  let ((g, r), c) ← lift "S" (dState 256 100 (hex h))
  expect (decide (g = w) && r.remainingNodes == 100 - spent) "state"
  lift "Sf" (finish c); expect (hx (← lift "Se" (encodeStateDeclV1 g)) == h) "state wire"
private def rtStruct (h : String) (w : StructDeclV1) (spent : Nat) : IO Unit := do
  let ((g, r), c) ← lift "U" (dStruct 256 100 (hex h))
  expect (decide (g = w) && r.remainingNodes == 100 - spent) "struct"
  lift "Uf" (finish c); expect (hx (← lift "Ue" (encodeStructDeclV1 g)) == h) "struct wire"
private def rtEnum (h : String) (w : EnumDeclV1) (spent : Nat) : IO Unit := do
  let ((g, r), c) ← lift "E" (dEnum 256 100 (hex h))
  expect (decide (g = w) && r.remainingNodes == 100 - spent) "enum"
  lift "Ef" (finish c); expect (hx (← lift "Ee" (encodeEnumDeclV1 g)) == h) "enum wire"
private def rtEvent (h : String) (w : EventDeclV1) (spent : Nat) : IO Unit := do
  let ((g, r), c) ← lift "V" (dEvent 256 100 (hex h))
  expect (decide (g = w) && r.remainingNodes == 100 - spent) "event"
  lift "Vf" (finish c); expect (hx (← lift "Ve" (encodeEventDeclV1 g)) == h) "event wire"
private def rtError (h : String) (w : ErrorDeclV1) (spent : Nat) : IO Unit := do
  let ((g, r), c) ← lift "R" (dError 256 100 (hex h))
  expect (decide (g = w) && r.remainingNodes == 100 - spent) "error"
  lift "Rf" (finish c); expect (hx (← lift "Re" (encodeErrorDeclV1 g)) == h) "error wire"
private def rtExt (h : String) (w : ExtensionReqV1) (spent : Nat) : IO Unit := do
  let ((g, r), c) ← lift "X" (dExt 256 100 (hex h))
  expect (decide (g = w) && r.remainingNodes == 100 - spent) "ext"
  lift "Xf" (finish c); expect (hx (← lift "Xe" (encodeExtensionReqV1 g)) == h) "ext wire"
private def rtProof (h : String) (w : ProofDeclV1) (spent : Nat) : IO Unit := do
  let ((g, r), c) ← lift "P" (dProof 256 100 (hex h))
  expect (decide (g = w) && r.remainingNodes == 100 - spent) "proof"
  lift "Pf" (finish c); expect (hx (← lift "Pe" (encodeProofDeclV1 g)) == h) "proof wire"

/-- Frozen D1-PA-112: 14 PA98 literals, 14 FC, 42 boundaries. -/
def run : IO Unit := do
  let enabled ← nm "enabled"; let count ← nm "count"; let secret ← nm "secret"
  let store ← nm "Store"; let items ← nm "items"; let choice ← nm "Choice"
  let noneN ← nm "None"; let someN ← nm "Some"; let ping ← nm "Ping"
  let transfer ← nm "Transfer"; let from_ ← nm "from"; let amount ← nm "amount"
  let note ← nm "note"; let emptyE ← nm "Empty"; let denied ← nm "Denied"
  let reason ← nm "reason"; let safe ← nm "safe"
  let demoFeature ← qn #["Demo", "Feature"]
  let demoAdvanced ← qn #["Demo", "Advanced"]
  let proofsSafe ← qn #["Proofs", "safe"]
  let dig00 := "sha256:0000000000000000000000000000000000000000000000000000000000000000"
  let digab := "sha256:abababababababababababababababababababababababababababababababab"
  let fdCount : FieldDeclV1 := { name := count, type_ := .uint 256 }
  let fdItems : FieldDeclV1 := { name := items, type_ := .map .bool .unit }
  let varNone : EnumVariantV1 := { name := noneN, payloadTypes := #[] }
  let varSome : EnumVariantV1 := { name := someN, payloadTypes := #[.bool, .principal] }
  let pFrom : ParamV1 := { visibility := .public_, name := from_, type_ := .principal }
  let pAmount : ParamV1 := { visibility := .private_, name := amount, type_ := .uint 64 }
  let pNote : ParamV1 := { visibility := .commitment, name := note, type_ := .bytes 0 }
  let pReason : ParamV1 := { visibility := .public_, name := reason, type_ := .bool }
  -- 14 positives
  rtState "0900000053746174654465636c0300110000005669736962696c6974792e5075626c6963000007000000656e61626c656409000000547970652e426f6f6c0000"
    { visibility := .public_, name := enabled, type_ := .bool } 2
  rtState "0900000053746174654465636c0300120000005669736962696c6974792e50726976617465000005000000636f756e7409000000547970652e55496e7401004000"
    { visibility := .private_, name := count, type_ := .uint 64 } 2
  rtState "0900000053746174654465636c0300150000005669736962696c6974792e436f6d6d69746d656e740000060000007365637265740a000000547970652e417272617902000b000000547970652e4f7074696f6e01000a000000547970652e427974657301000000000000000000"
    { visibility := .commitment, name := secret, type_ := .array (.option (.bytes 0)) 0 } 4
  rtStruct "0a0000005374727563744465636c02000500000053746f726502000000090000004669656c644465636c020005000000636f756e7409000000547970652e55496e7401000001090000004669656c644465636c0200050000006974656d7308000000547970652e4d6170020009000000547970652e426f6f6c000009000000547970652e556e69740000"
    { name := store, fields := #[fdCount, fdItems] } 7
  rtStruct "0a0000005374727563744465636c02000500000053746f726501000000090000004669656c644465636c020005000000636f756e7409000000547970652e55496e7401000001"
    { name := store, fields := #[fdCount] } 3
  rtStruct "0a0000005374727563744465636c02000500000053746f726502000000090000004669656c644465636c0200050000006974656d7308000000547970652e4d6170020009000000547970652e426f6f6c000009000000547970652e556e69740000090000004669656c644465636c020005000000636f756e7409000000547970652e55496e7401000001"
    { name := store, fields := #[fdItems, fdCount] } 7
  rtEnum "08000000456e756d4465636c02000600000043686f696365020000000b000000456e756d56617269616e740200040000004e6f6e65000000000b000000456e756d56617269616e74020004000000536f6d650200000009000000547970652e426f6f6c00000e000000547970652e5072696e636970616c0000"
    { name := choice, variants := #[varNone, varSome] } 5
  rtEvent "090000004576656e744465636c02000400000050696e6700000000" { name := ping, params := #[] } 1
  rtEvent "090000004576656e744465636c0200080000005472616e736665720300000005000000506172616d0300110000005669736962696c6974792e5075626c696300000400000066726f6d0e000000547970652e5072696e636970616c000005000000506172616d0300120000005669736962696c6974792e50726976617465000006000000616d6f756e7409000000547970652e55496e740100400005000000506172616d0300150000005669736962696c6974792e436f6d6d69746d656e740000040000006e6f74650a000000547970652e4279746573010000000000"
    { name := transfer, params := #[pFrom, pAmount, pNote] } 7
  rtError "090000004572726f724465636c020005000000456d70747900000000" { name := emptyE, params := #[] } 1
  rtError "090000004572726f724465636c02000600000044656e6965640100000005000000506172616d0300110000005669736962696c6974792e5075626c6963000006000000726561736f6e09000000547970652e426f6f6c0000"
    { name := denied, params := #[pReason] } 3
  rtExt "0c000000457874656e73696f6e5265710300020000000400000044656d6f070000004665617475726505000000312e302e30470000007368613235363a30303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030"
    { id := demoFeature, version := "1.0.0", digest := dig00 } 1
  rtExt "0c000000457874656e73696f6e5265710300020000000400000044656d6f08000000416476616e63656415000000312e322e332d616c7068612e312b6275696c642e35470000007368613235363a61626162616261626162616261626162616261626162616261626162616261626162616261626162616261626162616261626162616261626162616261626162"
    { id := demoAdvanced, version := "1.2.3-alpha.1+build.5", digest := digab } 1
  rtProof "0900000050726f6f664465636c030004000000736166650f00000050726f6f664b696e642e486f6c64730000020000000600000050726f6f66730400000073616665"
    { invariant := safe, kind := .holds, theorem_ := proofsSafe } 1
  rtProof "0900000050726f6f664465636c030004000000736166651400000050726f6f664b696e642e50726573657276696e670000020000000600000050726f6f66730400000073616665"
    { invariant := safe, kind := .preserving, theorem_ := proofsSafe } 1
  -- 14 FC at zero budgets
  let hState := hex "0900000053746174654465636c0300110000005669736962696c6974792e5075626c6963000007000000656e61626c656409000000547970652e426f6f6c0000"
  let hStruct := hex "0a0000005374727563744465636c02000500000053746f726501000000090000004669656c644465636c020005000000636f756e7409000000547970652e55496e7401000001"
  let hEnum := hex "08000000456e756d4465636c02000600000043686f696365020000000b000000456e756d56617269616e740200040000004e6f6e65000000000b000000456e756d56617269616e74020004000000536f6d650200000009000000547970652e426f6f6c00000e000000547970652e5072696e636970616c0000"
  let hEvent := hex "090000004576656e744465636c02000400000050696e6700000000"
  let hError := hex "090000004572726f724465636c020005000000456d70747900000000"
  let hExt := hex "0c000000457874656e73696f6e5265710300020000000400000044656d6f070000004665617475726505000000312e302e30470000007368613235363a30303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030"
  let hProof := hex "0900000050726f6f664465636c030004000000736166650f00000050726f6f664b696e642e486f6c64730000020000000600000050726f6f66730400000073616665"
  for bad in ([2, 4] : List Nat) do
    err "fcS" "tag 'StateDecl' must declare 3 fields" (dState 0 0 (setFc hState bad))
    err "fcP" "tag 'ProofDecl' must declare 3 fields" (dProof 0 0 (setFc hProof bad))
  for bad in ([1, 3] : List Nat) do
    err "fcU" "tag 'StructDecl' must declare 2 fields" (dStruct 0 0 (setFc hStruct bad))
    err "fcN" "tag 'EnumDecl' must declare 2 fields" (dEnum 0 0 (setFc hEnum bad))
    err "fcV" "tag 'EventDecl' must declare 2 fields" (dEvent 0 0 (setFc hEvent bad))
    err "fcR" "tag 'ErrorDecl' must declare 2 fields" (dError 0 0 (setFc hError bad))
  for bad in ([2, 4] : List Nat) do
    err "fcX" "tag 'ExtensionReq' must declare 3 fields" (dExt 0 0 (setFc hExt bad))
  -- 42 boundaries (seven distinct declaration sibling tags for wrong-family)
  err "wf1" "unknown state-decl tag 'StructDecl'" (dState 0 0 (noFc (tg "StructDecl" #[])))
  err "wf2" "unknown struct-decl tag 'EnumDecl'" (dStruct 0 0 (noFc (tg "EnumDecl" #[])))
  err "wf3" "unknown enum-decl tag 'EventDecl'" (dEnum 0 0 (noFc (tg "EventDecl" #[])))
  err "wf4" "unknown event-decl tag 'ErrorDecl'" (dEvent 0 0 (noFc (tg "ErrorDecl" #[])))
  err "wf5" "unknown error-decl tag 'ExtensionReq'" (dError 0 0 (noFc (tg "ExtensionReq" #[])))
  err "wf6" "unknown extension-req tag 'ProofDecl'" (dExt 0 0 (noFc (tg "ProofDecl" #[])))
  err "wf7" "unknown proof-decl tag 'StateDecl'" (dProof 0 0 (noFc (tg "StateDecl" #[])))
  err "depth" "depth budget exhausted" (dState 0 0 hState)
  err "nS" "node budget exhausted" (dState 1 0 (tg "StateDecl" #[ByteArray.empty, ByteArray.empty, ByteArray.empty]))
  err "nU" "node budget exhausted" (dStruct 1 0 (tg "StructDecl" #[ByteArray.empty, ByteArray.empty]))
  err "nN" "node budget exhausted" (dEnum 1 0 (tg "EnumDecl" #[ByteArray.empty, ByteArray.empty]))
  err "nV" "node budget exhausted" (dEvent 1 0 (tg "EventDecl" #[ByteArray.empty, ByteArray.empty]))
  err "nR" "node budget exhausted" (dError 1 0 (tg "ErrorDecl" #[ByteArray.empty, ByteArray.empty]))
  err "nX" "node budget exhausted" (dExt 1 0 (tg "ExtensionReq" #[ByteArray.empty, ByteArray.empty, ByteArray.empty]))
  err "nP" "node budget exhausted" (dProof 1 0 (tg "ProofDecl" #[ByteArray.empty, ByteArray.empty, ByteArray.empty]))
  -- State order + type pass-through (A-before-B dual-fault)
  err "s-vis" "unknown visibility tag 'Type.Bool'"
    (dState 3 8 (tg "StateDecl" #[ty "Bool", u32 0, tg "Bogus" #[]]))
  err "s-name" "source name component must contain 1..240 UTF-8 bytes"
    (dState 3 8 (tg "StateDecl" #[vis "Public", u32 0, tg "Bogus" #[]]))
  err "s-type" "integer width must be one of 8,16,32,64,128,256"
    (dState 3 4 (tg "StateDecl" #[vis "Public", ident "x", ty "UInt" #[u16 24]]))
  -- Struct
  err "u-name" "source name component must contain 1..240 UTF-8 bytes"
    (dStruct 3 8 (tg "StructDecl" #[u32 0, u32 99 ++ ByteArray.empty]))
  err "u-empty" "struct fields must be nonempty"
    (dStruct 2 4 (tg "StructDecl" #[ident "Store", u32 0]))
  err "u-count" "array count exceeds caller limit"
    (dStruct 3 2 (tg "StructDecl" #[ident "Store", u32 2 ++ fw "a" (ty "Bool") ++ fw "b" (ty "Bool")]))
  err "u-child" "integer width must be one of 8,16,32,64,128,256"
    (dStruct 3 8 (tg "StructDecl" #[ident "Store", u32 1 ++ fw "c" (ty "UInt" #[u16 24])]))
  err "u-sib" "node budget exhausted"
    (dStruct 4 4 (tg "StructDecl" #[ident "Store", u32 2 ++ fw "a" (ty "Option" #[ty "Bool"]) ++ fw "b" (ty "Unit")]))
  -- Enum
  err "e-name" "source name component must contain 1..240 UTF-8 bytes"
    (dEnum 3 8 (tg "EnumDecl" #[u32 0, u32 99]))
  err "e-empty" "enum variants must be nonempty"
    (dEnum 2 4 (tg "EnumDecl" #[ident "Choice", u32 0]))
  err "e-count" "array count exceeds caller limit"
    (dEnum 3 2 (tg "EnumDecl" #[ident "Choice", u32 2 ++ vw "A" #[] ++ vw "B" #[]]))
  err "e-child" "unknown type tag 'Visibility.Public'"
    (dEnum 3 8 (tg "EnumDecl" #[ident "Choice", u32 1 ++ vw "X" #[noFc (vis "Public")]]))
  err "e-sib" "node budget exhausted"
    (dEnum 3 3 (tg "EnumDecl" #[ident "Choice", u32 2 ++ vw "A" #[ty "Bool"] ++ vw "B" #[ty "Unit"]]))
  -- Event
  err "v-name" "source name component must contain 1..240 UTF-8 bytes"
    (dEvent 3 8 (tg "EventDecl" #[u32 0, u32 99]))
  err "v-count" "array count exceeds caller limit"
    (dEvent 3 2 (tg "EventDecl" #[ident "Ping", u32 2 ++ pw "Public" "a" (ty "Bool") ++ pw "Public" "b" (ty "Unit")]))
  err "v-param" "unknown visibility tag 'Type.Bool'"
    (dEvent 3 8 (tg "EventDecl" #[ident "Ping", u32 1 ++ tg "Param" #[ty "Bool", ident "x", ty "Unit"]]))
  err "v-sib" "node budget exhausted"
    (dEvent 4 4 (tg "EventDecl" #[ident "Ping", u32 2 ++ pw "Public" "a" (ty "Option" #[ty "Bool"]) ++ pw "Public" "b" (ty "Unit")]))
  -- Error
  err "r-name" "source name component must contain 1..240 UTF-8 bytes"
    (dError 3 8 (tg "ErrorDecl" #[u32 0, u32 99]))
  err "r-count" "array count exceeds caller limit"
    (dError 3 2 (tg "ErrorDecl" #[ident "Empty", u32 2 ++ pw "Public" "a" (ty "Bool") ++ pw "Public" "b" (ty "Unit")]))
  err "r-param" "unknown visibility tag 'Type.Bool'"
    (dError 3 8 (tg "ErrorDecl" #[ident "Empty", u32 1 ++ tg "Param" #[ty "Bool", ident "x", ty "Unit"]]))
  err "r-sib" "node budget exhausted"
    (dError 4 4 (tg "ErrorDecl" #[ident "Empty", u32 2 ++ pw "Public" "a" (ty "Option" #[ty "Bool"]) ++ pw "Public" "b" (ty "Unit")]))
  -- Extension: QID before hostile version/digest; version before digest
  err "x-qid" "source qualified id must contain 2..256 components"
    (dExt 2 4 (tg "ExtensionReq" #[u32 1 ++ ident "Only", sbytes "not-a-semver", sbytes "bad"]))
  err "x-ver" "extension version must use canonical exact SemVer"
    (dExt 2 4 (tg "ExtensionReq" #[qidBytes #["Demo", "Feature"], sbytes "01.0.0", sbytes "bad"]))
  err "x-dig" "extension digest must use canonical sha256 spelling"
    (dExt 2 4 (tg "ExtensionReq" #[qidBytes #["Demo", "Feature"], sbytes "1.0.0", sbytes "sha256:ZZ"]))
  -- Proof
  err "p-inv" "source name component must contain 1..240 UTF-8 bytes"
    (dProof 2 4 (tg "ProofDecl" #[u32 0, tg "ProofKind.Holds" #[], u32 1 ++ ident "Only"]))
  err "p-qid" "source qualified id must contain 2..256 components"
    (dProof 2 4 (tg "ProofDecl" #[ident "safe", tg "ProofKind.Holds" #[], u32 1 ++ ident "Only"]))
  err "p-kind" "unknown proof-kind tag 'ProofKind.Bogus'"
    (dProof 2 4 (tg "ProofDecl" #[ident "safe", tg "ProofKind.Bogus" #[],
      u32 2 ++ ident "Proofs" ++ ident "safe"]))
  err "p-kind-fc" "tag 'ProofKind.Holds' must declare 0 fields"
    (dProof 2 4 (tg "ProofDecl" #[ident "safe", tg "ProofKind.Holds" #[ByteArray.mk #[0]],
      u32 2 ++ ident "Proofs" ++ ident "safe"]))
  err "p-two-field" "tag 'ProofDecl' must declare 3 fields"
    (dProof 2 4 (tg "ProofDecl" #[ident "safe", u32 2 ++ ident "Proofs" ++ ident "safe"]))
  err "trail" "trailing bytes" (do
    let ((_g, _), c) ← dState 3 4 (hex ("0900000053746174654465636c0300110000005669736962696c6974792e5075626c6963000007000000656e61626c656409000000547970652e426f6f6c0000" ++ "00"))
    finish c)

end Tests.Language.SourceAstDeclDecodeV1
