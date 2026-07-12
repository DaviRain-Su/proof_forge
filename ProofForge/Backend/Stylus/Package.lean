/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import ProofForge.Backend.Stylus.RustSdk.AST

namespace ProofForge.Backend.Stylus

open RustSdk

structure PackageError where
  message : String
  deriving Repr, BEq

private def fail (message : String) : Except PackageError α := .error { message }

private def validatePath (path : String) : Except PackageError Unit := do
  if path.isEmpty || path.startsWith "/" || path.contains '\\' then
    fail s!"unsafe Stylus crate path `{path}`"
  let components := path.splitOn "/"
  if components.any (fun part => part.isEmpty || part == "." || part == "..") then
    fail s!"unsafe Stylus crate path `{path}`"

def validateCrate (crate : RustCrate) : Except PackageError Unit := do
  let mut seen : Array String := #[]
  for file in crate.files do
    validatePath file.path
    if seen.contains file.path then
      fail s!"duplicate Stylus crate path `{file.path}`"
    seen := seen.push file.path

def writeCrateAtomic (crate : RustCrate) (output : System.FilePath) : IO (Except PackageError Unit) := do
  match validateCrate crate with
  | .error error => pure (.error error)
  | .ok () =>
      if ← output.pathExists then
        pure <| .error { message := s!"Stylus crate output already exists: {output}" }
      else
        let pid <- IO.Process.getPID
        let temporary := System.FilePath.mk s!"{output}.tmp-{pid}"
        try
          if ← temporary.pathExists then IO.FS.removeDirAll temporary
          IO.FS.createDirAll temporary
          for file in crate.files do
            let path := temporary / file.path
            IO.FS.createDirAll (path.parent.getD temporary)
            IO.FS.writeFile path file.content
          IO.FS.rename temporary output
          pure (.ok ())
        catch error =>
          if ← temporary.pathExists then IO.FS.removeDirAll temporary
          pure <| .error { message := s!"failed to package Stylus crate: {error}" }

end ProofForge.Backend.Stylus
