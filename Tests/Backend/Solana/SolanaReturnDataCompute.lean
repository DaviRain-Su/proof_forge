import ProofForge.Backend.Solana.Package
import ProofForge.Backend.Solana.SbpfAsm
import ProofForge.Solana.Examples.ReturnDataCompute
import ProofForge.Target.Adapter
import ProofForge.Target.Registry

namespace ProofForge.Tests.SolanaReturnDataCompute

open ProofForge.Target

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then
    pure ()
  else
    throw <| IO.userError message

def contains (haystack needle : String) : Bool :=
  haystack.contains needle

def hasCapability (plan : CapabilityPlan) (capability : Capability) : Bool :=
  plan.capabilities.any (fun c => c == capability)

def metadataValue? (call : CapabilityCall) (key : String) : Option String :=
  call.metadata.foldl
    (fun found metadata =>
      match found with
      | some _ => found
      | none =>
          if metadata.key == key then
            some metadata.value
          else
            none)
    none

def scopedReturnDataCall? (plan : CapabilityPlan) (name entrypoint : String) :
    Option CapabilityCall :=
  plan.calls.find? fun call =>
    call.capability == .runtimeReturnData &&
    metadataValue? call "solana.return_data.name" == some name &&
    metadataValue? call "proof_forge.entrypoint" == some entrypoint

def scopedComputeUnitsCall? (plan : CapabilityPlan) (name entrypoint : String) :
    Option CapabilityCall :=
  plan.calls.find? fun call =>
    call.capability == .runtimeComputeUnits &&
    metadataValue? call "solana.compute_units.name" == some name &&
    metadataValue? call "proof_forge.entrypoint" == some entrypoint

def scopedComputeUnitsLogCall? (plan : CapabilityPlan) (name entrypoint : String) :
    Option CapabilityCall :=
  plan.calls.find? fun call =>
    call.capability == .runtimeComputeUnits &&
    metadataValue? call "solana.compute_units.name" == some name &&
    metadataValue? call "solana.compute_units.op" == some "log_remaining" &&
    metadataValue? call "proof_forge.entrypoint" == some entrypoint

def requireMetadata (call : CapabilityCall) (key expected : String) : IO Unit :=
  require (metadataValue? call key == some expected)
    s!"metadata `{key}` mismatch for operation `{call.operation}`"

def main : IO UInt32 := do
  let spec := ProofForge.Solana.Examples.ReturnDataCompute.spec
  let plan ←
    match resolveSpec solanaSbpfAsm spec with
    | .ok plan => pure plan
    | .error err => throw <| IO.userError s!"Solana return-data/compute routing failed: {err.render}"

  require (hasCapability plan .runtimeReturnData)
    "Solana plan missing runtime.return_data capability"
  require (hasCapability plan .runtimeComputeUnits)
    "Solana plan missing runtime.compute_units capability"
  require (hasCapability plan .storageScalar)
    "Solana plan missing storage.scalar capability"

  let returnDataCall ←
    match scopedReturnDataCall? plan "publish_result_data" "publish_result" with
    | some call => pure call
    | none => throw <| IO.userError "Solana plan missing publish_result return-data action"
  require (returnDataCall.operation == .builtin "solana.return_data.set")
    "publish_result_data should lower through solana.return_data.set"
  requireMetadata returnDataCall "solana.extension" "return_data"
  requireMetadata returnDataCall "solana.return_data.op" "set"
  requireMetadata returnDataCall "solana.return_data.source_state" "result"
  requireMetadata returnDataCall "solana.return_data.bytes" "8"

  let readReturnDataCall ←
    match scopedReturnDataCall? plan "read_latest_return_data" "read_return_data" with
    | some call => pure call
    | none => throw <| IO.userError "Solana plan missing read_latest_return_data return-data action"
  require (readReturnDataCall.operation == .builtin "solana.return_data.get")
    "read_latest_return_data should lower through solana.return_data.get"
  requireMetadata readReturnDataCall "solana.extension" "return_data"
  requireMetadata readReturnDataCall "solana.return_data.op" "get"
  requireMetadata readReturnDataCall "solana.return_data.destination_state" "last_return"
  requireMetadata readReturnDataCall "solana.return_data.max_bytes" "8"
  requireMetadata readReturnDataCall "solana.return_data.length_state" "return_len"
  requireMetadata readReturnDataCall "solana.return_data.program_id_states"
    "return_program0,return_program1,return_program2,return_program3"

  let roundtripSetCall ←
    match scopedReturnDataCall? plan "roundtrip_publish_result_data" "roundtrip_return_data" with
    | some call => pure call
    | none => throw <| IO.userError "Solana plan missing roundtrip_publish_result_data return-data action"
  requireMetadata roundtripSetCall "solana.extension" "return_data"
  requireMetadata roundtripSetCall "solana.return_data.op" "set"
  requireMetadata roundtripSetCall "solana.return_data.source_state" "result"
  requireMetadata roundtripSetCall "solana.return_data.bytes" "8"

  let roundtripReadCall ←
    match scopedReturnDataCall? plan "roundtrip_read_return_data" "roundtrip_return_data" with
    | some call => pure call
    | none => throw <| IO.userError "Solana plan missing roundtrip_read_return_data return-data action"
  requireMetadata roundtripReadCall "solana.extension" "return_data"
  requireMetadata roundtripReadCall "solana.return_data.op" "get"
  requireMetadata roundtripReadCall "solana.return_data.destination_state" "last_return"
  requireMetadata roundtripReadCall "solana.return_data.max_bytes" "8"
  requireMetadata roundtripReadCall "solana.return_data.length_state" "return_len"
  requireMetadata roundtripReadCall "solana.return_data.program_id_states"
    "return_program0,return_program1,return_program2,return_program3"

  let computeCall ←
    match scopedComputeUnitsCall? plan "record_remaining" "record_compute" with
    | some call => pure call
    | none => throw <| IO.userError "Solana plan missing record_remaining compute-units action"
  require (computeCall.operation == .builtin "solana.compute_units.remaining")
    "record_remaining should lower through solana.compute_units.remaining"
  requireMetadata computeCall "solana.extension" "compute_units"
  requireMetadata computeCall "solana.compute_units.op" "remaining"
  requireMetadata computeCall "solana.compute_units.output_state" "remaining"
  requireMetadata computeCall "solana.compute_units.feature_gated" "true"

  let logComputeCall ←
    match scopedComputeUnitsLogCall? plan "log_remaining" "log_compute" with
    | some call => pure call
    | none => throw <| IO.userError "Solana plan missing log_remaining compute-units action"
  require (logComputeCall.operation == .builtin "solana.compute_units.log_remaining")
    "log_remaining should lower through solana.compute_units.log_remaining"
  requireMetadata logComputeCall "solana.extension" "compute_units"
  requireMetadata logComputeCall "solana.compute_units.op" "log_remaining"

  match resolveSpec evm spec with
  | .ok _ => throw <| IO.userError "EVM unexpectedly accepted Solana return-data/compute extensions"
  | .error err =>
      require (contains err.render "cannot use Solana target extension metadata")
        s!"unexpected EVM diagnostic: {err.render}"

  match ProofForge.Backend.Solana.Package.renderPackageForSpec "solana-return-data-compute" spec with
  | .ok pkg =>
      let some asmFile := pkg.files.find? (fun file => file.path == pkg.asmPath)
        | throw <| IO.userError "return-data/compute package missing sBPF assembly"
      let some manifestFile := pkg.files.find? (fun file => file.path == "manifest.toml")
        | throw <| IO.userError "return-data/compute package missing manifest.toml"
      let asm := asmFile.contents
      let manifest := manifestFile.contents
      require (contains manifest "[[solana.entrypoint_return_data]]")
        "manifest missing entrypoint return-data action section"
      require (contains manifest "return_data = \"publish_result_data\"")
        "manifest missing publish_result_data action"
      require (contains manifest "op = \"set\"")
        "manifest missing return-data set op"
      require (contains manifest "source_state = \"result\"")
        "manifest missing return-data source state"
      require (contains manifest "bytes = 8")
        "manifest missing return-data byte count"
      require (contains manifest "return_data = \"read_latest_return_data\"")
        "manifest missing read_latest_return_data action"
      require (contains manifest "op = \"get\"")
        "manifest missing return-data get op"
      require (contains manifest "destination_state = \"last_return\"")
        "manifest missing return-data destination state"
      require (contains manifest "max_bytes = 8")
        "manifest missing return-data max byte count"
      require (contains manifest "length_state = \"return_len\"")
        "manifest missing return-data length state"
      require (contains manifest "program_id_states = [\"return_program0\", \"return_program1\", \"return_program2\", \"return_program3\"]")
        "manifest missing return-data program id state outputs"
      require (contains manifest "return_data = \"roundtrip_publish_result_data\"")
        "manifest missing roundtrip_publish_result_data action"
      require (contains manifest "return_data = \"roundtrip_read_return_data\"")
        "manifest missing roundtrip_read_return_data action"
      require (contains manifest "entrypoint = \"roundtrip_return_data\"")
        "manifest missing roundtrip_return_data entrypoint action"
      require (contains manifest "[[solana.entrypoint_compute_units]]")
        "manifest missing entrypoint compute-units action section"
      require (contains manifest "compute_units = \"record_remaining\"")
        "manifest missing record_remaining action"
      require (contains manifest "op = \"remaining\"")
        "manifest missing compute-units remaining op"
      require (contains manifest "output_state = \"remaining\"")
        "manifest missing compute-units output state"
      require (contains manifest "feature_gated = true")
        "manifest missing compute-units feature-gated marker"
      require (contains manifest "compute_units = \"log_remaining\"")
        "manifest missing log_remaining compute-units action"
      require (contains manifest "op = \"log_remaining\"")
        "manifest missing compute-units log_remaining op"
      require (contains asm "solana.return_data.action publish_result_data")
        "assembly missing return-data entrypoint action"
      require (contains asm "sol_return_data_set_publish_result_data:")
        "assembly missing return-data helper label"
      require (contains asm "solana.return_data.set publish_result_data: source=result bytes=8")
        "assembly missing return-data helper marker"
      require (contains asm "call sol_set_return_data")
        "assembly missing sol_set_return_data syscall"
      require (contains asm "solana.return_data.read_action read_latest_return_data")
        "assembly missing return-data read entrypoint action"
      require (contains asm "sol_return_data_get_read_latest_return_data:")
        "assembly missing return-data get helper label"
      require (contains asm "solana.return_data.get read_latest_return_data: destination=last_return max_bytes=8")
        "assembly missing return-data get helper marker"
      require (contains asm "zero return-data program id buffer before sol_get_return_data")
        "assembly missing return-data program id zeroing"
      require (contains asm "call sol_get_return_data")
        "assembly missing sol_get_return_data syscall"
      require (contains asm "solana.return_data.length read_latest_return_data state=return_len")
        "assembly missing return-data length output"
      require (contains asm "solana.return_data.program_id read_latest_return_data[3] state=return_program3")
        "assembly missing fourth return-data program id output"
      require (contains asm "solana.return_data.action roundtrip_publish_result_data")
        "assembly missing roundtrip return-data set entrypoint action"
      require (contains asm "sol_return_data_set_roundtrip_publish_result_data:")
        "assembly missing roundtrip return-data set helper label"
      require (contains asm "solana.return_data.read_action roundtrip_read_return_data")
        "assembly missing roundtrip return-data read entrypoint action"
      require (contains asm "sol_return_data_get_roundtrip_read_return_data:")
        "assembly missing roundtrip return-data get helper label"
      require (contains asm "solana.compute_units.action record_remaining")
        "assembly missing compute-units entrypoint action"
      require (contains asm "sol_compute_units_remaining_record_remaining:")
        "assembly missing compute-units helper label"
      require (contains asm "solana.compute_units.remaining record_remaining: output=remaining feature_gated=true")
        "assembly missing compute-units helper marker"
      require (contains asm "call sol_remaining_compute_units")
        "assembly missing sol_remaining_compute_units syscall"
      require (contains asm "stxdw [r5+0], r3")
        "assembly missing compute-units state write"
      require (contains asm "solana.compute_units.log_action log_remaining")
        "assembly missing compute-units log entrypoint action"
      require (contains asm "sol_compute_units_log_log_remaining:")
        "assembly missing compute-units log helper label"
      require (contains asm "solana.compute_units.log_remaining log_remaining")
        "assembly missing compute-units log helper marker"
      require (contains asm "call sol_log_compute_units_")
        "assembly missing sol_log_compute_units_ syscall"
  | .error err =>
      throw <| IO.userError s!"Solana return-data/compute package render failed: {err.render}"

  IO.println "solana-return-data-compute: ok"
  return 0

end ProofForge.Tests.SolanaReturnDataCompute

def main : IO UInt32 :=
  ProofForge.Tests.SolanaReturnDataCompute.main
