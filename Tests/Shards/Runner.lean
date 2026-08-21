namespace Tests.Shards

/-- Uniform per-suite lifecycle output for shard diagnostics. The original
    exception is rethrown so the shard remains fail-closed. -/
def runSuite (name : String) (suite : IO Unit) : IO Unit := do
  let started ← IO.monoMsNow
  IO.eprintln s!"=== suite START: {name} ==="
  try
    suite
    let finished ← IO.monoMsNow
    IO.eprintln s!"=== suite OK: {name} ({finished - started} ms) ==="
  catch error =>
    let finished ← IO.monoMsNow
    IO.eprintln s!"=== suite FAIL: {name} ({finished - started} ms) ==="
    throw error

end Tests.Shards
