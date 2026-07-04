import ProofForge.Contract.UpgradePolicy

namespace ProofForge.Contract.UpgradePolicy

/-- Reject unsupported (target, policy, proxy) combinations with a clear diagnostic. -/
def checkSupported (targetId : String) (policy : UpgradePolicy) (proxyPattern? : Option ProxyPattern) :
    Except String Unit :=
  match targetId, policy, proxyPattern? with
  | "evm", .authority _, some .uups => .ok ()
  | "evm", .authority _, _ =>
      .error "EVM target does not support `authority` upgrade policy without a documented proxy pattern; declare `proxy_pattern uups` or use `immutable`"
  | "evm", .governance _, _ =>
      .error "EVM target does not support `governance` upgrade policy in v0"
  | "solana-sbpf-asm", .governance _, _ =>
      .error "Solana target does not support `governance` upgrade policy in v0"
  | "wasm-near", .governance _, _ =>
      .error "NEAR target does not support `governance` upgrade policy in v0"
  | "aleo-leo", .authority _, _ =>
      .error "Aleo target only supports `immutable` upgrade policy"
  | "aleo-leo", .governance _, _ =>
      .error "Aleo target only supports `immutable` upgrade policy"
  | "psy-dpn", .authority _, _ =>
      .error "Psy DPN target only supports `immutable` upgrade policy"
  | "psy-dpn", .governance _, _ =>
      .error "Psy DPN target only supports `immutable` upgrade policy"
  | _, _, _ => .ok ()

end ProofForge.Contract.UpgradePolicy
