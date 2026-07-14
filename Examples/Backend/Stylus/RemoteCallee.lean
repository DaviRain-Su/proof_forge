/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Minimal deployable peer for the Stylus two-contract Nitro scenario.
-/
import ProofForge.Contract.Source.Legacy

namespace Examples.Backend.Stylus.RemoteCallee

open ProofForge.Contract.Source.Legacy

contract_source RemoteCallee do
  query remote_call returns(.u64) do
    return u64 42;

end Examples.Backend.Stylus.RemoteCallee
