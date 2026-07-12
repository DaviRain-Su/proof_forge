import ProofForge.Backend.Stylus.Package

open ProofForge.Backend.Stylus
open ProofForge.Backend.Stylus.RustSdk

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def expectInvalid (crate : RustCrate) (fragment : String) : IO Unit :=
  match validateCrate crate with
  | .ok () => throw <| IO.userError s!"expected invalid crate containing `{fragment}`"
  | .error error => require (error.message.contains fragment) s!"missing diagnostic `{fragment}`"

def main : IO Unit := do
  let good : RustCrate := {
    name := "counter"
    files := #[
      { path := "Cargo.toml", content := "[package]\n" },
      { path := "src/lib.rs", content := "#![no_std]\n" }
    ]
  }
  expectInvalid { good with files := #[{ path := "/tmp/escape", content := "" }] } "unsafe"
  expectInvalid { good with files := #[{ path := "../escape", content := "" }] } "unsafe"
  expectInvalid { good with files := #[{ path := "src\\escape", content := "" }] } "unsafe"
  expectInvalid { good with files := #[
    { path := "Cargo.toml", content := "a" }, { path := "Cargo.toml", content := "b" }
  ] } "duplicate"
  let output : System.FilePath := "build/stylus/package-test/Counter"
  let parent := output.parent.getD "build/stylus/package-test"
  if ← parent.pathExists then IO.FS.removeDirAll parent
  match ← writeCrateAtomic good output with
  | .error error => throw <| IO.userError error.message
  | .ok () => pure ()
  require (← (output / "Cargo.toml").pathExists) "atomic package omitted Cargo.toml"
  require (← (output / "src/lib.rs").pathExists) "atomic package omitted src/lib.rs"
  match ← writeCrateAtomic good output with
  | .ok () => throw <| IO.userError "existing output must be rejected"
  | .error error => require (error.message.contains "already exists") "missing existing-output diagnostic"
  IO.FS.removeDirAll parent
  IO.println "stylus-package: ok"
