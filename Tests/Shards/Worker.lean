import Tests.Frontend.ProtocolV1
import Tests.Frontend.WorkerV1
import Tests.Compiler.ProofSubjectFilesV1
import Tests.Compiler.ProofWorkerV1
unsafe def main : IO Unit := do
  Tests.Frontend.ProtocolV1.run
  Tests.Frontend.WorkerV1.run
  Tests.Compiler.ProofSubjectFilesV1.run
  Tests.Compiler.ProofWorkerV1.run
  IO.println "shard-worker: ok"
