import ProofForge.Frontend.Surface.Type
import ProofForge.Frontend.Surface.Syntax
import ProofForge.Frontend.Surface.Validate
import ProofForge.Frontend.Surface.NormalizeEnv
import ProofForge.Frontend.Surface.NormalizeExpr
import ProofForge.Frontend.Surface.NormalizeStmt
import ProofForge.Frontend.Surface.Normalize
import ProofForge.Frontend.Surface.Semantics
import ProofForge.Frontend.Surface.Collections.Set
import ProofForge.Frontend.Surface.Collections.Queue
import ProofForge.Frontend.Surface.Host.Near

/-! # Surface AST — Module Aggregator

Re-exports the full Surface front-end. The Surface module does NOT import
`ProofForge.IR.Legacy`, `ProofForge.IR.Contract`, or any backend/target AST.
-/

namespace ProofForge.Frontend.Surface

end ProofForge.Frontend.Surface