import Tests.Core.Common
import Tests.Core.CommonRemaining
import Tests.Core.CommonScalars
import Tests.Core.Unicode
import Tests.Core.DiagnosticV1
import Tests.Core.DiagnosticBundleV1
unsafe def main : IO Unit := do
  Tests.Core.Common.run
  Tests.Core.CommonRemaining.run
  Tests.Core.CommonScalars.run
  Tests.Core.Unicode.run
  Tests.Core.DiagnosticV1.run
  Tests.Core.DiagnosticBundleV1.run
  IO.println "shard-core: ok"
