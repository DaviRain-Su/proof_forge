import Tests.Language.ProgramExportFixtures.Shared

namespace Tests.Language.ProgramExportFixtures.A

open ProofForgeV2.Language
open Tests.Language.ProgramExportFixtures.Shared

program AProg where
  entry run() : UInt64 do
    return 1

def sharedManualAlias : ProofForgeV2.Source.Program := SharedProg

end Tests.Language.ProgramExportFixtures.A
