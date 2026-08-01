---
id: RPT-014
title: N-5 external call/schedule return values — schema impact
status: draft
owner: engineering
updated: 2026-08-02
normative: false
---

# N-5: Typed external call returns (schema impact)

## Current product fact (code)

| Layer | Shape |
|---|---|
| ProgramV1 | `call` / `schedule` are **statements** only (`Stmt.Call` / `Stmt.Schedule`) |
| Normalize | Lowers to void `Op.ExternalCall` / `Op.Schedule` (`Instruction.result = none`) |
| Wire structure | Void-op result-presence gate: spurious `result := some _` → `.badCfg` |
| Reference | Response cursor consumes matching external responses; no value binding into SSA |
| Targets | Status/arg slots (Noir) / promise (NEAR); no typed multi-word return ABI |

There is **no** expression-level `call` and **no** source form that binds a return
value into a `let` / place today.

## What “call return values” requires

To admit typed returns without lying about the wire model, at least one of:

1. **Schema upgrade (preferred, explicit)**  
   - Extend `Op.ExternalCall` / `Op.Schedule` (or add a sibling op) so a
     value-producing form may carry `Instruction.result = some ValueDef` with a
     declared result TypeId.  
   - Structure gate: result presence + serializable result type + effectId
     numbering unchanged.  
   - Reference: map external response payload → canonical valueBytes of that
     TypeId (or trap on mismatch).  
   - ProgramV1: either expression `call` or a binding statement
     (`let x : T := call Q(...)`) — **source surface change**, sole decoder.

2. **Out-of-band response binding (no Op result)**  
   - Keep void ExternalCall; introduce a later `ContextRead`-like or host-owned
     “last response” place. Rejected for N-5: blurs invocation context vs call
     site and breaks effect ordering clarity.

3. **Target-only ABI without Semantic**  
   Forbidden: frontend/Semantic must stay target-neutral (AGENTS).

## Decision for this engineering slice

- **Do not** invent a dual reader or silent schema fork.  
- **Keep** void ExternalCall/Schedule fail-closed for result-producing forms.  
- **Document** this file as the sole live N-5 design pointer (not a fourth gap
  list — see DOC-DEDUP).  
- Implementation of (1) is a **follow-on** shared-core cutover (Normalize + Wire
  + Reference + Tests together); target ABI is a later leaf after schema freezes.

## Product pins (already / N-5)

- Product `call` / `schedule` with UInt64 args lower and freeze S2
  `effect.synchronous-call` / `effect.asynchronous-workflow`.  
- Wire rejects value-producing ExternalCall/Schedule.  
- No ProgramV1 expression `call` — parser/statement surface only.

## Non-claims

- Not formal TASK-D2 / TST-SEM / SupportClaim.  
- Not multi-target runtime return ABI completion.  
- Not IBC/oracle end-to-end.

## Next concrete implement slice (when opened)

1. ADR/SPEC-SEM row for value-producing external op + source binding.  
2. Wire structure + Reference response→value.  
3. Normalize product lower + RequirementsInfer unchanged for effect keys.  
4. Target leaves one-by-one (NEAR promise / Noir slots first candidates).
