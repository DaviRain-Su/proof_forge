import ProofForgeV2.Source.AstDeclCodecV1
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstSpineDeclCodecV1

namespace ProofForgeV2.Source.AstProgramItemCodecV1

open ProofForgeV2.Source.AstDeclCodecV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstSpineDeclCodecV1

def encodeProgramItemV1 : ProgramItemV1 → Except String ByteArray
  | .state d => encodeStateDeclV1 d
  | .struct d => encodeStructDeclV1 d
  | .enum d => encodeEnumDeclV1 d
  | .const d => encodeConstDeclV1 d
  | .event d => encodeEventDeclV1 d
  | .error d => encodeErrorDeclV1 d
  | .init d => encodeInitDeclV1 d
  | .entry d => encodeEntryDeclV1 d
  | .view d => encodeViewDeclV1 d
  | .fn d => encodeFnDeclV1 d
  | .invariant d => encodeInvariantDeclV1 d
  | .extensionReq d => encodeExtensionReqV1 d
  | .proof d => encodeProofDeclV1 d

end ProofForgeV2.Source.AstProgramItemCodecV1
