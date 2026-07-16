import ProofForge.Backend.Stylus.DirectWasm.Context
import ProofForge.Backend.Stylus.DirectWasm.Module
import ProofForge.Backend.Stylus.Package
import ProofForge.Backend.Stylus.Plan.Core
import ProofForge.Backend.Stylus.RustSdk.Render
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
  let valueFunction : ProofForge.IR.Core.Function := {
    id := { value := 0 }, params := #[], retType := .unit, entry := { value := 0 }
    blocks := #[{
      id := { value := 0 }
      instructions := #[{ results := #[{ id := { value := 1 }, type := .u128 }], op := .contextRead .value }]
      terminator := .return #[]
    }]
  }
  require (ProofForge.Backend.Stylus.Plan.Core.functionReadsValue valueFunction)
    "canonical msg.value use did not infer payable policy"
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

  let slot := Array.replicate 32 0
  let authMethod : StylusAbiMethodPlan := {
    name := "withdraw", canonicalSignature := "withdraw()", selector := #[0x3c, 0xcf, 0xd6, 0x0b]
  }
  let authBlock : StylusBlockPlan := {
    id := 0
    operations := #[
      .contextRead 1 .address .msgSender,
      .storageLoad 2 "owner",
      .compare 3 .address .eq 1 2,
      .assert_ 3 "stylus: unauthorized"
    ]
    terminator := .return #[]
  }
  let authFunction : StylusFunctionPlan := {
    id := "withdraw", abiMethod := "withdraw", entryBlock := 0
    blocks := #[authBlock]
    support := { rustSdk := .implemented, directWasm := .implemented }
  }
  let authPlan : StylusPlan := {
    targetId := "wasm-arbitrum-stylus", moduleName := "StylusValueVault"
    abi := { methods := #[authMethod], errors := #[] }
    storage := { words := #[{ id := "owner", slot := .literal slot, byteWidth := 20, type := .address }] }
    functions := #[authFunction], events := #[], calls := #[]
    hostOps := #[
      { id := "withdraw.sender", functionId := "withdraw", operation := .msgSender,
        support := { rustSdk := .implemented, directWasm := .implemented } },
      { id := "withdraw.owner", functionId := "withdraw", operation := .storageLoad,
        support := { rustSdk := .implemented, directWasm := .implemented } },
      { id := "withdraw.result", functionId := "withdraw", operation := .writeResult,
        support := { rustSdk := .implemented, directWasm := .implemented } },
      { id := "withdraw.nonpayable", functionId := "withdraw", operation := .msgValue,
        support := { rustSdk := .implemented, directWasm := .implemented } }
    ]
    resources := { maxMemoryPages := 1, requiresStorageFlush := false }
    artifacts := { solidityAbi := true, typescriptClient := true }
  }
  let direct <- match lowerFromPlan authPlan with
    | .ok module => pure module | .error error => throw <| IO.userError error.message
  let directWat := ProofForge.Compiler.Wasm.Printer.render direct
  require (directWat.contains "msg_sender" && directWat.contains "msg_value" && directWat.contains "i32.load8_u" &&
      directWat.contains "write_result" && directWat.contains "i64.and")
    "authorization plan was not lowered directly"
  let rust <- match ProofForge.Backend.Stylus.RustSdk.renderCrate authPlan with
    | .ok crate => pure crate | .error error => throw <| IO.userError error.message
  let some lib := rust.find? "src/lib.rs" | throw <| IO.userError "authorization Rust crate missing"
  require (lib.contains "self.vm().msg_sender()" && lib.contains "stylus: unauthorized")
    "authorization plan was not lowered through Rust SDK"

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
  IO.FS.writeFile "build/stylus/value-vault-differential/authorization.wat" directWat
  let cratePath := System.FilePath.mk "build/stylus/value-vault-differential/authorization-rust"
  if ← cratePath.pathExists then IO.FS.removeDirAll cratePath
  match ← writeCrateAtomic rust cratePath with
  | .ok () => pure () | .error error => throw <| IO.userError error.message
  IO.println "stylus-value-vault-differential: ok"
