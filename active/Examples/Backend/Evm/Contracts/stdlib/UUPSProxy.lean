/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

EVM backend-spike wrapper for the UUPS proxy transport. The wrapped spec has no
portable authority policy until the EVM target can enforce its declared keyRef.
EVM deployment requires non-zero `implementation` and `admin` constructor
arguments; the runtime exposes no post-deploy initializer.
-/
import ProofForge.Contract.Stdlib.UUPSProxy

namespace UUPSProxy

def spec := ProofForge.Contract.Stdlib.UUPSProxy.spec
def module := ProofForge.Contract.Stdlib.UUPSProxy.module

end UUPSProxy
