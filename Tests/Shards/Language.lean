import Tests.Language.ProgramExports
unsafe def main : IO Unit := do
  Tests.Language.ProgramExports.run
  IO.println "diag-pe ok"
