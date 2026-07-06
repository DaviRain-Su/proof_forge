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
  pure <| ProofForge.Contract.Token.EvmWrap.wrapRuntimeObject decl.id (decl.id ++ "Runtime") runtimeObject decl.spec

def main : IO UInt32 := do
  let proofToken ← parseFixture "Examples/Learn/ProofToken.learn"
  let yul ← renderLearnTokenYul proofToken

  require (yul.contains "object \"ProofToken\"") "ERC-20 Yul missing token object"
  require (yul.contains "sstore(0, or(shl(192, 1000000), shl(128, 9)))")
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

  let feeToken ← parseFixture "Examples/Learn/FeeToken.learn"
  let feeYul ← renderLearnTokenYul feeToken
  require (feeYul.contains "case 0x40c10f19") "mintable fee token should include mint selector"
  require (!feeYul.contains "case 0x42966c68") "non-burnable fee token should not include burn selector"

  IO.println "token-evm: ok"
  return 0

end ProofForge.Tests.TokenEvm

def main : IO UInt32 :=
  ProofForge.Tests.TokenEvm.main
