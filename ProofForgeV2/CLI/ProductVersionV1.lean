/-
  Product version identity for engineering distribution (REL-CLI-0).

  Authority: docs/product/05-distribution-and-packages.md
  The string `productVersionV1` must match repo-root `VERSION` exactly
  (enforced by scripts/package_cli_dist.sh and package smoke).
  This is **not** formal Stage-0 / hermetic release evidence.
-/
namespace ProofForgeV2.CLI.ProductVersionV1

/-- Engineering product SemVer; sole Lean-side product version constant. -/
def productVersionV1 : String := "0.1.1"

/-- Machine-readable version schema id. -/
def productVersionSchemaV1 : String := "proof-forge.cli.version.v1"

/-- Distribution channel spelling — never claim formal Stage-0 here. -/
def productChannelV1 : String := "engineering-dist"

/-- Product CLI executable name as shipped. -/
def productNameV1 : String := "proof-forge-next"

/-- Pinned Lean toolchain id (must match repo `lean-toolchain` file content). -/
def leanToolchainIdV1 : String := "leanprover/lean4:v4.31.0"

/-- Human one-line version (stdout for `version` / `--version`). -/
def renderVersionHumanV1 : String :=
  s!"{productNameV1} {productVersionV1} ({productChannelV1})"

/-- Deterministic PF-JCS-friendly JSON object text for `version --json`.

    Key order is fixed ASCII for stable stdout (not full PF-JCS library encode). -/
def renderVersionJsonV1 : String :=
  "{" ++
  s!"\"channel\":\"{productChannelV1}\"," ++
  s!"\"leanToolchain\":\"{leanToolchainIdV1}\"," ++
  s!"\"product\":\"{productNameV1}\"," ++
  s!"\"schema\":\"{productVersionSchemaV1}\"," ++
  s!"\"version\":\"{productVersionV1}\"" ++
  "}"

end ProofForgeV2.CLI.ProductVersionV1
