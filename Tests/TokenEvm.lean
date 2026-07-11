import ProofForge.Contract.Token.EvmSpec
import ProofForge.Contract.Token.EvmWrap
import ProofForge.Contract.Token.Learn
import ProofForge.Backend.Evm.IR

namespace ProofForge.Tests.TokenEvm

open ProofForge.Contract.Token
open ProofForge.Contract.Token.Learn

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then
    pure ()
  else
    throw <| IO.userError message

def parseFixture (path : String) : IO TokenDecl := do
  match (← parseFile (System.FilePath.mk path)) with
  | .ok decl => pure decl
  | .error err => throw <| IO.userError err

def renderLearnTokenYul (decl : TokenDecl) : IO String := do
  let module := ProofForge.Contract.Token.EvmSpec.moduleFor decl.spec
  let runtimeObject ←
    match ProofForge.Backend.Evm.IR.lowerModule module with
    | .ok obj => pure obj
    | .error err => throw <| IO.userError err.render
  match ProofForge.Contract.Token.EvmWrap.wrapRuntimeObject
      decl.id (decl.id ++ "Runtime") runtimeObject decl.spec with
  | .ok yul => pure yul
  | .error err => throw <| IO.userError err

def main : IO UInt32 := do
  let proofToken ← parseFixture "Examples/Backend/Learn/ProofToken.learn"
  let yul ← renderLearnTokenYul proofToken

  require (yul.contains "object \"ProofToken\"") "ERC-20 Yul missing token object"
  require
    (yul.contains
      "sstore(0, or(and(1000000, 18446744073709551615), shl(64, and(9, 18446744073709551615))))")
    "ERC-20 Yul missing packed initial scalar storage"
  require (yul.contains "sstore(mapSlot(1, caller()), 1000000)")
    "ERC-20 Yul missing deployer initial balance"
  require (yul.contains "case 0x18160ddd") "ERC-20 Yul missing totalSupply selector"
  require (yul.contains "case 0x70a08231") "ERC-20 Yul missing balanceOf(address) selector"
  require (yul.contains "case 0xa9059cbb") "ERC-20 Yul missing transfer(address,uint256) selector"
  require (yul.contains "case 0x095ea7b3") "ERC-20 Yul missing approve(address,uint256) selector"
  require (yul.contains "case 0xdd62ed3e") "ERC-20 Yul missing allowance(address,address) selector"
  require (yul.contains "case 0x23b872dd") "ERC-20 Yul missing transferFrom(address,address,uint256) selector"
  require (yul.contains "case 0x313ce567") "ERC-20 Yul missing decimals() selector"
  require (yul.contains "case 0x40c10f19") "mintable ERC-20 Yul missing mint selector"
  require (yul.contains "case 0x42966c68") "burnable ERC-20 Yul missing burn selector"
  require (yul.contains "log3(") "ERC-20 Yul missing indexed event emission"

  let feeToken ← parseFixture "Examples/Backend/Learn/FeeToken.learn"
  match validateEvmTokenFeatures feeToken.spec with
  | .ok _ => throw <| IO.userError "EVM wrapper policy accepted transfer-fee TokenSpec"
  | .error err =>
      require (err.contains "transfer_fee")
        s!"unexpected EVM transfer-fee rejection: {err}"

  let oversizedSpec : TokenSpec := {
    name := "Oversized EVM Supply"
    symbol := "BIG"
    decimals := 18
    initialSupply? := some 18446744073709551616
  }
  let oversizedRuntimeObject ←
    match ProofForge.Backend.Evm.IR.lowerModule
        (ProofForge.Contract.Token.EvmSpec.moduleFor oversizedSpec) with
    | .ok obj => pure obj
    | .error err => throw <| IO.userError err.render
  match ProofForge.Contract.Token.EvmWrap.wrapRuntimeObject
      "Oversized" "OversizedRuntime" oversizedRuntimeObject oversizedSpec with
  | .ok _ => throw <| IO.userError "EVM wrapper accepted initial supply above u64 storage"
  | .error err =>
      require (err.contains "initialSupply" && err.contains "u64")
        s!"unexpected EVM wrapper oversized-supply diagnostic: {err}"

  -- TokenSpec + permit → ERC20Permit addon (ecrecover helpers)
  let permitSpec : TokenSpec := {
    name := "PermitToken"
    symbol := "PT"
    decimals := 18
    features := #[.mintable, .permit]
  }
  let permitMod := ProofForge.Contract.Token.EvmSpec.moduleFor permitSpec
  require (permitMod.entrypoints.any (·.name == "permit")) "permit entry present"
  require (permitMod.entrypoints.any (·.name == "nonces")) "nonces entry present"
  require (permitMod.state.any (fun s => s.id == "nonces")) "nonces state"
  require (!(permitMod.entrypoints.any (·.name == "setPermitSig"))) "no signature staging entry"
  require (!(permitMod.state.any (fun s => #["permitV", "permitR", "permitS"].contains s.id)))
    "no signature staging state"
  let some permitEntry := permitMod.entrypoints.find? (·.name == "permit")
    | throw <| IO.userError "permit entry missing"
  require (permitEntry.selector? == some "d505accf") "canonical seven-arg permit selector"
  require (permitEntry.params.size == 7) "permit must have seven atomic arguments"
  let some domainInit := permitMod.entrypoints.find? (·.name == "initDomain")
    | throw <| IO.userError "initDomain entry missing"
  require (domainInit.selector? == some "3c0ad216") "canonical initDomain(bytes32) selector"
  require (permitMod.capabilities.any (· == .cryptoEcrecover)) "crypto.ecrecover cap"
  match ProofForge.Backend.Evm.IR.renderModule permitMod with
  | .error e => throw <| IO.userError s!"permit token Yul: {e.message}"
  | .ok permitYul =>
      require (permitYul.contains "case 0xd505accf") "permit selector"
      require (permitYul.contains "case 0x7ecebe00") "nonces selector"
      require (permitYul.contains "__proof_forge_ecrecover") "ecrecover helper"
      require (permitYul.contains "__proof_forge_eip712_permit_digest") "eip712 digest helper"

  IO.println "token-evm: ok"
  return 0

end ProofForge.Tests.TokenEvm

def main : IO UInt32 :=
  ProofForge.Tests.TokenEvm.main
