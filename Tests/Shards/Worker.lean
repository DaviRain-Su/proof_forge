import Tests.Frontend.ProtocolV1
import Tests.Frontend.WorkerV1
unsafe def main : IO Unit := do
  Tests.Frontend.ProtocolV1.run
  Tests.Frontend.WorkerV1.run
  IO.println "shard-worker: ok"
