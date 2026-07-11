/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Shared facade for portable role-based access control. Target-specific adapters
may expose a native standard ABI (for example EVM `bytes32` roles), while this
business source keeps compact role handles in the portable IR.

  lake env proof-forge build --target evm --root . \
    -o build/portable-access-control/AccessControl \
    Examples/Product/AccessControl.lean
-/
import ProofForge.Contract.Stdlib.AccessControlPortable

namespace Examples.Product.AccessControl

def spec : ProofForge.Contract.ContractSpec :=
  ProofForge.Contract.Stdlib.AccessControlPortable.spec

def module : ProofForge.IR.Module :=
  spec.module

end Examples.Product.AccessControl
