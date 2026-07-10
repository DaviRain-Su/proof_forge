import ProofForge.Contract.Spec.Json
import ProofForge.Backend.Evm.AbiType
import ProofForge.IR.Contract
import ProofForge.IR.Mutability

namespace ProofForge.Contract.Client

open ProofForge.IR

def evmAbiWrapperPath : String := "proof-forge-evm-abi.ts"

def nearWrapperPath : String := "proof-forge-near.ts"

/-- Spike-level Soroban TypeScript sidecar (not a NEAR wrapper path). -/
def sorobanWrapperPath : String := "proof-forge-soroban.ts"

/-- CosmWasm TypeScript sidecar (not a NEAR wrapper path). -/
def cosmWasmWrapperPath : String := "proof-forge-cosmwasm.ts"

def solanaClientPath : String := "proof-forge-client.ts"

def solanaIdlPath : String := "proof-forge-idl.json"

def typeToTs : ValueType → String
  | .u32 => "number"
  | .u64 => "bigint"
  | .u8 => "number"
  | .u128 => "bigint"
  | .bool => "boolean"
  | .hash => "string"
  | .address => "string"
  | .bytes => "string"
  | .string => "string"
  | .unit => "void"
  | .fixedArray _ _ => "any[]"
  | .structType _ => "Record<string, any>"
  | .array _ => "any[]"

def entrypointParamAbiWord? (entrypoint : Entrypoint) (index : Nat) : Option String :=
  if h : index < entrypoint.paramAbiWords.size then entrypoint.paramAbiWords[index] else none

def paramTypeToTs (entrypoint : Entrypoint) (index : Nat) (type : ValueType) : String :=
  match entrypointParamAbiWord? entrypoint index with
  | some abiWord =>
      if abiWord == "address" || abiWord.startsWith "bytes" then
        "string"
      else if abiWord == "bool" then
        "boolean"
      else
        typeToTs type
  | none => typeToTs type

def abiEntryJson (module : Module) (entrypoint : Entrypoint) : Except String String :=
  match entrypoint.kind with
  | .fallback =>
      .ok "{\"type\":\"fallback\",\"stateMutability\":\"nonpayable\"}"
  | .receive =>
      .ok "{\"type\":\"receive\",\"stateMutability\":\"payable\"}"
  | .function => do
      let mut inputEntries := #[]
      for h : idx in [0:entrypoint.params.size] do
        let param := entrypoint.params[idx]
        let abiType ← ProofForge.Backend.Evm.AbiType.descriptor module
          s!"generated EVM client entrypoint `{entrypoint.name}` parameter `{param.fst}`"
          param.snd (entrypointParamAbiWord? entrypoint idx)
        inputEntries := inputEntries.push (abiType.toJson (some param.fst))
      let inputs := String.intercalate "," inputEntries.toList
      let outputs ←
        if entrypoint.returns == .unit then
          pure "[]"
        else do
          let abiType ← ProofForge.Backend.Evm.AbiType.descriptor module
            s!"generated EVM client entrypoint `{entrypoint.name}` return" entrypoint.returns
          pure ("[" ++ abiType.toJson ++ "]")
      let stateMutability := if entrypoint.mutability == .view then "view" else "nonpayable"
      pure ("{\"name\":\"" ++ entrypoint.name ++ "\",\"type\":\"function\",\"inputs\":[" ++ inputs ++ "],\"outputs\":" ++ outputs ++ ",\"stateMutability\":\"" ++ stateMutability ++ "\"}")

def abiJson (module : Module) : Except String String := do
  let entries ← module.entrypoints.mapM (abiEntryJson module)
  pure ("[" ++ String.intercalate "," entries.toList ++ "]")

def errorCatalogJson (spec : ContractSpec) : String :=
  ProofForge.Contract.Spec.Json.jsonArray
    (ProofForge.Contract.Spec.Json.errorCatalog spec.module |>.map
      ProofForge.Contract.Spec.Json.errorCatalogEntryJson)

def errorCatalogueTs (spec : ContractSpec) : String :=
  String.intercalate "\n" [
    "export const ERRORS = " ++ errorCatalogJson spec ++ " as const;",
    "export type ProofForgeError = (typeof ERRORS)[number];",
    "",
    "export function errorByAssertionId(assertionId: number): ProofForgeError | undefined {",
    "  return ERRORS.find((item) => item.assertionId === assertionId);",
    "}"
  ]

def evmErrorHelpersTs (spec : ContractSpec) : String :=
  String.intercalate "\n" [
    errorCatalogueTs spec,
    "",
    "export type DecodedProofForgeRevert = {",
    "  error: ProofForgeError;",
    "  args: readonly unknown[];",
    "};",
    "",
    "export function decodeProofForgeRevertDetails(error: unknown): DecodedProofForgeRevert | undefined {",
    "  const candidate = error as { data?: unknown; error?: { data?: unknown } };",
    "  const data = typeof candidate?.data === \"string\"",
    "    ? candidate.data",
    "    : typeof candidate?.error?.data === \"string\"",
    "      ? candidate.error.data",
    "      : undefined;",
    "  if (!data) return undefined;",
    "  const hex = data.startsWith(\"0x\") || data.startsWith(\"0X\") ? data.slice(2) : data;",
    "  // PF-P2-02 / E1.1: Solidity custom-error selector (+ optional ABI static args).",
    "  // Selector-only: exactly 4 bytes. With args: 4 + 32*n bytes; match by selector.",
    "  if (hex.length >= 8 && hex.length % 64 === 8) {",
    "    const sel = hex.slice(0, 8).toLowerCase();",
    "    const candidates = ERRORS.filter((item) => (item as { soliditySelector?: string | null }).soliditySelector?.toLowerCase() === sel);",
    "    if (candidates.length !== 1) return undefined;",
    "    const bySel = candidates[0];",
    "    if (bySel) {",
    "      const argTypes = (bySel as { solidityArgTypes?: readonly string[] }).solidityArgTypes ?? [];",
    "      if (hex.length !== 8 + argTypes.length * 64) return undefined;",
    "      try {",
    "        const args = argTypes.length === 0",
    "          ? []",
    "          : Array.from(ethers.AbiCoder.defaultAbiCoder().decode(argTypes, `0x${hex.slice(8)}`));",
    "        return { error: bySel, args };",
    "      } catch {",
    "        return undefined;",
    "      }",
    "    }",
    "  }",
    "  try {",
    "    const [assertionId, userCode] = ethers.AbiCoder.defaultAbiCoder().decode([\"uint32\", \"string\"], data) as [bigint, string];",
    "    const id = Number(assertionId);",
    "    const decodedError = ERRORS.find((item) => item.assertionId === id && (!item.userCode || item.userCode === userCode)) ?? errorByAssertionId(id);",
    "    return decodedError ? { error: decodedError, args: [] } : undefined;",
    "  } catch {",
    "    return undefined;",
    "  }",
    "}",
    "",
    "export function decodeProofForgeRevert(error: unknown): ProofForgeError | undefined {",
    "  return decodeProofForgeRevertDetails(error)?.error;",
    "}"
  ]

def nearErrorHelpersTs (spec : ContractSpec) : String :=
  String.intercalate "\n" [
    errorCatalogueTs spec,
    "",
    "export function parseProofForgePanic(message: string): ProofForgeError | undefined {",
    "  const match = /PF:(\\d+):([^\\s]+)/.exec(message);",
    "  if (!match) return undefined;",
    "  const assertionId = Number(match[1]);",
    "  const userCode = match[2];",
    "  return ERRORS.find((item) => item.assertionId === assertionId && (!item.userCode || item.userCode === userCode)) ?? errorByAssertionId(assertionId);",
    "}"
  ]

def evmEntrypointWrapper (entrypoint : Entrypoint) : String :=
  let params := String.intercalate ", " <| (entrypoint.params.mapIdx fun index p =>
    p.fst ++ ": " ++ paramTypeToTs entrypoint index p.snd).toList
  let argList := String.intercalate ", " (entrypoint.params.map fun p => p.fst).toList
  if entrypoint.mutability == .call then
    if entrypoint.returns == .unit then
      "\nexport async function " ++ entrypoint.name ++ "(" ++ params ++ "): Promise<void> {\n" ++
      "  const tx = await contract.getFunction(\"" ++ entrypoint.name ++ "\")(" ++ argList ++ ");\n" ++
      "  await tx.wait();\n" ++
      "}\n"
    else
      "\nexport async function " ++ entrypoint.name ++ "(" ++ params ++ "): Promise<ethers.ContractTransactionReceipt | null> {\n" ++
      "  const tx = await contract.getFunction(\"" ++ entrypoint.name ++ "\")(" ++ argList ++ ");\n" ++
      "  return await tx.wait();\n" ++
      "}\n"
  else
    "\nexport async function " ++ entrypoint.name ++ "(" ++ params ++ "): Promise<" ++ typeToTs entrypoint.returns ++ "> {\n" ++
    "  return await contract.getFunction(\"" ++ entrypoint.name ++ "\").staticCall(" ++ argList ++ ");\n" ++
    "}\n"

def evmArtifactPathsTs (artifactBaseName : String) : String :=
  String.intercalate "\n" [
    "export const ARTIFACT_BASENAME = \"" ++ artifactBaseName ++ "\";",
    "",
    "export const ARTIFACT_PATHS = {",
    "  runtimeBytecode: \"./" ++ artifactBaseName ++ ".bin\",",
    "  initCode: \"./" ++ artifactBaseName ++ ".init.bin\",",
    "  deployManifest: \"./" ++ artifactBaseName ++ ".proof-forge-deploy.json\",",
    "  contractSpec: \"./" ++ artifactBaseName ++ ".contract-spec.json\",",
    "  client: \"./" ++ evmAbiWrapperPath ++ "\",",
    "} as const;"
  ]

def evmDeployHelpersTs : String :=
  String.intercalate "\n" [
    "export type DeployInitCodeResult = {",
    "  address: string;",
    "  contract: ethers.Contract;",
    "  receipt: ethers.ContractTransactionReceipt | null;",
    "};",
    "",
    "export function readArtifactHex(relativePath: string, baseDir: string): string {",
    "  const fs = require(\"node:fs\") as typeof import(\"node:fs\");",
    "  const path = require(\"node:path\") as typeof import(\"node:path\");",
    "  return fs.readFileSync(path.join(baseDir, relativePath), \"utf8\").trim();",
    "}",
    "",
    "export async function deployInitCode(",
    "  runner: ethers.Signer,",
    "  initCodeHex: string,",
    "): Promise<DeployInitCodeResult> {",
    "  const normalized = initCodeHex.startsWith(\"0x\") ? initCodeHex : `0x${initCodeHex}`;",
    "  const tx = await runner.sendTransaction({ data: normalized });",
    "  const receipt = await tx.wait();",
    "  const address = receipt?.contractAddress;",
    "  if (!address) {",
    "    throw new Error(\"ProofForge deployInitCode: missing contractAddress\");",
    "  }",
    "  const deployed = connect(address, runner);",
    "  return { address, contract: deployed, receipt };",
    "}",
    "",
    "export async function deployFromArtifactDir(",
    "  runner: ethers.Signer,",
    "  artifactDir: string,",
    "  basename: string = ARTIFACT_BASENAME,",
    "): Promise<DeployInitCodeResult> {",
    "  const initCode = readArtifactHex(`./${basename}.init.bin`, artifactDir);",
    "  return deployInitCode(runner, initCode);",
    "}"
  ]

def renderEvmAbiWrapper (spec : ContractSpec) (artifactBaseName : String := spec.name) :
    Except String String := do
  ProofForge.IR.Mutability.validateModule spec.module
  let entrypointLines := String.intercalate "" <|
    (spec.module.entrypoints.filter (fun entrypoint => entrypoint.kind == .function)
      |>.map evmEntrypointWrapper).toList
  let abi ← abiJson spec.module
  pure <| String.intercalate "\n" [
    "/* ProofForge generated EVM ABI wrapper. */",
    "/* eslint-disable @typescript-eslint/no-explicit-any */",
    "import { ethers } from \"ethers\";",
    "",
    "export const ABI = " ++ abi ++ " as const;",
    "",
    evmArtifactPathsTs artifactBaseName,
    "",
    evmErrorHelpersTs spec,
    "",
    evmDeployHelpersTs,
    "",
    "let contract: ethers.Contract;",
    "let iface: ethers.Interface;",
    "",
    "export function connect(address: string, runner: ethers.ContractRunner) {",
    "  iface = new ethers.Interface(ABI);",
    "  contract = new ethers.Contract(address, ABI, runner);",
    "  return contract;",
    "}",
    entrypointLines
  ]

def nearArgsObject (entrypoint : Entrypoint) : String :=
  "{" ++ String.intercalate ", " (entrypoint.params.map fun p => "\"" ++ p.fst ++ "\": " ++ p.fst).toList ++ "}"

def nearEntrypointWrapper (entrypoint : Entrypoint) : String :=
  let params := String.intercalate ", " (entrypoint.params.map fun p => p.fst ++ ": " ++ typeToTs p.snd).toList
  let argsObj := nearArgsObject entrypoint
  if entrypoint.mutability == .call then
    let paramsWithOptions :=
      if params.isEmpty then
        "options: NearCallOptions = {}"
      else
        params ++ ", options: NearCallOptions = {}"
    let returnType :=
      if entrypoint.returns == .unit then "void"
      else "Awaited<ReturnType<Account[\"functionCall\"]>>"
    let returnKeyword := if entrypoint.returns == .unit then "" else "return "
    "\nexport async function " ++ entrypoint.name ++ "(" ++ paramsWithOptions ++ "): Promise<" ++ returnType ++ "> {\n" ++
    "  " ++ returnKeyword ++ "await account.functionCall({\n" ++
    "    contractId,\n" ++
    "    methodName: \"" ++ entrypoint.name ++ "\",\n" ++
    "    args: " ++ argsObj ++ ",\n" ++
    "    gas: options.gas,\n" ++
    "    attachedDeposit: options.attachedDeposit ?? options.deposit,\n" ++
    "  });\n" ++
    "}\n"
  else
    let paramsWithOptions :=
      if params.isEmpty then
        "options: NearViewOptions = {}"
      else
        params ++ ", options: NearViewOptions = {}"
    "\nexport async function " ++ entrypoint.name ++ "(" ++ paramsWithOptions ++ "): Promise<" ++ typeToTs entrypoint.returns ++ "> {\n" ++
    "  return await account.viewFunction({\n" ++
    "    ...options,\n" ++
    "    contractId,\n" ++
    "    methodName: \"" ++ entrypoint.name ++ "\",\n" ++
    "    args: " ++ argsObj ++ ",\n" ++
    "  }) as " ++ typeToTs entrypoint.returns ++ ";\n" ++
    "}\n"

def renderNearWrapper (spec : ContractSpec) : String :=
  let entrypointLines := String.intercalate "" (spec.module.entrypoints.map nearEntrypointWrapper).toList
  String.intercalate "\n" [
    "/* ProofForge generated NEAR wrapper. */",
    "/* eslint-disable @typescript-eslint/no-explicit-any */",
    "import { Account } from \"near-api-js\";",
    "",
    nearErrorHelpersTs spec,
    "",
    "export type NearCallOptions = {",
    "  gas?: bigint | string | number;",
    "  attachedDeposit?: bigint | string | number;",
    "  deposit?: bigint | string | number;",
    "};",
    "",
    "export type NearViewOptions = {",
    "  finality?: string;",
    "  blockId?: string | number;",
    "  [key: string]: unknown;",
    "};",
    "",
    "let contractId: string;",
    "let account: Account;",
    "",
    "export function connect(id: string, signer: Account) {",
    "  contractId = id;",
    "  account = signer;",
    "}",
    entrypointLines
  ]

/-- Minimal Soroban client stub for the Spike host-family adapter (PF-P0-04).
Does not import NEAR packages; full Stellar client wiring remains follow-on work. -/
def renderSorobanWrapper (spec : ContractSpec) : String :=
  let names := String.intercalate ", " (spec.module.entrypoints.map (fun e => e.name)).toList
  let quoted := String.intercalate ", " (spec.module.entrypoints.map (fun e => "\"" ++ e.name ++ "\"")).toList
  String.intercalate "\n" [
    "/* ProofForge generated Soroban wrapper (Spike). */",
    "/* Target: wasm-stellar-soroban — not a NEAR client. */",
    "/* eslint-disable @typescript-eslint/no-explicit-any */",
    "",
    "export type SorobanCallOptions = {",
    "  // Follow-on: Stellar RPC / auth / TTL options.",
    "  [key: string]: unknown;",
    "};",
    "",
    "let contractId: string;",
    "",
    "export function connect(id: string) {",
    "  contractId = id;",
    "}",
    "",
    "export const entrypoints = [" ++ quoted ++ "] as const;",
    "",
    "// Declared entrypoints: " ++ names,
    "export function getContractId(): string {",
    "  return contractId;",
    "}",
    ""
  ]

def renderCosmWasmWrapper (spec : ContractSpec) : String :=
  let names := String.intercalate ", " (spec.module.entrypoints.map (fun e => e.name)).toList
  let quoted := String.intercalate ", " (spec.module.entrypoints.map (fun e => "\"" ++ e.name ++ "\"")).toList
  String.intercalate "\n" [
    "/* ProofForge generated CosmWasm wrapper (Counter MVP / PF-P3-02). */",
    "/* Target: wasm-cosmwasm — not a NEAR client. */",
    "/* eslint-disable @typescript-eslint/no-explicit-any */",
    "",
    "export type CosmWasmCallOptions = {",
    "  // Follow-on: CosmWasm RPC / funds / gas options.",
    "  [key: string]: unknown;",
    "};",
    "",
    "let contractAddress: string;",
    "",
    "export function connect(address: string) {",
    "  contractAddress = address;",
    "}",
    "",
    "export const entrypoints = [" ++ quoted ++ "] as const;",
    "",
    "// Declared entrypoints: " ++ names,
    "export function getContractAddress(): string {",
    "  return contractAddress;",
    "}",
    ""
  ]

end ProofForge.Contract.Client
