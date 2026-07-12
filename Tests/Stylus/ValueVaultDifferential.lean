import ProofForge.Backend.Stylus.DirectWasm.Context
import ProofForge.Backend.Stylus.ValueVaultSemantics
import ProofForge.Compiler.Wasm.Printer

open ProofForge.Backend.Stylus
open ProofForge.Backend.Stylus.DirectWasm
open ProofForge.Backend.Stylus.Semantics
open ProofForge.Backend.Stylus.ValueVaultSemantics

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def address (byte : UInt8) : Word := Array.replicate 20 byte

def main : IO Unit := do
  let module <- match contextModule 1 with
    | .ok module => pure module
    | .error error => throw <| IO.userError error.message
  let wat := ProofForge.Compiler.Wasm.Printer.render module
  for signature in #[
      "\"msg_sender\" (func $msg_sender (param i32))",
      "\"msg_value\" (func $msg_value (param i32))",
      "\"contract_address\" (func $contract_address (param i32))",
      "\"block_number\" (func $block_number (result i64))",
      "\"block_timestamp\" (func $block_timestamp (result i64))"] do
    require (wat.contains signature) s!"missing official Stylus HostIO signature: {signature}"
  require (!wat.contains "predecessor_account_id" && !wat.contains "attached_deposit")
    "Stylus context module leaked NEAR HostIO"

  let owner := address 0x11
  let stranger := address 0x22
  let base : VaultState := { owner, balance := 10, lastBlock := 7 }
  let depositContext : Context := { sender := owner, value := encodeU64 5, blockNumber := 8, timestamp := 9 }
  let deposited := execute base depositContext (.deposit 20)
  require (deposited.status == .success && deposited.state.balance == 15)
    "authorized payable deposit failed"
  require (deposited.state.lastBlock == 8 && deposited.flushes == 1)
    "deposit did not preserve block context and one flush"

  let zeroDeposit := execute base { depositContext with value := encodeU64 0 } (.deposit 20)
  require (zeroDeposit.status == .reverted zeroValueBytes && zeroDeposit.state == base && zeroDeposit.flushes == 0)
    "zero-value deposit did not roll back"
  let excessDeposit := execute base { depositContext with value := encodeU64 21 } (.deposit 20)
  require (excessDeposit.status == .reverted excessValueBytes && excessDeposit.state == base)
    "excess-value deposit did not roll back"
  let unauthorized := execute base { depositContext with sender := stranger, value := encodeU64 0 } (.withdraw 3)
  require (unauthorized.status == .reverted unauthorizedBytes && unauthorized.state == base &&
      unauthorized.pendingWrites == 0) "unauthorized withdrawal leaked cached state"
  let nonPayable := execute base { depositContext with value := encodeU64 1 } (.withdraw 3)
  require (nonPayable.status == .reverted nonPayableBytes && nonPayable.state == base)
    "nonpayable withdrawal accepted value"
  let withdrawn := execute base { depositContext with value := encodeU64 0 } (.withdraw 3)
  require (withdrawn.status == .success && withdrawn.state.balance == 7 && withdrawn.flushes == 1)
    "authorized withdrawal failed"
  let insufficient := execute base { depositContext with value := encodeU64 0 } (.withdraw 11)
  require (insufficient.status == .reverted insufficientBalanceBytes && insufficient.state == base)
    "insufficient withdrawal did not roll back"

  IO.FS.createDirAll "build/stylus/value-vault-differential"
  IO.FS.writeFile "build/stylus/value-vault-differential/context.wat" wat
  IO.println "stylus-value-vault-differential: ok"
