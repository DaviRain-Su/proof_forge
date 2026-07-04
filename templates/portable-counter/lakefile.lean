import Lake
open Lake DSL

/-!
Template lakefile for `proof-forge init`.

The init command copies this file into the target directory and substitutes
`{{PACKAGE_NAME}}` and `{{PROOF_FORGE_GIT_URL}}`.
-/
require proofForge from git
  "{{PROOF_FORGE_GIT_URL}}" @ "main"

package «{{PACKAGE_NAME}}» where
  version := v!"0.1.0"

lean_lib Counter where
  roots := #[`Counter]
