import Lean
import Lean.Util.Path
import ProofForge.Cli.ConstructorAbi
import ProofForge.Cli.EmitMode
import ProofForge.Cli.HexUtil
import ProofForge.Contract.Spec
import ProofForge.Target
import ProofForge.Target.PeerMap

open Lean
open System
open ProofForge.Cli.ConstructorAbi
open ProofForge.Cli.HexUtil

namespace ProofForge.Cli

export ProofForge.Cli.EmitMode (EmitMode)

inductive Command where
  | build
  | emit
  | check
  | init
  | metadata
  | listTargets
  | listFixtures
  deriving BEq, Inhabited, Repr

structure CliOptions where
  cmd : Command := .build
  input? : Option FilePath := none
  output? : Option FilePath := none
  root? : Option FilePath := none
  moduleName? : Option Name := none
  yulOutput? : Option FilePath := none
  artifactOutput? : Option FilePath := none
  solc : String := "solc"
  cast : String := "cast"
  evmChainProfile? : Option String := none
  evmConstructorArgsHex : String := ""
  evmConstructorArgsSource : String := "--evm-constructor-args-hex"
  evmConstructorParams : Array ConstructorParamSpec := #[]
  evmConstructorValues : Array ConstructorValueSpec := #[]
  solanaSbpfArch : String := "v3"
  targetId? : Option String := none
  fixture? : Option String := none
  format? : Option String := none
  reportFormat? : Option String := none
  scenario? : Option FilePath := none
  mode : EmitMode := .yul
  fromNewSurface : Bool := false
  /-- Deploy-time logical peer → host identity. Default **identity** (no silent
  rewrite). Use `--peer logical=host` and/or `--peers-demo`. -/
  peerMap : ProofForge.Target.PeerMap.Map := ProofForge.Target.PeerMap.identity
  deriving Inhabited

def CliOptions.emitsEvmDeployManifest (opts : CliOptions) : Bool :=
  opts.mode.emitsEvmDeployManifest ||
    (opts.mode == .learnTarget && opts.targetId? == some ProofForge.Target.evm.id)

def parseModuleName (s : String) : Name :=
  s.splitOn "." |>.foldl (init := Name.anonymous) fun acc part =>
    if part.isEmpty then acc else acc.str part

def dropEndString (s : String) (n : Nat) : String :=
  (s.dropEnd n).toString

def leanBaseName (input : FilePath) : String :=
  let fileName := input.fileName.getD input.toString
  if fileName.endsWith ".lean" then
    dropEndString fileName ".lean".length
  else
    fileName

def siblingPath (input : FilePath) (fileName : String) : FilePath :=
  let child := FilePath.mk fileName
  match input.parent with
  | some parent => parent / child
  | none => child

def defaultYulOutput (input : FilePath) : FilePath :=
  siblingPath input s!".{leanBaseName input}.yul"

def defaultBytecodeYulOutput (bytecodeOutput : FilePath) : FilePath :=
  bytecodeOutput.withExtension "yul"

def mergeSpecConstructorParams
    (opts : CliOptions) (spec : ProofForge.Contract.ContractSpec) : CliOptions :=
  if spec.constructorParams.isEmpty then
    opts
  else
    let specParams := spec.constructorParams.map fun param =>
      { name := param.name, abiType := param.abiType }
    let extraParams := opts.evmConstructorParams.filter fun param =>
      !specParams.any (fun existing => existing.name == param.name)
    { opts with evmConstructorParams := specParams ++ extraParams }

def constructorValuesDeferSpecMerge
    (params : Array ConstructorParamSpec) (values : Array ConstructorValueSpec) : Bool :=
  values.any (fun value => !constructorParamExists params value.name)

def constructorValuesReady (params : Array ConstructorParamSpec) (values : Array ConstructorValueSpec) : Bool :=
  !values.isEmpty &&
    !constructorValuesDeferSpecMerge params values &&
    params.all (fun param => findConstructorValue? values param.name |>.isSome)

def finalizeConstructorOptions (opts : CliOptions) : Except String CliOptions := do
  let argsHex ← normalizeConstructorArgsHex opts.evmConstructorArgsHex
  if !opts.evmConstructorValues.isEmpty then
    if !argsHex.isEmpty then
      .error "--evm-constructor-arg cannot be combined with --evm-constructor-args-hex"
    else if constructorValuesDeferSpecMerge opts.evmConstructorParams opts.evmConstructorValues then
      validateConstructorValues opts.evmConstructorParams opts.evmConstructorValues
      .ok opts
    else if constructorValuesReady opts.evmConstructorParams opts.evmConstructorValues then
      let encoded ← encodeConstructorValues opts.evmConstructorParams opts.evmConstructorValues
      validateConstructorSchemaAndArgs opts.evmConstructorParams encoded
      .ok { opts with
        evmConstructorArgsHex := encoded,
        evmConstructorArgsSource := "--evm-constructor-arg"
      }
    else
      validateConstructorValues opts.evmConstructorParams opts.evmConstructorValues
      .ok opts
  else
    validateConstructorSchemaAndArgs opts.evmConstructorParams argsHex
    .ok { opts with
      evmConstructorArgsHex := argsHex,
      evmConstructorArgsSource := "--evm-constructor-args-hex"
    }

def finalizeConstructorOptionsForSpec
    (opts : CliOptions) (spec : ProofForge.Contract.ContractSpec) : Except String CliOptions := do
  let mergedBase := mergeSpecConstructorParams opts spec
  -- Named values may have been encoded against CLI-only params before the
  -- contract schema was loaded, so re-encode them after the merge. Raw ABI hex
  -- has no named values and must survive the schema merge for canonical checks.
  let merged :=
    if opts.evmConstructorValues.isEmpty then
      mergedBase
    else
      { mergedBase with evmConstructorArgsHex := "" }
  if !merged.evmConstructorValues.isEmpty && constructorValuesDeferSpecMerge merged.evmConstructorParams merged.evmConstructorValues then
    validateConstructorValuesAgainstParams merged.evmConstructorParams merged.evmConstructorValues
  finalizeConstructorOptions merged

end ProofForge.Cli
