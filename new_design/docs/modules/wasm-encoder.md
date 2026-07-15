---
id: MOD-WASM-001
title: WasmEncoder 模块规格
status: proposed
owner: backends
updated: 2026-07-15
normative: true
---

# WasmEncoder

输入 target-owned Plan 已完成的 `WasmModuleRecipe`；输出 deterministic Wasm AST/binary 与
source map。模块拥有 core Wasm types/instructions、index assignment、section ordering、LEB128
和 structural validation；不拥有 exports/imports 的业务含义、ABI、storage、auth、calls、
gas、upgrade 或 deployment。

index 按 recipe canonical order 分配；section 使用 Wasm 规范顺序，自定义 section 按 target
明确顺序；禁止 NaN/float、non-deterministic map iteration 和未声明 feature。host target
validator 在 recipe 前，base validator 在 encoding 后。

覆盖 empty module、duplicate import/export、invalid type/index、LEB extrema、memory min/max、
data overlap、custom sections、function limit、unknown opcode/feature、malformed UTF-8、same
recipe repeatability、NEAR/CosmWasm/Soroban/ICP recipe 隔离。关联 `INV-006`、
`SPEC-MAT-001`；Phase 1 由 `TST-NEAR-003/004` 验收。
