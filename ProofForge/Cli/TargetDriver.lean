import ProofForge.Cli.Fixture
import ProofForge.Cli.Quint

namespace ProofForge.Cli

/-- Inputs for target-first `build` legacy-flag resolution. -/
structure BuildRequest where
  input? : Option String := none
  fixture? : Option String := none
  format? : Option String := none
  token : Bool := false
  deriving Inhabited

/-- Inputs for target-first `emit` legacy-flag resolution. -/
structure EmitRequest where
  fixture : String
  format? : Option String := none
  deriving Inhabited

/-- Per-target CLI driver (PF-P1-01 compat surface).

Owns build/emit legacy-flag mapping until emit modes are absorbed into real
package operations. Registered by target id so `TargetFirst` dispatches via
lookup rather than a central target-id match. -/
structure TargetCliDriver where
  id : String
  resolveBuild : BuildRequest → Except String String
  resolveEmit : EmitRequest → Except String String

def isLeanSourceFile (input? : Option String) : Bool :=
  match input? with
  | some path => path.endsWith ".lean"
  | none => false

/-- Stable diagnostic for fixture-only targets that must not silently lower Counter. -/
def sourceInputUnsupported (target : String) : String :=
  s!"proof-forge build --target {target}: source input is not supported; \
use `proof-forge emit --target {target} --fixture <id>` for the Counter spike surface"

def isLearnInput (input? : Option String) : Bool :=
  match input? with
  | some input => input.endsWith ".learn"
  | none => false

/-! ### Primary triad drivers -/

def evmResolveBuild (req : BuildRequest) : Except String String :=
  let isLearn := isLearnInput req.input?
  let isLeanSource := isLeanSourceFile req.input?
  if isLearn then
    match req.format?, req.token with
    | some "yul", false => Except.ok "--learn-yul"
    | some "yul", true =>
        Except.error "proof-forge build --target evm --token --format yul is not yet implemented"
    | some "bytecode", true => Except.ok "--learn-token"
    | some "bytecode", false => Except.ok "--learn"
    | none, true => Except.ok "--learn-token"
    | none, false => Except.ok "--learn"
    | some _, true => Except.ok "--learn-token"
    | some _, false => Except.ok "--learn"
  else if req.token then
    match req.format? with
    | some "yul" =>
        if isLeanSource then
          Except.error "proof-forge build --target evm --token --format yul is not yet implemented"
        else
          Except.error "proof-forge build --target evm --token requires a .lean TokenSpec or .learn token source"
    | _ =>
        if isLeanSource then
          Except.ok "--learn-token"
        else
          Except.error "proof-forge build --target evm --token requires a .lean TokenSpec or .learn token source"
  else if req.format? == some "yul" then
    if req.input?.isSome then Except.ok "--evm-bytecode" else Except.ok "--emit-counter-ir-yul"
  else
    if req.input?.isSome then Except.ok "--evm-bytecode" else Except.ok "--emit-counter-ir-bytecode"

def evmResolveEmit (req : EmitRequest) : Except String String :=
  let format := req.format?.getD ""
  match req.fixture, format with
  | f, "yul" =>
      if f == "array-abi" then
        Except.ok "--emit-evm-array-abi-ir-yul"
      else
        Except.ok s!"--emit-{f}-ir-yul"
  | f, "bytecode" =>
      if f == "array-abi" then
        Except.ok "--emit-evm-array-abi-ir-bytecode"
      else
        Except.ok s!"--emit-{f}-ir-bytecode"
  | f, fmt =>
      Except.error s!"emit --target evm --fixture {f} --format {fmt} is not yet mapped to a legacy flag"

def solanaResolveBuild (req : BuildRequest) : Except String String :=
  let isLearn := isLearnInput req.input?
  let isLeanSource := isLeanSourceFile req.input?
  match isLearn, req.token with
  | true, true => Except.ok "--learn-token"
  | true, false => Except.ok "--learn"
  | false, true =>
      if isLeanSource then
        Except.ok "--learn-token"
      else
        Except.error "proof-forge build --target solana-sbpf-asm --token requires a .lean TokenSpec or .learn token source"
  | false, false =>
      if isLeanSource then
        -- Default final artifact is ELF (PF-P0-03). `--format s` is the
        -- toolchain-free assembly intermediate for static product CI.
        if req.format? == some "s" then
          Except.ok "--contract-source-sbpf"
        else if req.format?.isNone || req.format? == some "elf" || req.format? == some "so" then
          Except.ok "--contract-source-solana-elf"
        else
          Except.error
            s!"proof-forge build --target solana-sbpf-asm does not support format '{req.format?.getD ""}'; use --format s or --format elf"
      else if req.format? == some "s" || req.format?.isNone then
        Except.ok "--emit-counter-ir-sbpf"
      else
        Except.error s!"proof-forge build --target solana-sbpf-asm does not support format '{req.format?.getD ""}' without a Lean contract source input"

def solanaResolveEmit (req : EmitRequest) : Except String String :=
  let fmt := req.format?.getD ""
  let f := req.fixture
  if f == "counter" then
    if fmt == "elf" || fmt == "so" then
      Except.ok "--solana-elf"
    else
      Except.ok "--emit-counter-ir-sbpf"
  else if f == "value-vault" then
    if fmt == "elf" || fmt == "so" then
      Except.ok "--value-vault-solana-elf"
    else
      Except.ok "--emit-value-vault-ir-sbpf"
  else if f == "error-ref" then
    Except.ok "--emit-error-ref-ir-sbpf"
  else if f == "control" then
    Except.ok "--emit-control-ir-sbpf"
  else if f == "solana-sdk" then
    Except.ok "--emit-solana-sdk-sbpf"
  else if f == "canned-entrypoint" then
    Except.ok "--emit-sbpf-asm"
  else if f.startsWith "solana-" then
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

def nearResolveBuild (req : BuildRequest) : Except String String :=
  let isLearn := isLearnInput req.input?
  let isLeanSource := isLeanSourceFile req.input?
  if isLearn then
    Except.error "proof-forge build --target wasm-near from .learn source is not yet implemented"
  else if req.token then
    if isLeanSource then
      Except.ok "--learn-token"
    else
      Except.error "proof-forge build --target wasm-near --token requires a .lean TokenSpec or .learn token source"
  else if isLeanSource then
    if req.format?.isSome && req.format? != some "wat" then
      Except.error s!"proof-forge build --target wasm-near does not support format '{req.format?.getD ""}'; use --format wat"
    else
      Except.ok "--contract-source-emitwat"
  else if req.input?.isSome then
    Except.error "proof-forge build --target wasm-near from Lean source is not yet implemented; use a .lean contract_source module"
  else
    if req.format?.isSome && req.format? != some "wat" then
      Except.error s!"proof-forge build --target wasm-near does not support format '{req.format?.getD ""}'; use --format wat"
    else
      let fixture := req.fixture?.getD "counter"
      if ProofForge.Cli.Fixture.isWasmNearFixture fixture then
        Except.ok s!"--emit-{fixture}-emitwat"
      else
        Except.error s!"proof-forge build --target wasm-near --fixture {fixture} is not yet implemented"

def nearResolveEmit (req : EmitRequest) : Except String String :=
  let f := req.fixture
  let format := req.format?.getD ""
  if format == "wat" then
    if ProofForge.Cli.Fixture.isWasmNearFixture f then
      Except.ok s!"--emit-{f}-emitwat"
    else
      Except.error s!"emit --target wasm-near --fixture {f} --format wat is not yet mapped to a legacy flag"
  else
    if ProofForge.Cli.Fixture.isWasmNearFixture f then
      Except.ok s!"--emit-{f}-ir-wasm-near"
    else
      Except.error s!"emit --target wasm-near --fixture {f} is not yet mapped"

/-! ### Secondary / fixture drivers -/

def sorobanResolveBuild (req : BuildRequest) : Except String String :=
  let isLearn := isLearnInput req.input?
  let isLeanSource := isLeanSourceFile req.input?
  if isLearn then
    Except.error "proof-forge build --target wasm-stellar-soroban from .learn source is not yet implemented"
  else if req.token then
    Except.error
      "proof-forge build --target wasm-stellar-soroban --token: no TokenSpec lane; \
use --target evm | solana-sbpf-asm | wasm-near (see `just token-feature-matrix`)"
  else if isLeanSource then
    if req.format?.isSome && req.format? != some "wat" then
      Except.error s!"proof-forge build --target wasm-stellar-soroban does not support format '{req.format?.getD ""}'; use --format wat"
    else
      Except.ok "--contract-source-emitwat"
  else
    Except.error "proof-forge build --target wasm-stellar-soroban requires a .lean contract_source module"

def sorobanResolveEmit (req : EmitRequest) : Except String String :=
  Except.error s!"emit --target wasm-stellar-soroban --fixture {req.fixture} --format {req.format?.getD ""} is not yet mapped to a legacy flag"

def fixtureOnlyBuild (target flag : String) (req : BuildRequest) : Except String String :=
  if req.input?.isSome then
    Except.error (sourceInputUnsupported target)
  else
    Except.ok flag

def cosmwasmResolveBuild (req : BuildRequest) : Except String String :=
  if isLearnInput req.input? then
    Except.error "proof-forge build --target wasm-cosmwasm from .learn source is not yet implemented"
  else
    fixtureOnlyBuild "wasm-cosmwasm" "--emit-counter-ir-cosmwasm" req

def cosmwasmResolveEmit (req : EmitRequest) : Except String String :=
  if req.fixture == "counter" then
    Except.ok "--emit-counter-ir-cosmwasm"
  else
    Except.error s!"emit --target wasm-cosmwasm --fixture {req.fixture} --format {req.format?.getD ""} is not yet mapped to a legacy flag"

def psyResolveBuild (req : BuildRequest) : Except String String :=
  if isLearnInput req.input? then
    Except.error "proof-forge build --target psy-dpn from .learn source is not yet implemented"
  else
    fixtureOnlyBuild "psy-dpn" "--emit-counter-ir-psy" req

def psyResolveEmit (req : EmitRequest) : Except String String :=
  if ProofForge.Cli.Fixture.supportsFormat "psy-dpn" req.fixture .psy then
    Except.ok s!"--emit-{req.fixture}-ir-psy"
  else
    Except.error s!"emit --target psy-dpn --fixture {req.fixture} is not yet mapped to a legacy flag"

def aleoResolveBuild (req : BuildRequest) : Except String String :=
  if isLearnInput req.input? then
    Except.error "proof-forge build --target aleo-leo from .learn source is not yet implemented"
  else
    fixtureOnlyBuild "aleo-leo" "--emit-counter-ir-leo" req

def aleoResolveEmit (req : EmitRequest) : Except String String :=
  match req.fixture with
  | "counter" => Except.ok "--emit-counter-ir-leo"
  | "pure-math" => Except.ok "--emit-pure-math-ir-leo"
  | f => Except.error s!"emit --target aleo-leo --fixture {f} --format {req.format?.getD ""} is not yet mapped to a legacy flag"

def aptosResolveBuild (req : BuildRequest) : Except String String :=
  if isLearnInput req.input? then
    Except.error "proof-forge build --target move-aptos from .learn source is not yet implemented"
  else
    fixtureOnlyBuild "move-aptos" "--emit-counter-ir-aptos" req

def aptosResolveEmit (req : EmitRequest) : Except String String :=
  if req.fixture == "counter" then
    Except.ok "--emit-counter-ir-aptos"
  else
    Except.error s!"emit --target move-aptos --fixture {req.fixture} --format {req.format?.getD ""} is not yet mapped to a legacy flag"

def suiResolveBuild (req : BuildRequest) : Except String String :=
  if isLearnInput req.input? then
    Except.error "proof-forge build --target move-sui from .learn source is not yet implemented"
  else if req.input?.isSome then
    Except.error (sourceInputUnsupported "move-sui")
  else
    match req.fixture? with
    | some fixture =>
        if fixture == "counter" then Except.ok "--emit-counter-ir-sui"
        else Except.error s!"proof-forge build --target move-sui --fixture {fixture} is not yet implemented"
    | none => Except.ok "--emit-counter-ir-sui"

def suiResolveEmit (req : EmitRequest) : Except String String :=
  let fmt := req.format?.getD ""
  if req.fixture == "counter" then
    if fmt == "" || fmt == "sui" || fmt == "move" then Except.ok "--emit-counter-ir-sui"
    else Except.error s!"emit --target move-sui --fixture counter --format {fmt} is not supported; use --format sui"
  else
    Except.error s!"emit --target move-sui --fixture {req.fixture} --format {fmt} is not yet mapped to a legacy flag"

def cloudflareResolveBuild (req : BuildRequest) : Except String String :=
  if isLearnInput req.input? then
    Except.error "proof-forge build --target wasm-cloudflare-workers from .learn source is not yet implemented"
  else if req.input?.isSome then
    Except.error (sourceInputUnsupported "wasm-cloudflare-workers")
  else
    Except.error
      "proof-forge build --target wasm-cloudflare-workers is fixture-only; \
use `proof-forge emit --target wasm-cloudflare-workers --fixture counter`"

def cloudflareResolveEmit (req : EmitRequest) : Except String String :=
  if req.fixture == "counter" then
    Except.ok "--emit-counter-ir-ts"
  else
    Except.error s!"emit --target wasm-cloudflare-workers --fixture {req.fixture} --format {req.format?.getD ""} is not yet mapped to a legacy flag"

/-- CLI-only verification target (not in `Target.knownIds`). -/
def quintResolveBuild (_req : BuildRequest) : Except String String :=
  Except.error "unknown target 'quint'"

def quintResolveEmit (req : EmitRequest) : Except String String :=
  let f := req.fixture
  let fmt := req.format?.getD ""
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

/-- All registered CLI drivers. Adding a target requires a new entry here (or
a backend module that contributes one) — not a new arm in `TargetFirst`. -/
def cliDrivers : Array TargetCliDriver := #[
  { id := "evm", resolveBuild := evmResolveBuild, resolveEmit := evmResolveEmit },
  { id := "solana-sbpf-asm", resolveBuild := solanaResolveBuild, resolveEmit := solanaResolveEmit },
  { id := "wasm-near", resolveBuild := nearResolveBuild, resolveEmit := nearResolveEmit },
  { id := "wasm-stellar-soroban", resolveBuild := sorobanResolveBuild, resolveEmit := sorobanResolveEmit },
  { id := "wasm-cosmwasm", resolveBuild := cosmwasmResolveBuild, resolveEmit := cosmwasmResolveEmit },
  { id := "psy-dpn", resolveBuild := psyResolveBuild, resolveEmit := psyResolveEmit },
  { id := "aleo-leo", resolveBuild := aleoResolveBuild, resolveEmit := aleoResolveEmit },
  { id := "move-aptos", resolveBuild := aptosResolveBuild, resolveEmit := aptosResolveEmit },
  { id := "move-sui", resolveBuild := suiResolveBuild, resolveEmit := suiResolveEmit },
  { id := "wasm-cloudflare-workers", resolveBuild := cloudflareResolveBuild, resolveEmit := cloudflareResolveEmit },
  { id := "quint", resolveBuild := quintResolveBuild, resolveEmit := quintResolveEmit }
]

def findCliDriver? (id : String) : Option TargetCliDriver :=
  cliDrivers.find? (fun driver => driver.id == id)

/-- Registry-backed build flag resolution (replaces the central target-id match). -/
def resolveBuildLegacyFlag (target : String) (req : BuildRequest) : Except String String :=
  match findCliDriver? target with
  | some driver => driver.resolveBuild req
  | none => Except.error s!"unknown target '{target}'"

/-- Registry-backed emit flag resolution (replaces the central target-id match). -/
def resolveEmitLegacyFlag (target : String) (req : EmitRequest) : Except String String :=
  match findCliDriver? target with
  | some driver => driver.resolveEmit req
  | none =>
      Except.error s!"emit --target {target} --fixture {req.fixture} --format {req.format?.getD ""} is not yet mapped to a legacy flag"

end ProofForge.Cli
