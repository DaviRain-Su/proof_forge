import Tests.Frontend.DarwinSourceSupervisorV1

/-- Focused B11b2 matrix followed by the complete B11b1 regression suite. -/
unsafe def main : IO Unit := do
  Tests.Frontend.DarwinSourceSupervisorV1.run
  Tests.Frontend.DarwinWorkerSupervisorV1.run
