import Init.Notation
import Lean
import Lean.Elab.Frontend
import Lean.Util.Path
import ProofForge.Cli.ContractLoader
import ProofForge.Contract.Nft
import ProofForge.Contract.Nft.Materialize
import ProofForge.Contract.Intent.Registry

namespace ProofForge.Cli.NftLoader

open Lean

private def candidateNames (modName : Name) (base : Name) : List Name :=
  let lastComponent :=
    match modName.components.reverse with
    | last :: _ => last
    | [] => Name.anonymous
  [modName ++ base, lastComponent ++ base, base]

private def isConstOfType (env : Environment) (constName typeName : Name) : Bool :=
  match env.find? constName with
  | some info =>
      match info.type with
      | Expr.const name _ => name == typeName
      | _ => false
  | none => false

private def resolveConstName (env : Environment) (modName base typeName : Name) : Option Name :=
  (candidateNames modName base).find? fun candidate =>
    env.constants.contains candidate && isConstOfType env candidate typeName

unsafe def loadNftFromEnv (env : Environment) (modName : Name) :
    IO ProofForge.Contract.NFTSpec := do
  let some specName := resolveConstName env modName `spec `ProofForge.Contract.NFTSpec
    | throw <| IO.userError
        s!"no `spec : ProofForge.Contract.NFTSpec` found while loading module `{modName}`"
  match env.evalConstCheck ProofForge.Contract.NFTSpec {}
      `ProofForge.Contract.NFTSpec specName with
  | .ok spec => pure spec
  | .error msg => throw <| IO.userError msg

/-- Load an NFTSpec from a source file and materialize it to a ContractSpec
for the given target via the nftIntentRegistry. -/
unsafe def loadAndMaterializeNft
    (input : System.FilePath) (root? : Option System.FilePath)
    (moduleName? : Option Lean.Name) (targetId : String) :
    IO ProofForge.Contract.ContractSpec := do
  let (env, modName) ←
    ProofForge.Cli.ContractLoader.runTrustedLocalFrontend input root? moduleName?
  let nftSpec ← loadNftFromEnv env modName
  let intentContract ← match ProofForge.Contract.NFTSpec.toIntentContract nftSpec with
    | .ok c => pure c
    | .error e => throw <| IO.userError s!"NFTSpec validation failed: {e}"
  let registry ← match ProofForge.Contract.NftMaterialize.nftIntentRegistry with
    | .ok r => pure r
    | .error e => throw <| IO.userError s!"NFT registry creation failed: {e}"
  let materializer ← match ProofForge.Contract.IntentRegistry.resolve registry targetId .nonFungibleToken with
    | .ok m => pure m
    | .error e => throw <| IO.userError s!"{e}"
  let materialization ← match materializer.materialize intentContract with
    | .ok mat => pure mat
    | .error e => throw <| IO.userError s!"NFT materialization failed for target `{targetId}`: {e}"
  pure materialization.contractSpec

/-- Check if a source file defines an NFTSpec (for auto-detect diagnostics). -/
unsafe def isNftSpecSource
    (input : System.FilePath) (root? : Option System.FilePath)
    (moduleName? : Option Lean.Name) : IO Bool := do
  try
    let (env, modName) ←
      ProofForge.Cli.ContractLoader.runTrustedLocalFrontend input root? moduleName?
    pure (resolveConstName env modName `spec `ProofForge.Contract.NFTSpec).isSome
  catch _ =>
    pure false

end ProofForge.Cli.NftLoader