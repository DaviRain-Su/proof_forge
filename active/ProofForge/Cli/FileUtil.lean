import Lean.Util.Path

open System

namespace ProofForge.Cli

def writeTextFile (path : FilePath) (contents : String) : IO Unit := do
  if let some parent := path.parent then
    IO.FS.createDirAll parent
  IO.FS.writeFile path contents

end ProofForge.Cli
