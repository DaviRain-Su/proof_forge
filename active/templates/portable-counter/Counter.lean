/-
Minimal ProofForge portable starter contract.

This source is chain-neutral: it lowers to ContractSpec / portable IR. The
selected `--target` decides whether ProofForge emits EVM Yul/bytecode, Solana
sBPF assembly/ELF, NEAR WAT/Wasm, or another target artifact.
-/
import ProofForge.Contract.Source

namespace Counter

open ProofForge.Contract.Source

contract_source Counter do
  state count : .u64

  entry «initialize» do
    count := u64 0;

  entry increment do
    let n : .u64 := count;
    count := n +! u64 1;

  query get returns(.u64) do
    return count;

end Counter
