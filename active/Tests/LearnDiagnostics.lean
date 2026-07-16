import ProofForge.Contract.Learn

namespace ProofForge.Tests.LearnDiagnostics

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then
    pure ()
  else
    throw <| IO.userError message

def requireErrorContains (label needle source : String) : IO Unit := do
  match ProofForge.Contract.Learn.parseAndLower source with
  | .ok _ => throw <| IO.userError s!"{label}: expected Learn diagnostic containing `{needle}`"
  | .error err =>
      require (err.contains needle)
        s!"{label}: diagnostic mismatch\nexpected to contain: {needle}\nactual: {err}"

def unknownCpiSource : String := "
contract BadUnknownCpi {
  state last_transfer_lamports: u64

  solana account payer writable signer
  solana account recipient writable

  solana cpi lamport_transfer system_transfer(payer, recipient, lamports)

  entry transfer(lamports: u64) {
    solana invoke missing_transfer system_transfer(payer, recipient, lamports)
    last_transfer_lamports = lamports
  }
}
"

def mismatchedCpiSource : String := "
contract BadMismatchedCpi {
  state last_transfer_lamports: u64

  solana account payer writable signer
  solana account recipient writable

  solana cpi lamport_transfer system_transfer(payer, recipient, lamports)

  entry transfer(lamports: u64) {
    solana invoke lamport_transfer system_transfer(recipient, payer, lamports)
    last_transfer_lamports = lamports
  }
}
"

def unknownPdaSource : String := "
contract BadUnknownPda {
  state nonce: u64
  binding vault_bump: u64

  solana account vault_account writable owner program
  solana account authority readonly
  solana pda vault seeds [literal vault, account authority] bump vault_bump account vault_account signer

  entry touch() {
    solana derive pda missing_vault seeds [literal vault, account authority] bump vault_bump account vault_account signer
    nonce = 1
  }
}
"

def unknownStateSource : String := "
contract BadUnknownState {
  state source: u64
  state copied: u64

  entry copy() {
    solana memory memcpy copy_missing(copied, missing) bytes 8
  }
}
"

def unknownCpiAccountSource : String := "
contract BadUnknownCpiAccount {
  state last_transfer_lamports: u64

  solana account payer writable signer

  solana cpi lamport_transfer system_transfer(payer, recipient, lamports)

  entry transfer(lamports: u64) {
    solana invoke lamport_transfer system_transfer(payer, recipient, lamports)
    last_transfer_lamports = lamports
  }
}
"

def readonlyCpiAccountSource : String := "
contract BadReadonlyCpiAccount {
  state last_transfer_lamports: u64

  solana account payer writable signer
  solana account recipient readonly

  solana cpi lamport_transfer system_transfer(payer, recipient, lamports)

  entry transfer(lamports: u64) {
    solana invoke lamport_transfer system_transfer(payer, recipient, lamports)
    last_transfer_lamports = lamports
  }
}
"

def missingSignerCpiAccountSource : String := "
contract BadMissingSignerCpiAccount {
  state last_transfer_lamports: u64

  solana account payer writable
  solana account recipient writable

  solana cpi lamport_transfer system_transfer(payer, recipient, lamports)

  entry transfer(lamports: u64) {
    solana invoke lamport_transfer system_transfer(payer, recipient, lamports)
    last_transfer_lamports = lamports
  }
}
"

def main : IO UInt32 := do
  requireErrorContains "unknown CPI" "unknown Learn Solana CPI `missing_transfer`"
    unknownCpiSource
  requireErrorContains "mismatched CPI"
    "Learn Solana CPI invoke `lamport_transfer` does not match declaration"
    mismatchedCpiSource
  requireErrorContains "unknown PDA" "unknown Learn Solana PDA `missing_vault`"
    unknownPdaSource
  requireErrorContains "unknown helper state" "unknown Learn state `missing`"
    unknownStateSource
  requireErrorContains "unknown CPI account" "unknown Learn Solana account `recipient`"
    unknownCpiAccountSource
  requireErrorContains "readonly CPI account" "Learn Solana account `recipient` must be writable"
    readonlyCpiAccountSource
  requireErrorContains "missing signer CPI account" "Learn Solana account `payer` must be signer"
    missingSignerCpiAccountSource
  IO.println "learn-diagnostics: ok"
  return 0

end ProofForge.Tests.LearnDiagnostics

def main : IO UInt32 :=
  ProofForge.Tests.LearnDiagnostics.main
