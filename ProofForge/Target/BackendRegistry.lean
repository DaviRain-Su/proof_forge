import ProofForge.Backend.Evm.Plan
import ProofForge.Backend.Evm.Validate
import ProofForge.Backend.Solana.Plan
import ProofForge.Backend.Solana.SbpfAsm
import ProofForge.Backend.WasmHost.EmitWat
import ProofForge.Backend.WasmHost.IR
import ProofForge.Backend.WasmHost.Plan
import ProofForge.Target.Backend
import ProofForge.Target.HostBridge
import ProofForge.Target.Registry

namespace ProofForge.Target

open ProofForge.IR

def diagFromMessage (message : String) : Diagnostic := { message }

def mapPlanError {ε : Type} [Inhabited ε] (getMessage : ε → String)
    (result : Except ε α) : Except Diagnostic Unit :=
  match result with
  | .ok _ => .ok ()
  | .error err => .error (diagFromMessage (getMessage err))

/-! ### Primary triad: real backend stages on TargetBackend -/

def evmValidateModule (module : Module) : Except Diagnostic Unit :=
  match ProofForge.Backend.Evm.Validate.validateCapabilities module with
  | .ok () =>
      match ProofForge.Backend.Evm.Validate.validateState module with
      | .ok () =>
          match ProofForge.Backend.Evm.Validate.validateStructs module with
          | .ok () => .ok ()
          | .error err => .error (diagFromMessage err.message)
      | .error err => .error (diagFromMessage err.message)
  | .error err => .error (diagFromMessage err.message)

def evmEnsurePlan (module : Module) : Except Diagnostic Unit :=
  mapPlanError (fun (e : ProofForge.Backend.Evm.Plan.PlanError) => e.message)
    (ProofForge.Backend.Evm.Plan.buildModulePlan module)

def solanaValidateModule (module : Module) : Except Diagnostic Unit :=
  match ProofForge.Backend.Solana.SbpfAsm.validateCapabilities module with
  | .ok () => .ok ()
  | .error err => .error (diagFromMessage err.message)

def solanaEnsurePlan (module : Module) : Except Diagnostic Unit :=
  mapPlanError (fun (e : ProofForge.Backend.Solana.Plan.PlanError) => e.message)
    (ProofForge.Backend.Solana.Plan.buildSolanaModulePlan module)

/-- Align with production EmitWat path (PF-P1-04). `WasmHost.IR.validateModule`
rejects nested mapKey paths that EmitWat already lowers (e.g. AccessControl
roles); readiness must match build, not the stricter Rust-sourcegen gate. -/
def nearValidateModule (module : Module) : Except Diagnostic Unit :=
  match ProofForge.Backend.WasmHost.EmitWat.renderModule module with
  | .ok _ => .ok ()
  | .error err => .error (diagFromMessage err.message)

def nearEnsurePlan (module : Module) : Except Diagnostic Unit :=
  mapPlanError (fun (e : ProofForge.Backend.WasmHost.Plan.PlanError) => e.message)
    (ProofForge.Backend.WasmHost.Plan.buildModulePlan module)

/-- EVM package dry-run: capability plan + structural plan is the check L2 surface;
full Yul emission still needs CLI ABI/constructor context (build smokes). -/
def evmEnsurePackage (_module : Module) (_plan : CapabilityPlan) : Except Diagnostic Unit :=
  .ok ()

def solanaEnsurePackage (module : Module) (plan : CapabilityPlan) : Except Diagnostic Unit :=
  match ProofForge.Backend.Solana.SbpfAsm.renderModuleWithPlan module plan with
  | .ok _ => .ok ()
  | .error err => .error (diagFromMessage err.render)

def nearEnsurePackage (module : Module) (plan : CapabilityPlan) : Except Diagnostic Unit :=
  match ProofForge.Backend.WasmHost.EmitWat.renderModuleWithPlan module plan HostBridge.near with
  | .ok _ => .ok ()
  | .error err => .error (diagFromMessage err.message)

def evmBackend : TargetBackend := {
  TargetBackend.ofProfile evm with
  validateModule? := some evmValidateModule
  ensurePlan? := some evmEnsurePlan
  ensurePackage? := some evmEnsurePackage
}

def solanaBackend : TargetBackend := {
  TargetBackend.ofProfile solanaSbpfAsm with
  validateModule? := some solanaValidateModule
  ensurePlan? := some solanaEnsurePlan
  ensurePackage? := some solanaEnsurePackage
}

def nearBackend : TargetBackend := {
  TargetBackend.ofProfile wasmNear with
  validateModule? := some nearValidateModule
  ensurePlan? := some nearEnsurePlan
  ensurePackage? := some nearEnsurePackage
}

def primaryTriadBackends : Array TargetBackend := #[
  evmBackend,
  solanaBackend,
  nearBackend
]

def primaryTriadIds : Array String := #["evm", "solana-sbpf-asm", "wasm-near"]

def isPrimaryTriad (id : String) : Bool :=
  primaryTriadIds.contains id

def backendForProfile (profile : TargetProfile) : TargetBackend :=
  if profile.id == "evm" then
    evmBackend
  else if profile.id == "solana-sbpf-asm" then
    solanaBackend
  else if profile.id == "wasm-near" then
    nearBackend
  else
    TargetBackend.ofProfile profile

/-- One backend per active registry profile. Primary triad carry real
validate/plan hooks; secondary targets keep profile+resolve until migrated. -/
def allBackends : Array TargetBackend :=
  all.map backendForProfile

def findBackend? (id : String) : Option TargetBackend :=
  allBackends.find? (fun backend => backend.profile.id == id)

/-- Capability resolve via the backend registry. -/
def resolveViaBackend (id : String) (spec : ProofForge.Contract.ContractSpec) :
    Except Diagnostic CapabilityPlan :=
  match findBackend? id with
  | some backend => backend.resolve spec
  | none => .error {
      message := s!"unknown target `{id}`: no TargetBackend is registered"
    }

end ProofForge.Target
