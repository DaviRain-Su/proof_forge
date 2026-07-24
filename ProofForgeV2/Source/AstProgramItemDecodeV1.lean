import ProofForgeV2.Source.AstDeclDecodeV1
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstSpineDeclDecodeV1
import ProofForgeV2.Source.DecodeBudgetV1
import ProofForgeV2.Source.WireDecodeV1

namespace ProofForgeV2.Source.AstProgramItemDecodeV1

open ProofForgeV2.Source.AstDeclDecodeV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstSpineDeclDecodeV1
open ProofForgeV2.Source.DecodeBudgetV1
open ProofForgeV2.Source.WireDecodeV1

private def fail (detail : String) : Except String α :=
  .error detail

private def wrapItem (constructor : α → ProgramItemV1)
    (decoder : DecoderV1 (α × DecodeBudgetV1)) :
    DecoderV1 (ProgramItemV1 × DecodeBudgetV1) := fun cursor => do
  let ((value, residual), cursor) ← decoder cursor
  pure ((constructor value, residual), cursor)

/-- Decode one no-wrapper ProgramItem by bounded tag lookahead, then delegate
    the original cursor and caller-owned budgets to exactly one record decoder. -/
def decodeProgramItemV1 (depth : Nat) (budget : DecodeBudgetV1) :
    DecoderV1 (ProgramItemV1 × DecodeBudgetV1) := fun cursor => do
  let (tag, _afterTag) ← decodeTagV1 cursor
  match tag with
  | "StateDecl" => wrapItem ProgramItemV1.state (decodeStateDeclV1 depth budget) cursor
  | "StructDecl" => wrapItem ProgramItemV1.struct (decodeStructDeclV1 depth budget) cursor
  | "EnumDecl" => wrapItem ProgramItemV1.enum (decodeEnumDeclV1 depth budget) cursor
  | "ConstDecl" => wrapItem ProgramItemV1.const (decodeConstDeclV1 depth budget) cursor
  | "EventDecl" => wrapItem ProgramItemV1.event (decodeEventDeclV1 depth budget) cursor
  | "ErrorDecl" => wrapItem ProgramItemV1.error (decodeErrorDeclV1 depth budget) cursor
  | "InitDecl" => wrapItem ProgramItemV1.init (decodeInitDeclV1 depth budget) cursor
  | "EntryDecl" => wrapItem ProgramItemV1.entry (decodeEntryDeclV1 depth budget) cursor
  | "ViewDecl" => wrapItem ProgramItemV1.view (decodeViewDeclV1 depth budget) cursor
  | "FnDecl" => wrapItem ProgramItemV1.fn (decodeFnDeclV1 depth budget) cursor
  | "InvariantDecl" =>
      wrapItem ProgramItemV1.invariant (decodeInvariantDeclV1 depth budget) cursor
  | "ExtensionReq" =>
      wrapItem ProgramItemV1.extensionReq (decodeExtensionReqV1 depth budget) cursor
  | "ProofDecl" => wrapItem ProgramItemV1.proof (decodeProofDeclV1 depth budget) cursor
  | _ => fail s!"unknown program-item tag '{tag}'"

end ProofForgeV2.Source.AstProgramItemDecodeV1
