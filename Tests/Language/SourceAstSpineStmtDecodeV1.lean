import ProofForgeV2.Source.AstCodecV1
import ProofForgeV2.Source.AstPatternV1
import ProofForgeV2.Source.AstSpineCodecV1
import ProofForgeV2.Source.AstSpineEqV1
import ProofForgeV2.Source.AstSpineStmtDecodeV1
import ProofForgeV2.Source.AstSpineV1
import ProofForgeV2.Source.AstV1
import ProofForgeV2.Source.DecodeBudgetV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.QualifiedNameV1
import ProofForgeV2.Source.WireCodecV1
import ProofForgeV2.Source.WireDecodeV1

namespace Tests.Language.SourceAstSpineStmtDecodeV1

set_option maxRecDepth 4096

open ProofForgeV2.Source.AstCodecV1
open ProofForgeV2.Source.AstPatternV1
open ProofForgeV2.Source.AstSpineCodecV1
open ProofForgeV2.Source.AstSpineStmtDecodeV1
open ProofForgeV2.Source.AstSpineV1
open ProofForgeV2.Source.AstV1
open ProofForgeV2.Source.DecodeBudgetV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.QualifiedNameV1
open ProofForgeV2.Source.WireCodecV1
open ProofForgeV2.Source.WireDecodeV1

private def expect (c : Bool) (m : String) : IO Unit := unless c do throw <| IO.userError m
private def lift (lab : String) (r : Except String α) : IO α :=
  match r with | .ok v => pure v | .error e => throw <| IO.userError s!"{lab}: {e}"
private def err (lab want : String) (r : Except String α) : IO Unit :=
  match r with
  | .error e => expect (e == want) s!"{lab}: want {want}, got {e}"
  | .ok _ => throw <| IO.userError s!"{lab}: unexpectedly ok"
private def hv (c : Char) : Nat := if c ≤ '9' then c.toNat-'0'.toNat else c.toNat-'a'.toNat+10
private def hex (s : String) : ByteArray := Id.run do
  let cs:=s.toList.toArray; let mut b:=ByteArray.empty; let mut i:=0
  while i+1<cs.size do
    b:=b.push (UInt8.ofNat (hv cs[i]!*16+hv cs[i+1]!))
    i:=i+2
  pure b
private def hx (b : ByteArray) : String := b.foldl (fun s x =>
  let d (n:Nat):=Char.ofNat (if n<10 then '0'.toNat+n else 'a'.toNat+n-10)
  (s.push (d (x.toNat/16))).push (d (x.toNat%16))) ""
private def u16 (n:Nat):=ByteArray.mk #[UInt8.ofNat n, UInt8.ofNat (n/256)]
private def u32 (n:Nat):=ByteArray.mk #[UInt8.ofNat n,UInt8.ofNat (n/256),UInt8.ofNat (n/65536),UInt8.ofNat (n/16777216)]
private def sbytes (s:String):=u32 s.utf8ByteSize ++ s.toUTF8
private def tg (s:String) (fs:Array ByteArray):=sbytes s ++ u16 fs.size ++ fs.foldl (·++·) ByteArray.empty
private def head (s:String) (fc:Nat) (p:ByteArray:=ByteArray.empty):=sbytes s ++ u16 fc ++ p
private def bad (s:String):=sbytes s
private def setFc (b:ByteArray) (n:Nat):ByteArray :=
  let o:=4+(b.get! 0).toNat; (b.set! o (UInt8.ofNat n)).set! (o+1) (UInt8.ofNat (n/256))
private def bud (n:Nat):DecodeBudgetV1:={remainingNodes:=n}
private def nm (s:String):IO SourceNameComponentV1:=lift "n" (parseSourceNameComponentV1 s)
private def qn (ps:Array String):IO SourceQualifiedNameV1:=lift "q" (parseSourceQualifiedNameV1 ps)
private def dS (d n:Nat) (b:ByteArray):=decodeStmtV1 d (bud n) (start b)
private def dB (d n:Nat) (b:ByteArray):=decodeBlockV1 d (bud n) (start b)
private def dA (d n:Nat) (b:ByteArray):=decodeStmtMatchArmV1 d (bud n) (start b)
private def litI (n:Nat):ExprV1:=.literal (.integer n)
private def litB (b:Bool):ExprV1:=.literal (.bool b)
private def nestIf : Nat → StmtV1 → StmtV1
  | 0, base => base
  | n+1, base => .if_ (litB true) { statements := #[nestIf n base] } none

/-- Frozen D1-PA-114: 21 positives, 26 FC, 52 boundaries. -/
def run : IO Unit := do
  let x←nm "x"; let y←nm "y"; let i←nm "i"; let denied←nm "Denied"; let ping←nm "Ping"
  let mathAdd←qn #["Math","add"]
  let L0:ExprV1:=litI 0; let L1:ExprV1:=litI 1; let L4096:ExprV1:=litI 4096; let LT:ExprV1:=litB true
  let pName:PlaceV1:=.name x
  let retNone:StmtV1:=.return_ none; let ret1:StmtV1:=.return_ (some L1)
  let blkRet:BlockV1:={statements:=#[retNone]}; let blkRet1:BlockV1:={statements:=#[ret1]}
  let emitPing:StmtV1:=.emit ping #[]
  let blkMulti:BlockV1:={statements:=#[retNone,emitPing]}
  let blkRev:BlockV1:={statements:=#[emitPing,retNone]}
  let sArmW:StmtMatchArmV1:={pattern:=.wildcard, body:=blkRet}
  let ext0:ExternalCallExprV1:={callee:=mathAdd, args:=#[]}
  let ext1:ExternalCallExprV1:={callee:=mathAdd, args:=#[L1]}
  -- 21 positives
  let ((g,r),c)←lift "stmt_let_none" (dS 256 100 (hex "0800000053746d742e4c657403000100000078000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000"))
  expect (decide (g = .let_ x none L1) && r.remainingNodes == 100 - 2) "stmt_let_none"
  lift "stmt_let_nonef" (finish c); expect (hx (← lift "stmt_let_nonee" (encodeStmtV1 g)) == "0800000053746d742e4c657403000100000078000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000") "stmt_let_none wire"
  let ((g,r),c)←lift "stmt_let_some" (dS 256 100 (hex "0800000053746d742e4c6574030001000000790109000000547970652e426f6f6c00000c000000457870722e4c69746572616c01000c0000004c69746572616c2e426f6f6c010001"))
  expect (decide (g = .let_ y (some .bool) LT) && r.remainingNodes == 100 - 3) "stmt_let_some"
  lift "stmt_let_somef" (finish c); expect (hx (← lift "stmt_let_somee" (encodeStmtV1 g)) == "0800000053746d742e4c6574030001000000790109000000547970652e426f6f6c00000c000000457870722e4c69746572616c01000c0000004c69746572616c2e426f6f6c010001") "stmt_let_some wire"
  let ((g,r),c)←lift "stmt_assign" (dS 256 100 (hex "0b00000053746d742e41737369676e02000a000000506c6163652e4e616d65010001000000780c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000"))
  expect (decide (g = .assign pName L1) && r.remainingNodes == 100 - 3) "stmt_assign"
  lift "stmt_assignf" (finish c); expect (hx (← lift "stmt_assigne" (encodeStmtV1 g)) == "0b00000053746d742e41737369676e02000a000000506c6163652e4e616d65010001000000780c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000") "stmt_assign wire"
  let ((g,r),c)←lift "stmt_if_none" (dS 256 100 (hex "0700000053746d742e496603000c000000457870722e4c69746572616c01000c0000004c69746572616c2e426f6f6c01000105000000426c6f636b0100010000000b00000053746d742e52657475726e01000000"))
  expect (decide (g = .if_ LT blkRet none) && r.remainingNodes == 100 - 4) "stmt_if_none"
  lift "stmt_if_nonef" (finish c); expect (hx (← lift "stmt_if_nonee" (encodeStmtV1 g)) == "0700000053746d742e496603000c000000457870722e4c69746572616c01000c0000004c69746572616c2e426f6f6c01000105000000426c6f636b0100010000000b00000053746d742e52657475726e01000000") "stmt_if_none wire"
  let ((g,r),c)←lift "stmt_if_some" (dS 256 100 (hex "0700000053746d742e496603000c000000457870722e4c69746572616c01000c0000004c69746572616c2e426f6f6c01000105000000426c6f636b0100010000000b00000053746d742e52657475726e0100000105000000426c6f636b0100010000000b00000053746d742e52657475726e0100010c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000"))
  expect (decide (g = .if_ LT blkRet (some blkRet1)) && r.remainingNodes == 100 - 7) "stmt_if_some"
  lift "stmt_if_somef" (finish c); expect (hx (← lift "stmt_if_somee" (encodeStmtV1 g)) == "0700000053746d742e496603000c000000457870722e4c69746572616c01000c0000004c69746572616c2e426f6f6c01000105000000426c6f636b0100010000000b00000053746d742e52657475726e0100000105000000426c6f636b0100010000000b00000053746d742e52657475726e0100010c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000") "stmt_if_some wire"
  let ((g,r),c)←lift "stmt_match" (dS 256 100 (hex "0a00000053746d742e4d6174636802000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000010000000c00000053746d744d6174636841726d0200100000005061747465726e2e57696c6463617264000005000000426c6f636b0100010000000b00000053746d742e52657475726e010000"))
  expect (decide (g = .match_ L1 #[sArmW]) && r.remainingNodes == 100 - 6) "stmt_match"
  lift "stmt_matchf" (finish c); expect (hx (← lift "stmt_matche" (encodeStmtV1 g)) == "0a00000053746d742e4d6174636802000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000010000000c00000053746d744d6174636841726d0200100000005061747465726e2e57696c6463617264000005000000426c6f636b0100010000000b00000053746d742e52657475726e010000") "stmt_match wire"
  let ((g,r),c)←lift "stmt_for_0" (dS 256 100 (hex "0800000053746d742e466f72050001000000690c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e7465676572010000000000000000000000000000000000000000000000000000000000000000000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e7465676572010000100000000000000000000000000000000000000000000000000000000000000000000005000000426c6f636b0100010000000b00000053746d742e52657475726e010000"))
  expect (decide (g = .for_ i L0 L4096 0 blkRet) && r.remainingNodes == 100 - 5) "stmt_for_0"
  lift "stmt_for_0f" (finish c); expect (hx (← lift "stmt_for_0e" (encodeStmtV1 g)) == "0800000053746d742e466f72050001000000690c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e7465676572010000000000000000000000000000000000000000000000000000000000000000000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e7465676572010000100000000000000000000000000000000000000000000000000000000000000000000005000000426c6f636b0100010000000b00000053746d742e52657475726e010000") "stmt_for_0 wire"
  let ((g,r),c)←lift "stmt_for_4096" (dS 256 100 (hex "0800000053746d742e466f72050001000000690c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e7465676572010000000000000000000000000000000000000000000000000000000000000000000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e7465676572010000100000000000000000000000000000000000000000000000000000000000000010000005000000426c6f636b0100010000000b00000053746d742e52657475726e010000"))
  expect (decide (g = .for_ i L0 L4096 4096 blkRet) && r.remainingNodes == 100 - 5) "stmt_for_4096"
  lift "stmt_for_4096f" (finish c); expect (hx (← lift "stmt_for_4096e" (encodeStmtV1 g)) == "0800000053746d742e466f72050001000000690c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e7465676572010000000000000000000000000000000000000000000000000000000000000000000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e7465676572010000100000000000000000000000000000000000000000000000000000000000000010000005000000426c6f636b0100010000000b00000053746d742e52657475726e010000") "stmt_for_4096 wire"
  let ((g,r),c)←lift "stmt_assert_none" (dS 256 100 (hex "0b00000053746d742e41737365727402000c000000457870722e4c69746572616c01000c0000004c69746572616c2e426f6f6c01000100"))
  expect (decide (g = .assert_ LT none) && r.remainingNodes == 100 - 2) "stmt_assert_none"
  lift "stmt_assert_nonef" (finish c); expect (hx (← lift "stmt_assert_nonee" (encodeStmtV1 g)) == "0b00000053746d742e41737365727402000c000000457870722e4c69746572616c01000c0000004c69746572616c2e426f6f6c01000100") "stmt_assert_none wire"
  let ((g,r),c)←lift "stmt_assert_some" (dS 256 100 (hex "0b00000053746d742e41737365727402000c000000457870722e4c69746572616c01000c0000004c69746572616c2e426f6f6c010001010600000044656e696564"))
  expect (decide (g = .assert_ LT (some denied)) && r.remainingNodes == 100 - 2) "stmt_assert_some"
  lift "stmt_assert_somef" (finish c); expect (hx (← lift "stmt_assert_somee" (encodeStmtV1 g)) == "0b00000053746d742e41737365727402000c000000457870722e4c69746572616c01000c0000004c69746572616c2e426f6f6c010001010600000044656e696564") "stmt_assert_some wire"
  let ((g,r),c)←lift "stmt_revert_empty" (dS 256 100 (hex "0b00000053746d742e52657665727402000600000044656e69656400000000"))
  expect (decide (g = .revert denied #[]) && r.remainingNodes == 100 - 1) "stmt_revert_empty"
  lift "stmt_revert_emptyf" (finish c); expect (hx (← lift "stmt_revert_emptye" (encodeStmtV1 g)) == "0b00000053746d742e52657665727402000600000044656e69656400000000") "stmt_revert_empty wire"
  let ((g,r),c)←lift "stmt_revert_one" (dS 256 100 (hex "0b00000053746d742e52657665727402000600000044656e696564010000000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000"))
  expect (decide (g = .revert denied #[L1]) && r.remainingNodes == 100 - 2) "stmt_revert_one"
  lift "stmt_revert_onef" (finish c); expect (hx (← lift "stmt_revert_onee" (encodeStmtV1 g)) == "0b00000053746d742e52657665727402000600000044656e696564010000000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000") "stmt_revert_one wire"
  let ((g,r),c)←lift "stmt_emit" (dS 256 100 (hex "0900000053746d742e456d697402000400000050696e6700000000"))
  expect (decide (g = emitPing) && r.remainingNodes == 100 - 1) "stmt_emit"
  lift "stmt_emitf" (finish c); expect (hx (← lift "stmt_emite" (encodeStmtV1 g)) == "0900000053746d742e456d697402000400000050696e6700000000") "stmt_emit wire"
  let ((g,r),c)←lift "stmt_return_none" (dS 256 100 (hex "0b00000053746d742e52657475726e010000"))
  expect (decide (g = retNone) && r.remainingNodes == 100 - 1) "stmt_return_none"
  lift "stmt_return_nonef" (finish c); expect (hx (← lift "stmt_return_nonee" (encodeStmtV1 g)) == "0b00000053746d742e52657475726e010000") "stmt_return_none wire"
  let ((g,r),c)←lift "stmt_return_1" (dS 256 100 (hex "0b00000053746d742e52657475726e0100010c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000"))
  expect (decide (g = ret1) && r.remainingNodes == 100 - 2) "stmt_return_1"
  lift "stmt_return_1f" (finish c); expect (hx (← lift "stmt_return_1e" (encodeStmtV1 g)) == "0b00000053746d742e52657475726e0100010c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000") "stmt_return_1 wire"
  let ((g,r),c)←lift "stmt_call" (dS 256 100 (hex "0900000053746d742e43616c6c01001000000045787465726e616c43616c6c45787072020002000000040000004d6174680300000061646400000000"))
  expect (decide (g = .call ext0) && r.remainingNodes == 100 - 2) "stmt_call"
  lift "stmt_callf" (finish c); expect (hx (← lift "stmt_calle" (encodeStmtV1 g)) == "0900000053746d742e43616c6c01001000000045787465726e616c43616c6c45787072020002000000040000004d6174680300000061646400000000") "stmt_call wire"
  let ((g,r),c)←lift "stmt_sched" (dS 256 100 (hex "0d00000053746d742e5363686564756c6501001000000045787465726e616c43616c6c45787072020002000000040000004d61746803000000616464010000000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000"))
  expect (decide (g = .schedule ext1) && r.remainingNodes == 100 - 3) "stmt_sched"
  lift "stmt_schedf" (finish c); expect (hx (← lift "stmt_schede" (encodeStmtV1 g)) == "0d00000053746d742e5363686564756c6501001000000045787465726e616c43616c6c45787072020002000000040000004d61746803000000616464010000000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000") "stmt_sched wire"
  let ((g,r),c)←lift "block_single" (dB 256 100 (hex "05000000426c6f636b0100010000000b00000053746d742e52657475726e010000"))
  expect (decide (g = blkRet) && r.remainingNodes == 100 - 2) "block_single"
  lift "block_singlef" (finish c); expect (hx (← lift "block_singlee" (encodeBlockV1 g)) == "05000000426c6f636b0100010000000b00000053746d742e52657475726e010000") "block_single wire"
  let ((g,r),c)←lift "block_multi" (dB 256 100 (hex "05000000426c6f636b0100020000000b00000053746d742e52657475726e0100000900000053746d742e456d697402000400000050696e6700000000"))
  expect (decide (g = blkMulti) && r.remainingNodes == 100 - 3) "block_multi"
  lift "block_multif" (finish c); expect (hx (← lift "block_multie" (encodeBlockV1 g)) == "05000000426c6f636b0100020000000b00000053746d742e52657475726e0100000900000053746d742e456d697402000400000050696e6700000000") "block_multi wire"
  let ((g,r),c)←lift "stmt_arm" (dA 256 100 (hex "0c00000053746d744d6174636841726d0200100000005061747465726e2e57696c6463617264000005000000426c6f636b0100010000000b00000053746d742e52657475726e010000"))
  expect (decide (g = sArmW) && r.remainingNodes == 100 - 4) "stmt_arm"
  lift "stmt_armf" (finish c); expect (hx (← lift "stmt_arme" (encodeStmtMatchArmV1 g)) == "0c00000053746d744d6174636841726d0200100000005061747465726e2e57696c6463617264000005000000426c6f636b0100010000000b00000053746d742e52657475726e010000") "stmt_arm wire"
  let ((g,r),c)←lift "nonalias_blk_er" (dB 256 100 (hex "05000000426c6f636b0100020000000900000053746d742e456d697402000400000050696e67000000000b00000053746d742e52657475726e010000"))
  expect (decide (g = blkRev) && r.remainingNodes == 100 - 3) "nonalias_blk_er"
  lift "nonalias_blk_erf" (finish c); expect (hx (← lift "nonalias_blk_ere" (encodeBlockV1 g)) == "05000000426c6f636b0100020000000900000053746d742e456d697402000400000050696e67000000000b00000053746d742e52657475726e010000") "nonalias_blk_er wire"
  expect (decide (blkMulti ≠ blkRev)) "block nonalias val"
  expect ((← lift "bm" (encodeBlockV1 blkMulti)) ≠ (← lift "br" (encodeBlockV1 blkRev))) "block nonalias bytes"
  -- 26 FC at zero budgets
  err "fc_Stmt.Let_2" "tag 'Stmt.Let' must declare 3 fields" (dS 0 0 (setFc (hex "0800000053746d742e4c657403000100000078000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000") 2))
  err "fc_Stmt.Let_4" "tag 'Stmt.Let' must declare 3 fields" (dS 0 0 (setFc (hex "0800000053746d742e4c657403000100000078000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000") 4))
  err "fc_Stmt.Assign_1" "tag 'Stmt.Assign' must declare 2 fields" (dS 0 0 (setFc (hex "0b00000053746d742e41737369676e02000a000000506c6163652e4e616d65010001000000780c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000") 1))
  err "fc_Stmt.Assign_3" "tag 'Stmt.Assign' must declare 2 fields" (dS 0 0 (setFc (hex "0b00000053746d742e41737369676e02000a000000506c6163652e4e616d65010001000000780c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000") 3))
  err "fc_Stmt.If_2" "tag 'Stmt.If' must declare 3 fields" (dS 0 0 (setFc (hex "0700000053746d742e496603000c000000457870722e4c69746572616c01000c0000004c69746572616c2e426f6f6c01000105000000426c6f636b0100010000000b00000053746d742e52657475726e01000000") 2))
  err "fc_Stmt.If_4" "tag 'Stmt.If' must declare 3 fields" (dS 0 0 (setFc (hex "0700000053746d742e496603000c000000457870722e4c69746572616c01000c0000004c69746572616c2e426f6f6c01000105000000426c6f636b0100010000000b00000053746d742e52657475726e01000000") 4))
  err "fc_Stmt.Match_1" "tag 'Stmt.Match' must declare 2 fields" (dS 0 0 (setFc (hex "0a00000053746d742e4d6174636802000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000010000000c00000053746d744d6174636841726d0200100000005061747465726e2e57696c6463617264000005000000426c6f636b0100010000000b00000053746d742e52657475726e010000") 1))
  err "fc_Stmt.Match_3" "tag 'Stmt.Match' must declare 2 fields" (dS 0 0 (setFc (hex "0a00000053746d742e4d6174636802000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000010000000c00000053746d744d6174636841726d0200100000005061747465726e2e57696c6463617264000005000000426c6f636b0100010000000b00000053746d742e52657475726e010000") 3))
  err "fc_Stmt.For_4" "tag 'Stmt.For' must declare 5 fields" (dS 0 0 (setFc (hex "0800000053746d742e466f72050001000000690c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e7465676572010000000000000000000000000000000000000000000000000000000000000000000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e7465676572010000100000000000000000000000000000000000000000000000000000000000000000000005000000426c6f636b0100010000000b00000053746d742e52657475726e010000") 4))
  err "fc_Stmt.For_6" "tag 'Stmt.For' must declare 5 fields" (dS 0 0 (setFc (hex "0800000053746d742e466f72050001000000690c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e7465676572010000000000000000000000000000000000000000000000000000000000000000000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e7465676572010000100000000000000000000000000000000000000000000000000000000000000000000005000000426c6f636b0100010000000b00000053746d742e52657475726e010000") 6))
  err "fc_Stmt.Assert_1" "tag 'Stmt.Assert' must declare 2 fields" (dS 0 0 (setFc (hex "0b00000053746d742e41737365727402000c000000457870722e4c69746572616c01000c0000004c69746572616c2e426f6f6c01000100") 1))
  err "fc_Stmt.Assert_3" "tag 'Stmt.Assert' must declare 2 fields" (dS 0 0 (setFc (hex "0b00000053746d742e41737365727402000c000000457870722e4c69746572616c01000c0000004c69746572616c2e426f6f6c01000100") 3))
  err "fc_Stmt.Revert_1" "tag 'Stmt.Revert' must declare 2 fields" (dS 0 0 (setFc (hex "0b00000053746d742e52657665727402000600000044656e69656400000000") 1))
  err "fc_Stmt.Revert_3" "tag 'Stmt.Revert' must declare 2 fields" (dS 0 0 (setFc (hex "0b00000053746d742e52657665727402000600000044656e69656400000000") 3))
  err "fc_Stmt.Emit_1" "tag 'Stmt.Emit' must declare 2 fields" (dS 0 0 (setFc (hex "0900000053746d742e456d697402000400000050696e6700000000") 1))
  err "fc_Stmt.Emit_3" "tag 'Stmt.Emit' must declare 2 fields" (dS 0 0 (setFc (hex "0900000053746d742e456d697402000400000050696e6700000000") 3))
  err "fc_Stmt.Return_0" "tag 'Stmt.Return' must declare 1 fields" (dS 0 0 (setFc (hex "0b00000053746d742e52657475726e010000") 0))
  err "fc_Stmt.Return_2" "tag 'Stmt.Return' must declare 1 fields" (dS 0 0 (setFc (hex "0b00000053746d742e52657475726e010000") 2))
  err "fc_Stmt.Call_0" "tag 'Stmt.Call' must declare 1 fields" (dS 0 0 (setFc (hex "0900000053746d742e43616c6c01001000000045787465726e616c43616c6c45787072020002000000040000004d6174680300000061646400000000") 0))
  err "fc_Stmt.Call_2" "tag 'Stmt.Call' must declare 1 fields" (dS 0 0 (setFc (hex "0900000053746d742e43616c6c01001000000045787465726e616c43616c6c45787072020002000000040000004d6174680300000061646400000000") 2))
  err "fc_Stmt.Schedule_0" "tag 'Stmt.Schedule' must declare 1 fields" (dS 0 0 (setFc (hex "0d00000053746d742e5363686564756c6501001000000045787465726e616c43616c6c45787072020002000000040000004d61746803000000616464010000000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000") 0))
  err "fc_Stmt.Schedule_2" "tag 'Stmt.Schedule' must declare 1 fields" (dS 0 0 (setFc (hex "0d00000053746d742e5363686564756c6501001000000045787465726e616c43616c6c45787072020002000000040000004d61746803000000616464010000000c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000") 2))
  err "fc_Block_0" "tag 'Block' must declare 1 fields" (dB 0 0 (setFc (hex "05000000426c6f636b0100010000000b00000053746d742e52657475726e010000") 0))
  err "fc_Block_2" "tag 'Block' must declare 1 fields" (dB 0 0 (setFc (hex "05000000426c6f636b0100010000000b00000053746d742e52657475726e010000") 2))
  err "fc_StmtMatchArm_1" "tag 'StmtMatchArm' must declare 2 fields" (dA 0 0 (setFc (hex "0c00000053746d744d6174636841726d0200100000005061747465726e2e57696c6463617264000005000000426c6f636b0100010000000b00000053746d742e52657475726e010000") 1))
  err "fc_StmtMatchArm_3" "tag 'StmtMatchArm' must declare 2 fields" (dA 0 0 (setFc (hex "0c00000053746d744d6174636841726d0200100000005061747465726e2e57696c6463617264000005000000426c6f636b0100010000000b00000053746d742e52657475726e010000") 3))
  -- 52 boundaries (fixed PA100 checked-in child carriers; no dynamic encode for inputs)
  let eL0 := hex "0c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000000000000000000000000000000000000000000000000000000000000000000"
  let eL1 := hex "0c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000"
  let eLT := hex "0c000000457870722e4c69746572616c01000c0000004c69746572616c2e426f6f6c010001"
  let eLK := hex "0c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000010000000000000000000000000000000000000000000000000000000000000"
  let plX := hex "0a000000506c6163652e4e616d6501000100000078"
  let blk1 := hex "05000000426c6f636b0100010000000b00000053746d742e52657475726e010000"
  let saW := hex "0c00000053746d744d6174636841726d0200100000005061747465726e2e57696c6463617264000005000000426c6f636b0100010000000b00000053746d742e52657475726e010000"
  let pw := hex "100000005061747465726e2e57696c64636172640000"
  let ret0B := hex "0b00000053746d742e52657475726e010000"
  let ret1B := hex "0b00000053746d742e52657475726e0100010c000000457870722e4c69746572616c01000f0000004c69746572616c2e496e746567657201000100000000000000000000000000000000000000000000000000000000000000"
  let id0 := u32 0
  err "b1" "unknown stmt tag 'Block'" (dS 0 0 (bad "Block"))
  err "b2" "unknown block tag 'Stmt.Return'" (dB 0 0 (bad "Stmt.Return"))
  err "b3" "unknown stmt-match-arm tag 'Stmt.Let'" (dA 0 0 (bad "Stmt.Let"))
  err "b4" "depth budget exhausted" (dS 0 0 (head "Stmt.Return" 1))
  err "b5" "node budget exhausted" (dS 1 0 (head "Stmt.Let" 3 id0))
  err "b6" "node budget exhausted" (dB 1 0 (head "Block" 1 (u32 0)))
  err "b7" "node budget exhausted" (dA 1 0 (head "StmtMatchArm" 2 (bad "BogusPattern" ++ bad "BogusBody")))
  err "b8" "source name component must contain 1..240 UTF-8 bytes" (dS 3 8 (tg "Stmt.Let" #[id0, ByteArray.mk #[2], bad "BogusValue"]))
  err "b9" "invalid option marker" (dS 3 8 (tg "Stmt.Let" #[sbytes "x", ByteArray.mk #[2], bad "BogusValue"]))
  err "b10" "unknown type tag 'Expr.Literal'" (dS 3 8 (tg "Stmt.Let" #[sbytes "x", ByteArray.mk #[1] ++ bad "Expr.Literal", bad "BogusValue"]))
  err "b11" "node budget exhausted" (dS 2 2 (hex "0800000053746d742e4c6574030001000000790109000000547970652e426f6f6c00000c000000457870722e4c69746572616c01000c0000004c69746572616c2e426f6f6c010001"))
  err "b12" "unknown place tag 'BogusTarget'" (dS 3 8 (tg "Stmt.Assign" #[bad "BogusTarget", bad "BogusValue"]))
  err "b13" "unknown expr tag 'BogusValue'" (dS 3 8 (tg "Stmt.Assign" #[plX, bad "BogusValue"]))
  err "b14" "unknown expr tag 'BogusCondition'" (dS 4 16 (tg "Stmt.If" #[bad "BogusCondition", bad "BogusThen", ByteArray.mk #[2]]))
  err "b15" "unknown block tag 'BogusThen'" (dS 4 16 (tg "Stmt.If" #[eLT, bad "BogusThen", ByteArray.mk #[2]]))
  err "b16" "invalid option marker" (dS 4 16 (tg "Stmt.If" #[eLT, blk1, ByteArray.mk #[2]]))
  err "b17" "node budget exhausted" (dS 3 4 (tg "Stmt.If" #[eLT, blk1, ByteArray.mk #[1] ++ blk1]))
  err "b18" "unknown expr tag 'BogusScrutinee'" (dS 4 16 (tg "Stmt.Match" #[bad "BogusScrutinee", u32 0]))
  err "b19" "stmt match arms must be nonempty" (dS 4 16 (tg "Stmt.Match" #[eL1, u32 0]))
  err "b20" "array count exceeds caller limit" (dS 4 3 (tg "Stmt.Match" #[eL1, u32 2]))
  err "b21" "unknown stmt-match-arm tag 'BogusArm'" (dS 4 16 (tg "Stmt.Match" #[eL1, u32 1 ++ bad "BogusArm"]))
  err "b22" "node budget exhausted" (dS 4 6 (tg "Stmt.Match" #[eL1, u32 2 ++ saW ++ saW]))
  err "b23" "source name component must contain 1..240 UTF-8 bytes" (dS 4 16 (tg "Stmt.For" #[id0, bad "BogusStart", bad "BogusEnd", u32 4097, bad "BogusBody"]))
  err "b24" "unknown expr tag 'BogusStart'" (dS 4 16 (tg "Stmt.For" #[sbytes "i", bad "BogusStart", bad "BogusEnd", u32 4097, bad "BogusBody"]))
  err "b25" "unknown expr tag 'BogusEnd'" (dS 4 16 (tg "Stmt.For" #[sbytes "i", eL0, bad "BogusEnd", u32 4097, bad "BogusBody"]))
  err "b26" "for bound must be 0..4096" (dS 4 16 (tg "Stmt.For" #[sbytes "i", eL0, eLK, u32 4097, bad "BogusBody"]))
  err "b27" "node budget exhausted" (dS 2 2 (tg "Stmt.For" #[sbytes "i", eL0, eLK, u32 0, blk1]))
  err "b28" "unknown expr tag 'BogusCondition'" (dS 3 8 (tg "Stmt.Assert" #[bad "BogusCondition", ByteArray.mk #[2]]))
  err "b29" "invalid option marker" (dS 3 8 (tg "Stmt.Assert" #[eLT, ByteArray.mk #[2]]))
  err "b30" "source name component must contain 1..240 UTF-8 bytes" (dS 3 8 (tg "Stmt.Assert" #[eLT, ByteArray.mk #[1] ++ id0]))
  err "b31" "source name component must contain 1..240 UTF-8 bytes" (dS 2 8 (tg "Stmt.Revert" #[id0, u32 0xffffffff]))
  err "b32" "array count exceeds caller limit" (dS 2 2 (tg "Stmt.Revert" #[sbytes "Denied", u32 2]))
  err "b33" "unknown expr tag 'BogusArg'" (dS 2 2 (tg "Stmt.Revert" #[sbytes "Denied", u32 1 ++ bad "BogusArg"]))
  err "b34" "source name component must contain 1..240 UTF-8 bytes" (dS 2 8 (tg "Stmt.Emit" #[id0, u32 0xffffffff]))
  err "b35" "array count exceeds caller limit" (dS 2 2 (tg "Stmt.Emit" #[sbytes "Ping", u32 2]))
  err "b36" "unknown expr tag 'BogusArg'" (dS 2 2 (tg "Stmt.Emit" #[sbytes "Ping", u32 1 ++ bad "BogusArg"]))
  err "b37" "invalid option marker" (dS 2 8 (tg "Stmt.Return" #[ByteArray.mk #[2] ++ bad "BogusValue"]))
  err "b38" "node budget exhausted" (dS 2 1 (tg "Stmt.Return" #[ByteArray.mk #[1] ++ eL1]))
  err "b39" "unknown external-call tag 'BogusExternal'" (dS 2 8 (tg "Stmt.Call" #[bad "BogusExternal"]))
  err "b40" "unknown external-call tag 'BogusExternal'" (dS 2 8 (tg "Stmt.Schedule" #[bad "BogusExternal"]))
  err "b41" "block statements must be nonempty" (dB 2 8 (tg "Block" #[u32 0 ++ bad "BogusStmt"]))
  err "b42" "array count exceeds caller limit" (dB 2 2 (tg "Block" #[u32 2]))
  err "b43" "unknown stmt tag 'BogusStmt'" (dB 2 8 (tg "Block" #[u32 1 ++ bad "BogusStmt"]))
  err "b44" "node budget exhausted" (dB 3 3 (tg "Block" #[u32 2 ++ ret1B ++ ret0B]))
  -- b45: fixed test-local wire from PA100 Emit+RevertEmpty child bytes (not encodeBlockV1)
  let raw45 := hex "05000000426c6f636b0100020000000900000053746d742e456d697402000400000050696e67000000000b00000053746d742e52657665727402000600000044656e69656400000000"
  let blk45:BlockV1:={statements:=#[emitPing, .revert denied #[]]}
  let ((g45,r45),c45)←lift "b45" (dB 2 3 raw45)
  expect (decide (g45 = blk45) && r45.remainingNodes == 0) "b45"
  lift "b45f" (finish c45)
  expect ((← lift "b45e" (encodeBlockV1 g45)) == raw45) "b45 reencode"
  err "b46" "unknown pattern tag 'BogusPattern'" (dA 3 8 (tg "StmtMatchArm" #[bad "BogusPattern", bad "BogusBody"]))
  err "b47" "unknown block tag 'BogusBody'" (dA 3 8 (tg "StmtMatchArm" #[pw, bad "BogusBody"]))
  err "b48" "node budget exhausted" (dA 2 2 (tg "StmtMatchArm" #[pw, blk1]))
  err "b49" "trailing bytes" (do let ((_,_),c)←dS 2 2 (hex ("0b00000053746d742e52657475726e010000" ++ "00")); finish c)
  let deep50 := nestIf 127 (.return_ (some L0))
  let ((gd,rd),cd)←lift "b50" (dS 256 383 (← lift "e50" (encodeStmtV1 deep50)))
  expect (decide (gd = deep50) && rd.remainingNodes == 0) "b50"
  lift "b50f" (finish cd); expect ((← lift "b50e" (encodeStmtV1 gd)) == (← lift "b50r" (encodeStmtV1 deep50))) "b50 wire"
  err "b51" "depth budget exhausted" (dS 256 385 (← lift "e51" (encodeStmtV1 (nestIf 128 retNone))))
  err "b52" "node budget exhausted" (dS 256 382 (← lift "e52" (encodeStmtV1 deep50)))

end Tests.Language.SourceAstSpineStmtDecodeV1
