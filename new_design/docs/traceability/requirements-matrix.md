---
id: TRACE-MATRIX-001
title: Phase 1 需求追踪矩阵
status: proposed
owner: quality
updated: 2026-07-15
normative: true
---

# Phase 1 需求追踪矩阵

Evidence 仅在有可复现 EV 时从 `specified` 升级；不得把 planned test 视为已通过。

| Requirement | ADR/INV | Spec/Module | Task | Test | Evidence |
|---|---|---|---|---|---|
| FR-001 | ADR-0002, ADR-0003, INV-001 | SPEC-LANG-001, MOD-SOURCE-001 | TASK-D1-02 | TST-SRC-003 | specified |
| FR-002 | ADR-0002 | SPEC-LANG-001 | TASK-D1-03/04 | TST-SRC-004/005 | specified |
| FR-003 | INV-001, INV-002 | SPEC-TYPE-001, SPEC-DIAG-001 | TASK-D2-01..04 | TST-TYPE/EFFECT/BOUND/VIS-* | specified (partial Bound impl; D2 not closed) |
| FR-004 | ADR-0004, INV-003 | SPEC-SEM-001, MOD-SEM-001 | TASK-D2-05..07 | TST-SEM-001, TST-REQ-001 | specified |
| FR-005 | ADR-0003, ADR-0004, INV-002 | SPEC-SEM-001, SPEC-REG-001 | TASK-D3-01..03 | TST-XTARGET-001 | specified |
| FR-006 | ADR-0005, INV-005 | SPEC-CAP-001 | TASK-D2-07/D3-03 | TST-REQ-003 | specified |
| FR-007 | ADR-0006, INV-004 | SPEC-MAT-001, MOD-MAT-001 | TASK-D3-04 | TST-MAT-001 | specified |
| FR-008 | ADR-0007, ADR-0008 | SPEC-REG-001 + target dossiers | TASK-D4..D7 | TST-*-001..005 | specified |
| FR-009 | ADR-0010, INV-009 | SPEC-OUT-001 | TASK-D3-05 | TST-OUT-001/002 | specified |
| FR-010 | ADR-0002 | SPEC-LANG-001, SPEC-CLI-001 | TASK-D1-05/06 | TST-SRC-006..008 | specified |
| FR-011 | INV-003 | SPEC-CLI-001, SPEC-DIAG-001 | TASK-D3-06 | TST-CLI-001..004 | specified |
| FR-012 | ADR-0008, INV-007 | SPEC-TYPE-001, SPEC-SEC-001 | TASK-D2-04/D7-01 | TST-VIS-001/002 | specified |
| FR-013 | ADR-0005 | SPEC-CAP-001 | TASK-D2-07/D3-03 | TST-REQ-003 | specified |
| FR-014 | INV-008 | SPEC-CLI-001, SPEC-SEC-001 | TASK-D3-06 | TST-CLI-004 | specified |
| NFR-001 | ADR-0013, INV-009 | SPEC-REPRO-001, SPEC-TOOL-001 | TASK-D0-03/D8-03 | TST-TOOL-001, TST-OUT-002, TST-ISO-003 | specified |
| NFR-002 | INV-003 | SPEC-DIAG-001 | TASK-D1-07 | TST-DIAG-001 | specified |
| NFR-003 | ADR-0005, ADR-0011, INV-005, INV-008 | SPEC-SEC-001 | TASK-D8-03 | TST-SEC-001 | specified |
| NFR-004 | ADR-0001, ADR-0012, ADR-0013, INV-010 | SPEC-REPRO-001 | TASK-D0-03/D0-04/D8-04 | TST-HOST-001, TST-ISO-002/003 | specified |
| NFR-005 | — | TRACE-MATRIX-001 | TASK-D0-01 | TST-DOC-001 | specified |
| NFR-006 | ADR-0009, ADR-0010 | SPEC-VER-001 | TASK-D0-01 | TST-VER-001 | specified |
| NFR-007 | — | MOD-TEST-001 | TASK-D8-03 | TST-PERF-001 | specified |
| NFR-008 | INV-005 | SPEC-SEC-001 | TASK-D2-03/D8-03 | TST-BOUND-001, TST-SEC-001 | specified |
| NFR-009 | ADR-0010, ADR-0013 | SPEC-TOOL-001, SPEC-SEC-001 | TASK-D0-03 | TST-TOOL-001, TST-HOST-001 | specified |
| NFR-010 | ADR-0004, ADR-0006, ADR-0007 | MOD-INDEX, SPEC-MAT-001 | TASK-D3-04 | TST-BOUNDARY-001 | specified |

`FR-008` 只有四个 target 的 runtime/proof EV 和 aggregate EV 齐全后关闭；目标 dossier 的
research/specification 状态不能替代实现证据。
