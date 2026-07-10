import Lean.Util.Path
import ProofForge.Cli.ConstructorAbi
import ProofForge.Cli.Fixture
import ProofForge.Cli.Quint
import ProofForge.Cli.TargetDriver
import ProofForge.Cli.Usage

open System
open ProofForge.Cli.ConstructorAbi

namespace ProofForge.Cli

structure NewCommandParseState where
  target? : Option String := none
  fixture? : Option String := none
  format? : Option String := none
  reportFormat? : Option String := none
  scenario? : Option String := none
  out? : Option String := none
  yulOut? : Option String := none
  artifactOut? : Option String := none
  root? : Option String := none
  module? : Option String := none
  solc : String := "solc"
  cast : String := "cast"
  evmChainProfile? : Option String := none
  evmConstructorParams : Array ConstructorParamSpec := #[]
  evmConstructorValues : Array ConstructorValueSpec := #[]
  evmConstructorArgsHex : String := ""
  solanaSbpfArch? : Option String := none
  token : Bool := false
  /-- Accumulated `--peer logical=host` bindings (forwarded to legacy). -/
  peers : Array String := #[]
  peersDemo : Bool := false
  input? : Option String := none
  legacyPrefix : List String := []
  deriving Inhabited

def takeOption (args : List String) (name : String) : Except String (String × List String) :=
  match args with
  | value :: rest => .ok (value, rest)
  | [] => .error s!"{name} requires a value"

partial def parseNewOptions : List String → NewCommandParseState → Except String NewCommandParseState
  | [], state => .ok state
  | "--target" :: rest, state => do
      let (target, rest) ← takeOption rest "--target"
      parseNewOptions rest { state with target? := some target }
  | "--fixture" :: rest, state => do
      let (fixture, rest) ← takeOption rest "--fixture"
      parseNewOptions rest { state with fixture? := some fixture }
  | "--format" :: rest, state => do
      let (format, rest) ← takeOption rest "--format"
      parseNewOptions rest { state with format? := some format }
  | "--report-format" :: rest, state => do
      let (format, rest) ← takeOption rest "--report-format"
      parseNewOptions rest { state with reportFormat? := some format }
  | "--scenario" :: rest, state => do
      let (path, rest) ← takeOption rest "--scenario"
      parseNewOptions rest { state with scenario? := some path }
  | "-o" :: rest, state => do
      let (out, rest) ← takeOption rest "-o"
      parseNewOptions rest { state with out? := some out }
  | "--output" :: rest, state => do
      let (out, rest) ← takeOption rest "--output"
      parseNewOptions rest { state with out? := some out }
  | "--root" :: rest, state => do
      let (root, rest) ← takeOption rest "--root"
      parseNewOptions rest { state with root? := some root }
  | "--module" :: rest, state => do
      let (module, rest) ← takeOption rest "--module"
      parseNewOptions rest { state with module? := some module }
  | "--yul-output" :: rest, state => do
      let (path, rest) ← takeOption rest "--yul-output"
      parseNewOptions rest { state with yulOut? := some path }
  | "--artifact-output" :: rest, state => do
      let (path, rest) ← takeOption rest "--artifact-output"
      parseNewOptions rest { state with artifactOut? := some path }
  | "--solc" :: rest, state => do
      let (path, rest) ← takeOption rest "--solc"
      parseNewOptions rest { state with solc := path }
  | "--cast" :: rest, state => do
      let (path, rest) ← takeOption rest "--cast"
      parseNewOptions rest { state with cast := path }
  | "--evm-chain-profile" :: rest, state => do
      let (profile, rest) ← takeOption rest "--evm-chain-profile"
      parseNewOptions rest { state with evmChainProfile? := some profile }
  | "--evm-constructor-param" :: rest, state => do
      let (spec, rest) ← takeOption rest "--evm-constructor-param"
      match spec.splitOn ":" with
      | [name, abiType] =>
          parseNewOptions rest { state with evmConstructorParams := state.evmConstructorParams.push { name := name, abiType := abiType } }
      | _ => .error s!"invalid --evm-constructor-param '{spec}', expected name:type"
  | "--evm-constructor-arg" :: rest, state => do
      let (spec, rest) ← takeOption rest "--evm-constructor-arg"
      match spec.splitOn "=" with
      | [name, value] =>
          parseNewOptions rest { state with evmConstructorValues := state.evmConstructorValues.push { name := name, value := value } }
      | _ => .error s!"invalid --evm-constructor-arg '{spec}', expected name=value"
  | "--evm-constructor-args-hex" :: rest, state => do
      let (hex, rest) ← takeOption rest "--evm-constructor-args-hex"
      parseNewOptions rest { state with evmConstructorArgsHex := hex }
  | "--solana-sbpf-arch" :: rest, state => do
      let (arch, rest) ← takeOption rest "--solana-sbpf-arch"
      if arch == "v0" || arch == "v3" then
        parseNewOptions rest { state with solanaSbpfArch? := some arch }
      else
        .error s!"invalid --solana-sbpf-arch '{arch}', expected v0 or v3"
  | "--token" :: rest, state =>
      parseNewOptions rest { state with token := true }
  | "--peer" :: rest, state => do
      let (spec, rest) ← takeOption rest "--peer"
      parseNewOptions rest { state with peers := state.peers.push spec }
  | "--peers-demo" :: rest, state =>
      parseNewOptions rest { state with peersDemo := true }
  | arg :: rest, state =>
      if arg.startsWith "-" then
        .error s!"unknown option: {arg}\n{usage}"
      else if state.input?.isSome then
        .error s!"multiple input files provided\n{usage}"
      else
        parseNewOptions rest { state with input? := some arg }

def pathLooksLikeDirectory (path : String) : Bool :=
  (FilePath.mk path).extension.isNone

def dirChildString (dir file : String) : String :=
  ((FilePath.mk dir) / file).toString

def targetFirstNativeOutput (target flag out : String) : String :=
  if !pathLooksLikeDirectory out then
    out
  else
    match target, flag with
    | "evm", "--emit-counter-ir-bytecode" => dirChildString out "Counter.bin"
    | "evm", "--emit-counter-ir-yul" => dirChildString out "Counter.yul"
    | "solana-sbpf-asm", "--emit-counter-ir-sbpf" => dirChildString out "Counter.s"
    | _, _ => out

def targetFirstYulOutput? (target flag : String) (out? yulOut? : Option String) : Option String :=
  match yulOut?, out? with
  | some yul, _ => some yul
  | none, some out =>
      if target == "evm" && flag == "--emit-counter-ir-bytecode" && pathLooksLikeDirectory out then
        some (dirChildString out "Counter.yul")
      else
        none
  | none, none => none

/-- Build legacy flag via registry-backed `TargetCliDriver` (PF-P1-01). -/
def buildLegacyFlag (target : String) (input? : Option String) (fixture? : Option String := none)
    (format? : Option String := none) (token : Bool := false) : Except String String :=
  resolveBuildLegacyFlag target {
    input? := input?
    fixture? := fixture?
    format? := format?
    token := token
  }

/-- Emit legacy flag via registry-backed `TargetCliDriver` (PF-P1-01). -/
def emitLegacyFlag (target fixture : String) (format? : Option String) : Except String String :=
  resolveEmitLegacyFlag target {
    fixture := fixture
    format? := format?
  }

def newCommandArgsToLegacy (state : NewCommandParseState) (cmd : String) : Except String (List String) := do
  if cmd == "build" then
    let target ← match state.target? with | some t => Except.ok t | none => Except.error "build requires --target <id>"
    let flag ← buildLegacyFlag target state.input? state.fixture? state.format? state.token
    let mut legacy := [flag]
    if let some out := state.out? then legacy := legacy ++ ["-o", targetFirstNativeOutput target flag out]
    if let some root := state.root? then legacy := legacy ++ ["--root", root]
    if let some modName := state.module? then legacy := legacy ++ ["--module", modName]
    if let some yul := targetFirstYulOutput? target flag state.out? state.yulOut? then legacy := legacy ++ ["--yul-output", yul]
    if let some artifact := state.artifactOut? then legacy := legacy ++ ["--artifact-output", artifact]
    if let some profile := state.evmChainProfile? then legacy := legacy ++ ["--evm-chain-profile", profile]
    for param in state.evmConstructorParams do
      legacy := legacy ++ ["--evm-constructor-param", s!"{param.name}:{param.abiType}"]
    for value in state.evmConstructorValues do
      legacy := legacy ++ ["--evm-constructor-arg", s!"{value.name}={value.value}"]
    if state.evmConstructorArgsHex != "" then
      legacy := legacy ++ ["--evm-constructor-args-hex", state.evmConstructorArgsHex]
    if flag == "--evm-bytecode" || flag.endsWith "-bytecode" then
      legacy := legacy ++ ["--solc", state.solc, "--cast", state.cast]
    if flag == "--learn" || flag == "--learn-token" then
      legacy := legacy ++ ["--target", target]
    -- EmitWat host bridge (NEAR vs Soroban) is selected from --target.
    if flag == "--contract-source-emitwat" then
      legacy := legacy ++ ["--target", target]
    if target == "solana-sbpf-asm" then
      if let some arch := state.solanaSbpfArch? then
        legacy := legacy ++ ["--solana-sbpf-arch", arch]
    if state.peersDemo then
      legacy := legacy ++ ["--peers-demo"]
    for peer in state.peers do
      legacy := legacy ++ ["--peer", peer]
    if let some input := state.input? then legacy := legacy ++ [input]
    Except.ok legacy
  else if cmd == "emit" then
    let target ← match state.target? with | some t => Except.ok t | none => Except.error "emit requires --target <id>"
    let fixture ← match state.fixture? with | some f => Except.ok f | none => Except.error "emit requires --fixture <id>"
    let flag ← emitLegacyFlag target fixture state.format?
    let mut legacy := [flag]
    if let some out := state.out? then legacy := legacy ++ ["-o", targetFirstNativeOutput target flag out]
    if let some yul := targetFirstYulOutput? target flag state.out? state.yulOut? then legacy := legacy ++ ["--yul-output", yul]
    if let some artifact := state.artifactOut? then legacy := legacy ++ ["--artifact-output", artifact]
    if let some profile := state.evmChainProfile? then legacy := legacy ++ ["--evm-chain-profile", profile]
    if let some scenario := state.scenario? then legacy := legacy ++ ["--scenario", scenario]
    if flag == "--emit-ir-quint" || flag == "--emit-ir-quint-scenario" then
      legacy := legacy ++ ["--fixture", fixture]
    if flag.endsWith "-bytecode" then
      legacy := legacy ++ ["--solc", state.solc, "--cast", state.cast]
    if target == "solana-sbpf-asm" then
      if let some arch := state.solanaSbpfArch? then
        legacy := legacy ++ ["--solana-sbpf-arch", arch]
    Except.ok legacy
  else if cmd == "check" then
    Except.error "proof-forge check is not yet implemented"
  else
    Except.error "expected build, emit, or check"

end ProofForge.Cli
