import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.NameComponentV1

namespace ProofForgeV2.Source.AstProgramV1

open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.NameComponentV1

structure ProgramV1 where
  name : SourceNameComponentV1
  items : Array ProgramItemV1
  deriving DecidableEq, Repr

end ProofForgeV2.Source.AstProgramV1
