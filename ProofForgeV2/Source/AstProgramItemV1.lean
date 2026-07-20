import ProofForgeV2.Source.AstDeclV1
import ProofForgeV2.Source.AstSpineDeclV1

namespace ProofForgeV2.Source.AstProgramItemV1

open ProofForgeV2.Source.AstDeclV1
open ProofForgeV2.Source.AstSpineDeclV1

inductive ProgramItemV1 where
  | state : StateDeclV1 → ProgramItemV1
  | struct : StructDeclV1 → ProgramItemV1
  | enum : EnumDeclV1 → ProgramItemV1
  | const : ConstDeclV1 → ProgramItemV1
  | event : EventDeclV1 → ProgramItemV1
  | error : ErrorDeclV1 → ProgramItemV1
  | init : InitDeclV1 → ProgramItemV1
  | entry : EntryDeclV1 → ProgramItemV1
  | view : ViewDeclV1 → ProgramItemV1
  | fn : FnDeclV1 → ProgramItemV1
  | invariant : InvariantDeclV1 → ProgramItemV1
  | extensionReq : ExtensionReqV1 → ProgramItemV1
  | proof : ProofDeclV1 → ProgramItemV1
  deriving DecidableEq, Repr

end ProofForgeV2.Source.AstProgramItemV1
