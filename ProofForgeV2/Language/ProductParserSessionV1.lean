import Lean
import Lean.Util.Path

/-!
# ProductParserSessionV1

Lightweight opaque authority for the package-owned product frontend
Environment. This module deliberately does not statically import
`ProofForgeV2.Language.Syntax` or `ProgramElaborationV1`: the locked frontend
`.olean` is loaded at runtime from the executable-sibling package root. Loader
and inline certification can therefore share one unforgeable Environment
without leaking DSL command keywords into compiler/target modules.
-/

namespace ProofForgeV2.Language.Loader

open Lean

/-- Product parser/elaboration session. The constructor is private; callers
    cannot relabel an ambient development Environment as product authority. -/
structure ProductParserSessionV1 where
  private mk ::
  private environment_ : Environment

namespace ProductParserSessionV1

/-- Locked module used for ProgramV1 inventory parsing and adjacent theorem
    elaboration. -/
def lockedFrontendModuleV1 : Name :=
  `ProofForgeV2.Language.ProgramElaborationV1

private def packageOleanRootV1 : IO System.FilePath := do
  let appDir ← IO.appDir
  let buildDir ← match appDir.parent with
    | some value => pure value
    | none => throw (IO.userError
        "PF-INTERNAL: product executable has no build-root parent")
  let root := buildDir / "lib" / "lean"
  let moduleFile := root / "ProofForgeV2" / "Language" /
    "ProgramElaborationV1.olean"
  unless ← moduleFile.pathExists do
    throw (IO.userError
      "PF-INTERNAL: package-owned inline-proof frontend module is missing")
  let rootMetadata ← root.symlinkMetadata
  unless rootMetadata.type == .dir do
    throw (IO.userError
      "PF-INTERNAL: package-owned inline-proof module root is not a directory")
  let realRoot ← IO.FS.realPath root
  unless realRoot == root do
    throw (IO.userError
      "PF-INTERNAL: package-owned inline-proof module root must not traverse a symlink")
  pure root

/-- Exact immutable Environment shared by product Loader parsing and proof
    command elaboration. -/
def sessionEnvironment (value : ProductParserSessionV1) : Environment :=
  value.environment_

/-- Mint the product session from an executable-sibling package module root and
    the trusted Lean runtime sysroot. This writes the process-global search path
    exactly once on the caller's control thread and ignores `LEAN_PATH`;
    concurrent creation remains unsupported. -/
unsafe def create : IO ProductParserSessionV1 := do
  let packageRoot ← packageOleanRootV1
  let leanSysroot ← findSysroot "lean"
  let builtinRoots ← getBuiltinSearchPath leanSysroot
  searchPathRef.set ([packageRoot] ++ builtinRoots)
  enableInitializersExecution
  let environment ← importModules #[{ module := lockedFrontendModuleV1 }] {} 0
    (loadExts := true)
  pure ⟨environment⟩

end ProductParserSessionV1

end ProofForgeV2.Language.Loader
