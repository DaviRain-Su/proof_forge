import ProofForge.Contract.Spec.Json
import ProofForge.Backend.Evm.AbiType
import ProofForge.Backend.WasmHost.NearAbiPlan
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

def returnTypeToTs (entrypoint : Entrypoint) : String :=
  match entrypoint.returnAbiWord? with
  | some abiWord =>
      if abiWord == "address" || abiWord.startsWith "bytes" then
        "string"
      else if abiWord == "bool" then
        "boolean"
      else
        typeToTs entrypoint.returns
  | none => typeToTs entrypoint.returns

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
            entrypoint.returnAbiWord?
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
    "\nexport async function " ++ entrypoint.name ++ "(" ++ params ++ "): Promise<" ++ returnTypeToTs entrypoint ++ "> {\n" ++
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

partial def nearBorshSchemaExpr (structs : Array StructDecl) : ValueType → String
  | .u8 => "\"u8\""
  | .u32 => "\"u32\""
  | .u64 | .address => "\"u64\""
  | .u128 => "\"u128\""
  | .bool => "\"bool\""
  | .hash => "\"hash\""
  | .fixedArray element length =>
      "{ kind: \"fixedArray\", element: " ++ nearBorshSchemaExpr structs element ++
        ", length: " ++ toString length ++ " }"
  | .structType name =>
      match structs.find? (fun decl => decl.name == name) with
      | none => "\"unsupported\""
      | some decl =>
          let fields := String.intercalate ", " <| (decl.fields.map fun field =>
            "{ name: \"" ++ field.id ++ "\", schema: " ++ nearBorshSchemaExpr structs field.type ++ " }").toList
          "{ kind: \"struct\", fields: [" ++ fields ++ "] }"
  | _ => "\"unsupported\""

def nearBorshArgsExpr (structs : Array StructDecl) (entrypoint : Entrypoint)
    (abiPlan : ProofForge.Backend.WasmHost.NearAbiPlan.EntrypointPlan) : String :=
  let types := String.intercalate ", " (abiPlan.params.map fun p => nearBorshSchemaExpr structs p.type).toList
  let values := String.intercalate ", " (entrypoint.params.map (fun p => p.fst)).toList
  "encodeNearBorshArgs([" ++ types ++ "], [" ++ values ++ "])"

def nearDecodeResultExpr (structs : Array StructDecl) (type : ValueType) (bytesExpr : String) : String :=
  match type with
  | .u64 | .address => "decodeNearBorshU64(" ++ bytesExpr ++ ")"
  | .u32 => "decodeNearBorshU32(" ++ bytesExpr ++ ")"
  | .bool => "decodeNearBorshBool(" ++ bytesExpr ++ ")"
  | .unit => "undefined"
  | _ => "decodeNearBorshResult(" ++ nearBorshSchemaExpr structs type ++ ", " ++ bytesExpr ++ ")"

def nearEntrypointWrapperWithPlan (entrypoint : Entrypoint)
    (abiPlan : ProofForge.Backend.WasmHost.NearAbiPlan.EntrypointPlan)
    (structs : Array StructDecl := #[]) : String :=
  let params := String.intercalate ", " (entrypoint.params.map fun p => p.fst ++ ": " ++ typeToTs p.snd).toList
  let argsBytes := nearBorshArgsExpr structs entrypoint abiPlan
  if entrypoint.mutability == .call then
    let paramsWithOptions :=
      if params.isEmpty then
        "options: NearCallOptions = {}"
      else
        params ++ ", options: NearCallOptions = {}"
    let returnType :=
      if entrypoint.returns == .unit then "void"
      else "unknown"
    let returnKeyword := if entrypoint.returns == .unit then "" else "return "
    "\nexport async function " ++ entrypoint.name ++ "(" ++ paramsWithOptions ++ "): Promise<" ++ returnType ++ "> {\n" ++
    "  " ++ returnKeyword ++ "await nearFunctionCallBorsh({\n" ++
    "    contractId,\n" ++
    "    methodName: \"" ++ entrypoint.name ++ "\",\n" ++
    "    args: " ++ argsBytes ++ ",\n" ++
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
    "  const result = await nearViewFunctionBorsh({\n" ++
    "    ...options,\n" ++
    "    contractId,\n" ++
    "    methodName: \"" ++ entrypoint.name ++ "\",\n" ++
    "    args: " ++ argsBytes ++ ",\n" ++
    "  });\n" ++
    "  return " ++ nearDecodeResultExpr structs abiPlan.returnType "result" ++ " as " ++ typeToTs abiPlan.returnType ++ ";\n" ++
    "}\n"

def nearEntrypointWrapper (entrypoint : Entrypoint) : String :=
  match ProofForge.Backend.WasmHost.NearAbiPlan.buildEntrypointPlan #[] entrypoint with
  | .ok plan => nearEntrypointWrapperWithPlan entrypoint plan
  | .error _ => ""

def nearBorshHelpersTs : String :=
  String.intercalate "\n" [
    "type NearBorshScalar = \"u8\" | \"u32\" | \"u64\" | \"u128\" | \"bool\" | \"hash\";",
    "type NearBorshSchema = NearBorshScalar | { kind: \"fixedArray\"; element: NearBorshSchema; length: number } | { kind: \"struct\"; fields: readonly { name: string; schema: NearBorshSchema }[] };",
    "function pushLe(out: number[], value: bigint, width: number) { for (let i = 0; i < width; i++) out.push(Number((value >> BigInt(i * 8)) & 255n)); }",
    "function encodeNearBorshValue(schema: NearBorshSchema, value: unknown, out: number[]): void {",
    "  if (typeof schema === \"string\") { if (schema === \"bool\") out.push(value ? 1 : 0); else if (schema === \"u8\") pushLe(out, BigInt(value as number | bigint), 1); else if (schema === \"u32\") pushLe(out, BigInt(value as number | bigint), 4); else if (schema === \"u64\") pushLe(out, BigInt(value as number | bigint), 8); else if (schema === \"u128\") pushLe(out, BigInt(value as number | bigint), 16); else { const hex = String(value).replace(/^0x/, \"\"); if (hex.length !== 64) throw new Error(\"NEAR Borsh hash must be 32 bytes\"); for (let i = 0; i < 64; i += 2) out.push(Number.parseInt(hex.slice(i, i + 2), 16)); } return; }",
    "  if (schema.kind === \"fixedArray\") { const values = value as readonly unknown[]; if (values.length !== schema.length) throw new Error(`NEAR Borsh array length ${values.length}, expected ${schema.length}`); values.forEach((item) => encodeNearBorshValue(schema.element, item, out)); return; }",
    "  const record = value as Record<string, unknown>; schema.fields.forEach((field) => encodeNearBorshValue(field.schema, record[field.name], out));",
    "}",
    "export function encodeNearBorshArgs(types: readonly NearBorshSchema[], values: readonly unknown[]): Uint8Array {",
    "  if (types.length !== values.length) throw new Error(\"NEAR Borsh argument arity mismatch\"); const out: number[] = []; types.forEach((type, index) => encodeNearBorshValue(type, values[index], out));",
    "  return Uint8Array.from(out);",
    "}",
    "function readLe(bytes: Uint8Array, width: number): bigint { if (bytes.length !== width) throw new Error(`NEAR Borsh result length ${bytes.length}, expected ${width}`); let value = 0n; for (let i = 0; i < width; i++) value |= BigInt(bytes[i]) << BigInt(i * 8); return value; }",
    "function decodeNearBorshValue(schema: NearBorshSchema, bytes: Uint8Array, cursor: { offset: number }): unknown { const take = (width: number) => { const part = bytes.slice(cursor.offset, cursor.offset + width); if (part.length !== width) throw new Error(\"truncated NEAR Borsh result\"); cursor.offset += width; return part; }; if (typeof schema === \"string\") { if (schema === \"bool\") { const value = take(1)[0]; if (value > 1) throw new Error(\"invalid NEAR Borsh bool\"); return value === 1; } if (schema === \"hash\") return Array.from(take(32), (byte) => byte.toString(16).padStart(2, \"0\")).join(\"\"); const width = schema === \"u8\" ? 1 : schema === \"u32\" ? 4 : schema === \"u64\" ? 8 : 16; const value = readLe(take(width), width); return schema === \"u8\" || schema === \"u32\" ? Number(value) : value; } if (schema.kind === \"fixedArray\") return Array.from({ length: schema.length }, () => decodeNearBorshValue(schema.element, bytes, cursor)); const result: Record<string, unknown> = {}; schema.fields.forEach((field) => { result[field.name] = decodeNearBorshValue(field.schema, bytes, cursor); }); return result; }",
    "export function decodeNearBorshResult(schema: NearBorshSchema, bytes: Uint8Array): unknown { const cursor = { offset: 0 }; const value = decodeNearBorshValue(schema, bytes, cursor); if (cursor.offset !== bytes.length) throw new Error(`NEAR Borsh result has ${bytes.length - cursor.offset} trailing bytes`); return value; }",
    "export const decodeNearBorshU64 = (bytes: Uint8Array): bigint => readLe(bytes, 8);",
    "export const decodeNearBorshU32 = (bytes: Uint8Array): number => Number(readLe(bytes, 4));",
    "export const decodeNearBorshBool = (bytes: Uint8Array): boolean => { if (bytes.length !== 1 || bytes[0] > 1) throw new Error(\"invalid NEAR Borsh bool\"); return bytes[0] === 1; };",
    "function bytesToBase64(bytes: Uint8Array): string { let raw = \"\"; for (const byte of bytes) raw += String.fromCharCode(byte); return btoa(raw); }",
    "async function nearViewFunctionBorsh(request: { contractId: string; methodName: string; args: Uint8Array; finality?: string; blockId?: string | number; [key: string]: unknown }): Promise<Uint8Array> {",
    "  const { contractId, methodName, args, finality, blockId } = request;",
    "  const response = await (account as any).connection.provider.query({ request_type: \"call_function\", account_id: contractId, method_name: methodName, args_base64: bytesToBase64(args), ...(blockId !== undefined ? { block_id: blockId } : { finality: finality ?? \"final\" }) });",
    "  return Uint8Array.from(response.result as number[]);",
    "}",
    "async function nearFunctionCallBorsh(request: { contractId: string; methodName: string; args: Uint8Array; gas?: bigint | string | number; attachedDeposit?: bigint | string | number }): Promise<unknown> {",
    "  return (account as any).signAndSendTransaction({ receiverId: request.contractId, actions: [transactions.functionCall(request.methodName, request.args, BigInt(request.gas ?? 30000000000000n), BigInt(request.attachedDeposit ?? 0n))] });",
    "}"
  ]

def renderNearWrapperChecked (spec : ContractSpec) : Except String String := do
  let plans <- ProofForge.Backend.WasmHost.NearAbiPlan.buildModulePlans spec.module
  let entrypointLines := String.intercalate "" <| (spec.module.entrypoints.filterMap fun entrypoint =>
    plans.find? (fun plan => plan.name == entrypoint.name) |>.map
      (fun plan => nearEntrypointWrapperWithPlan entrypoint plan spec.module.structs)).toList
  return String.intercalate "\n" [
    "/* ProofForge generated NEAR wrapper. */",
    "/* eslint-disable @typescript-eslint/no-explicit-any */",
    "import { Account, transactions } from \"near-api-js\";",
    "",
    nearErrorHelpersTs spec,
    "",
    nearBorshHelpersTs,
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

def renderNearWrapper (spec : ContractSpec) : String :=
  match renderNearWrapperChecked spec with
  | .ok wrapper => wrapper
  | .error error => s!"/* ProofForge refused NEAR client generation: {error} */"

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
