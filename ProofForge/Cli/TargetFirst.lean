import Lean.Util.Path
import ProofForge.Cli.ConstructorAbi
import ProofForge.Cli.Fixture
import ProofForge.Cli.Quint
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
  | arg :: rest, state =>
      if arg.startsWith "-" then
        .error s!"unknown option: {arg}\n{usage}"
      else if state.input?.isSome then
        .error s!"multiple input files provided\n{usage}"
      else
        parseNewOptions rest { state with input? := some arg }

def isLeanSourceFile (input? : Option String) : Bool :=
  match input? with
  | some path => path.endsWith ".lean"
  | none => false

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

def buildLegacyFlag (target : String) (input? : Option String) (fixture? : Option String := none) (format? : Option String := none) (token : Bool := false) : Except String String :=
  let isLearn := match input? with | some input => input.endsWith ".learn" | none => false
  let isLeanSource := isLeanSourceFile input?
  match target, isLearn, fixture?, format?, token with
  | "evm", true, _, some "yul", false => Except.ok "--learn-yul"
  | "evm", true, _, some "yul", true => Except.error "proof-forge build --target evm --token --format yul is not yet implemented"
  | "evm", true, _, some "bytecode", true => Except.ok "--learn-token"
  | "evm", true, _, some "bytecode", false => Except.ok "--learn"
  | "evm", true, _, none, true => Except.ok "--learn-token"
  | "evm", true, _, none, false => Except.ok "--learn"
  | "evm", false, _, some "yul", true =>
      if isLeanSource then
        Except.error "proof-forge build --target evm --token --format yul is not yet implemented"
      else
        Except.error "proof-forge build --target evm --token requires a .lean TokenSpec or .learn token source"
  | "evm", false, _, some "bytecode", true =>
      if isLeanSource then
        Except.ok "--learn-token"
      else
        Except.error "proof-forge build --target evm --token requires a .lean TokenSpec or .learn token source"
  | "evm", false, _, none, true =>
      if isLeanSource then
        Except.ok "--learn-token"
      else
        Except.error "proof-forge build --target evm --token requires a .lean TokenSpec or .learn token source"
  | "evm", false, _, some "yul", _ =>
      if input?.isSome then Except.ok "--evm-bytecode" else Except.ok "--emit-counter-ir-yul"
  | "evm", false, _, _, _ =>
      if input?.isSome then Except.ok "--evm-bytecode" else Except.ok "--emit-counter-ir-bytecode"
  | "wasm-near", true, _, _, _ =>
      Except.error "proof-forge build --target wasm-near from .learn source is not yet implemented"
  | "wasm-near", false, _, _, true =>
      if isLeanSource then
        Except.ok "--learn-token"
      else
        Except.error "proof-forge build --target wasm-near --token requires a .lean TokenSpec or .learn token source"
  | "wasm-near", false, fixture?, format?, _ =>
      if isLeanSource then
        if format?.isSome && format? != some "wat" then
          Except.error s!"proof-forge build --target wasm-near does not support format '{format?.getD ""}'; use --format wat"
        else
          Except.ok "--contract-source-emitwat"
      else if input?.isSome then
        Except.error "proof-forge build --target wasm-near from Lean source is not yet implemented; use a .lean contract_source module"
      else
        if format?.isSome && format? != some "wat" then
          Except.error s!"proof-forge build --target wasm-near does not support format '{format?.getD ""}'; use --format wat"
        else
          let fixture := fixture?.getD "counter"
          if ProofForge.Cli.Fixture.isWasmNearFixture fixture then
            Except.ok s!"--emit-{fixture}-emitwat"
          else
            Except.error s!"proof-forge build --target wasm-near --fixture {fixture} is not yet implemented"
  | "wasm-cosmwasm", true, _, _, _ =>
      Except.error "proof-forge build --target wasm-cosmwasm from .learn source is not yet implemented"
  | "wasm-cosmwasm", false, _, _, _ => Except.ok "--emit-counter-ir-cosmwasm"
  | "solana-sbpf-asm", true, _, _, true => Except.ok "--learn-token"
  | "solana-sbpf-asm", true, _, _, false => Except.ok "--learn"
  | "solana-sbpf-asm", false, _, _, true =>
      if isLeanSource then
        Except.ok "--learn-token"
      else
        Except.error "proof-forge build --target solana-sbpf-asm --token requires a .lean TokenSpec or .learn token source"
  | "solana-sbpf-asm", false, _, _, _ =>
      if isLeanSource then
        Except.ok "--contract-source-sbpf"
      else if format? == some "s" || format?.isNone then
        Except.ok "--emit-counter-ir-sbpf"
      else
        Except.error s!"proof-forge build --target solana-sbpf-asm does not support format '{format?.getD ""}' without a Lean contract source input"
  | "psy-dpn", true, _, _, _ =>
      Except.error "proof-forge build --target psy-dpn from .learn source is not yet implemented"
  | "psy-dpn", false, _, _, _ => Except.ok "--emit-counter-ir-psy"
  | "aleo-leo", true, _, _, _ =>
      Except.error "proof-forge build --target aleo-leo from .learn source is not yet implemented"
  | "aleo-leo", false, _, _, _ => Except.ok "--emit-counter-ir-leo"
  | "move-aptos", true, _, _, _ =>
      Except.error "proof-forge build --target move-aptos from .learn source is not yet implemented"
  | "move-aptos", false, _, _, _ => Except.ok "--emit-counter-ir-aptos"
  | "move-sui", true, _, _, _ =>
      Except.error "proof-forge build --target move-sui from .learn source is not yet implemented"
  | "move-sui", false, fixture?, _, _ =>
      if isLeanSource then
        Except.error "proof-forge build --target move-sui from source is out of scope for the Counter object MVP; use --fixture counter"
      else
        match fixture? with
        | some fixture =>
            if fixture == "counter" then Except.ok "--emit-counter-ir-sui"
            else Except.error s!"proof-forge build --target move-sui --fixture {fixture} is not yet implemented"
        | none => Except.ok "--emit-counter-ir-sui"
  | other, _, _, _, _ => Except.error s!"unknown target '{other}'"

def emitLegacyFlag (target fixture : String) (format? : Option String) : Except String String :=
  let format := format?.getD ""
  match target, fixture, format with
  | "evm", f, "yul" =>
      if f == "array-abi" then
        Except.ok "--emit-evm-array-abi-ir-yul"
      else
        Except.ok s!"--emit-{f}-ir-yul"
  | "evm", f, "bytecode" =>
      if f == "array-abi" then
        Except.ok "--emit-evm-array-abi-ir-bytecode"
      else
        Except.ok s!"--emit-{f}-ir-bytecode"
  | "solana-sbpf-asm", "counter", fmt =>
      if fmt == "elf" || fmt == "so" then
        Except.ok "--solana-elf"
      else
        Except.ok "--emit-counter-ir-sbpf"
  | "solana-sbpf-asm", "value-vault", fmt =>
      if fmt == "elf" || fmt == "so" then
        Except.ok "--value-vault-solana-elf"
      else
        Except.ok "--emit-value-vault-ir-sbpf"
  | "solana-sbpf-asm", "error-ref", _ => Except.ok "--emit-error-ref-ir-sbpf"
  | "solana-sbpf-asm", "control", _ => Except.ok "--emit-control-ir-sbpf"
  | "solana-sbpf-asm", "solana-sdk", _ => Except.ok "--emit-solana-sdk-sbpf"
  | "solana-sbpf-asm", "canned-entrypoint", _ => Except.ok "--emit-sbpf-asm"
  | "solana-sbpf-asm", f, fmt =>
      if f.startsWith "solana-" then
        if fmt == "s" then
          Except.error s!"emit --target solana-sbpf-asm --fixture {f} --format s is not yet mapped to a legacy flag; use --format elf"
        else
          Except.ok s!"--solana-{f.drop 7}-elf"
      else if f.startsWith "spl-token-" then
        if fmt == "s" || fmt == "" then
          Except.ok s!"--emit-solana-spl-token-{f.drop 10}-sbpf"
        else
          Except.ok s!"--solana-spl-token-{f.drop 10}-elf"
      else if f == "associated-token-cpi" then
        if fmt == "s" || fmt == "" then
          Except.ok "--emit-solana-associated-token-cpi-sbpf"
        else
          Except.ok "--solana-associated-token-cpi-elf"
      else if f.startsWith "system-" then
        if fmt == "s" || fmt == "" then
          Except.ok s!"--emit-solana-system-{f.drop 7}-sbpf"
        else
          Except.ok s!"--solana-system-{f.drop 7}-elf"
      else if f == "log-event" then
        if fmt == "s" then
          Except.error s!"emit --target solana-sbpf-asm --fixture {f} --format s is not yet mapped to a legacy flag; use --format elf"
        else
          Except.ok "--solana-log-event-elf"
      else
        Except.error s!"emit --target solana-sbpf-asm --fixture {f} is not yet mapped to a legacy flag"
  | "wasm-near", f, "wat" =>
      if ProofForge.Cli.Fixture.isWasmNearFixture f then
        Except.ok s!"--emit-{f}-emitwat"
      else
        Except.error s!"emit --target wasm-near --fixture {f} --format wat is not yet mapped to a legacy flag"
  | "wasm-near", f, _ =>
      if ProofForge.Cli.Fixture.isWasmNearFixture f then
        Except.ok s!"--emit-{f}-ir-wasm-near"
      else
        Except.error s!"emit --target wasm-near --fixture {f} is not yet mapped"
  | "wasm-cosmwasm", "counter", _ => Except.ok "--emit-counter-ir-cosmwasm"
  | "wasm-cloudflare-workers", "counter", _ => Except.ok "--emit-counter-ir-ts"
  | "psy-dpn", f, _ =>
      if ProofForge.Cli.Fixture.supportsFormat "psy-dpn" f .psy then
        Except.ok s!"--emit-{f}-ir-psy"
      else
        Except.error s!"emit --target psy-dpn --fixture {f} is not yet mapped to a legacy flag"
  | "aleo-leo", "counter", _ => Except.ok "--emit-counter-ir-leo"
  | "aleo-leo", "pure-math", _ => Except.ok "--emit-pure-math-ir-leo"
  | "move-aptos", "counter", _ => Except.ok "--emit-counter-ir-aptos"
  | "move-sui", "counter", fmt =>
      if fmt == "" || fmt == "sui" || fmt == "move" then Except.ok "--emit-counter-ir-sui"
      else Except.error s!"emit --target move-sui --fixture counter --format {fmt} is not supported; use --format sui"
  | "quint", f, fmt =>
      if fmt == "scenario" || fmt == "toml" then
        if !ProofForge.Cli.Quint.supportsFixture f then
          Except.error s!"emit --target quint --fixture {f} is not supported; supported fixtures: {String.intercalate ", " ProofForge.Cli.Quint.supportedFixtureIds.toList}"
        else
          Except.ok "--emit-ir-quint-scenario"
      else if fmt == "qnt" || fmt == "" then
        if !ProofForge.Cli.Quint.supportsFixture f then
          Except.error s!"emit --target quint --fixture {f} is not supported; supported fixtures: {String.intercalate ", " ProofForge.Cli.Quint.supportedFixtureIds.toList}"
        else if f == "counter" then
          Except.ok "--emit-counter-ir-quint"
        else if f == "value-vault" then
          Except.ok "--emit-value-vault-ir-quint"
        else
          Except.ok "--emit-ir-quint"
      else
        Except.error s!"emit --target quint --fixture {f} --format {fmt} is not supported; use --format qnt or scenario"
  | t, f, fmt =>
      Except.error s!"emit --target {t} --fixture {f} --format {fmt} is not yet mapped to a legacy flag"

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
    if target == "solana-sbpf-asm" then
      if let some arch := state.solanaSbpfArch? then
        legacy := legacy ++ ["--solana-sbpf-arch", arch]
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
