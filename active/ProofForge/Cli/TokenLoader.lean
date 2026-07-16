import Init.Notation
import Lean
import Lean.Elab.Frontend
import Lean.Util.Path
import ProofForge.Cli.ContractLoader
import ProofForge.Contract.Token

namespace ProofForge.Cli.TokenLoader

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

unsafe def loadTokenFromEnv (env : Environment) (modName : Name) :
    IO (Option String × ProofForge.Contract.Token.TokenSpec) := do
  let some specName := resolveConstName env modName `spec `ProofForge.Contract.Token.TokenSpec
    | throw <| IO.userError
        s!"no `spec : ProofForge.Contract.Token.TokenSpec` found while loading module `{modName}`"
  let spec ←
    match env.evalConstCheck ProofForge.Contract.Token.TokenSpec {}
        `ProofForge.Contract.Token.TokenSpec specName with
    | .ok spec => pure spec
    | .error msg => throw <| IO.userError msg
  let id? ←
    match resolveConstName env modName `id `String with
    | some idName =>
        match env.evalConstCheck String {} `String idName with
        | .ok id => pure (some id)
        | .error msg => throw <| IO.userError msg
    | none => pure none
  pure (id?, spec)

unsafe def loadToken
    (input : System.FilePath) (root? : Option System.FilePath) (moduleName? : Option Name) :
    IO (Option String × ProofForge.Contract.Token.TokenSpec) := do
  let (env, modName) ←
    ProofForge.Cli.ContractLoader.runTrustedLocalFrontend input root? moduleName?
  loadTokenFromEnv env modName

end ProofForge.Cli.TokenLoader
