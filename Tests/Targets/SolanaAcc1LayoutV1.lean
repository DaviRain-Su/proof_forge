import ProofForgeV2.Targets.Solana.EmitSbpfAsmV1

/-!
# Tests.Targets.SolanaAcc1LayoutV1 — ADR-0032 U1 account[1] layout pins

Source-level pins for sole CPI-rail hybrid multi-account layout:
* account[1] via `ACC1_HEADER` equ (not single-account INSTRUCTION_DATA_LEN hack)
* entrypoint admitCaller uses num_accounts==2
* deferred comment stubs must not return

Engineering only; not formal.
-/

namespace Tests.Targets.SolanaAcc1LayoutV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-- Pin real account[1] non-dup + is_signer emission; reject deferred stubs. -/
private def testAcc1ChecksNotDeferred : IO Unit := do
  let source ← IO.FS.readFile
    (System.FilePath.mk "ProofForgeV2/Targets/Solana/EmitSbpfAsmV1.lean")
  for forbidden in #[
      "account[1] is_signer deferred to full multi-account layout",
      "account[1] non-dup deferred (signer check is gate)"] do
    expect (!source.contains forbidden)
      s!"deferred account[1] stub returned: {forbidden}"
  expect (source.contains "check account[1].dup_marker == 0xff")
    "must emit account[1] dup_marker check comment"
  expect (source.contains "check account[1].is_signer")
    "must emit account[1] is_signer check comment"
  -- Zero-data account[1] uses ACC1_HEADER equ from admitCaller layout.
  expect (source.contains "ldxb r1, [r6 + ACC1_HEADER + 0]")
    "must load account[1] dup_marker via ACC1_HEADER + 0"
  expect (source.contains "ldxb r1, [r6 + ACC1_HEADER + 1]")
    "must load account[1] is_signer via ACC1_HEADER + 1"
  expect (source.contains "computeInputLayoutWithCallerV1")
    "must define admitCaller two-account layout"
  expect (source.contains "ACC1_HEADER")
    "must emit ACC1_HEADER equ for admitCaller layout"
  -- account[0] path unchanged (ACC0_HEADER equ).
  expect (source.contains "ldxb r1, [r6 + ACC0_HEADER + 0]")
    "account[0] dup_marker must still use ACC0_HEADER"
  expect (source.contains "ldxb r1, [r6 + ACC0_HEADER + 1]")
    "account[0] is_signer must still use ACC0_HEADER + 1"

unsafe def run : IO Unit := do
  testAcc1ChecksNotDeferred
  IO.println "Tests.Targets.SolanaAcc1LayoutV1: ok"

end Tests.Targets.SolanaAcc1LayoutV1
