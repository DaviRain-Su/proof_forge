import Tests.Shards.Runner
import Tests.Core.Common
import Tests.Core.CommonRemaining
import Tests.Core.CommonScalars
import Tests.Core.Unicode
import Tests.Core.ToolLockV4
import Tests.Core.DiagnosticV1
import Tests.Core.DiagnosticBundleV1

open Tests.Shards

unsafe def main : IO Unit := do
  runSuite "Tests.Core.Common" Tests.Core.Common.run
  runSuite "Tests.Core.CommonRemaining" Tests.Core.CommonRemaining.run
  runSuite "Tests.Core.CommonScalars" Tests.Core.CommonScalars.run
  runSuite "Tests.Core.Unicode" Tests.Core.Unicode.run
  runSuite "Tests.Core.ToolLockV4" Tests.Core.ToolLockV4.run
  runSuite "Tests.Core.DiagnosticV1" Tests.Core.DiagnosticV1.run
  runSuite "Tests.Core.DiagnosticBundleV1" Tests.Core.DiagnosticBundleV1.run
  IO.println "shard-core: ok"
