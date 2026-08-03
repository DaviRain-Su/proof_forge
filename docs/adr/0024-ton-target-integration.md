---
id: ADR-0024
title: TON（Tolk 1.4.2 / TVM）capability-gated target 集成
status: proposed
owner: architecture
updated: 2026-08-03
normative: true
---

# ADR-0024：TON（Tolk 1.4.2 / TVM）capability-gated target 集成

## 状态

proposed

## 背景

[ADR-0017](0017-research-phase-targets-ton-move-cairo-zkvm.md) 把 `ton` 登记为研究期
TargetId 候选（family **TVM Stack-Account**），但其后果清单（dossier、family 文档、
README 索引）长期未执行。2026-08-03 已先由工程切片补齐研究期文档
（[`docs/targets/11-ton.md`](../targets/11-ton.md)、
[`docs/targets/family-tvm-stack-account.md`](../targets/family-tvm-stack-account.md)），
并完成 2026 年工具链核实：**Tolk 为官方推荐合约语言**（FunC 停维护、Tact 废弃）；
`tolk-1.4.2` release 附带官方多平台 binary 与 sha256 digest；
`@ton/sandbox` 提供全 phase（storage/credit/compute/action/bounce）本地仿真。

本 ADR 决定把 `ton` 从研究期提升为 **capability-gated implemented target**（第 8 个），
架构形态与 Aleo（ADR-0023）、CosmWasm（A0/A1）先例一致。实现分两片：本 ADR 冻结
registry/descriptor/capability/工具锚点（TON-1）；materializer leaf 为后续切片
（TON-2，`.tolk` 源码发射 → locked `tolk` → `.fif` + BoC + `abi.json`）。

## 决策

1. **身份与归类**：`TargetId.ton`（小写、无分隔符）；family = TVM Stack-Account；
   不与 EVM/SVM/Wasm 共享 Plan/IR（ADR-0007/0008 同纪律）。
2. **Registry**：`TargetRegistryV1` 冻结 seed 新增 `ton`（8 implemented +
   3 design-only）；六轴 closed enums 扩三个构造子——`ExecutionHostV1.tvm`、
   `StateBindingV1.cellHashmap`、`SettlementModelV1.tonChain`；其余轴复用
   `transactionAtomic`（TON 单笔交易 compute+storage 原子提交，out-message 为
   未来独立交易）、`asynchronousActor`（与 ICP 同语义类：纯异步 actor 消息）、
   `noProof`。`CodegenProfileId.tonTolkBocV1`（`ton-tolk-boc-v1`）；
   `DescriptorDataV1.ton`（`ArtifactEncoding.tolkSource`）。maturity 标签
   `source-only`（leaf 与 sandbox 验收前不声明制品/runtime）。
3. **Capability（honest 6-key 子集）**：state.persistent、value.checked-arithmetic、
   value.bool、failure.atomic-rollback、effect.event（external out-message）、
   effect.asynchronous-workflow（原生异步消息为一等公民）。**`effect.synchronous-call`
   显式拒绝**：TON 不存在同步跨合约调用——任何「call 后立刻读返回值」必须经
   callback 消息 + query_id 关联，属后续工作流语义，不得伪装成 sync CALL
   （B-CALL-SEM 同级诚实标准）。
4. **工具锚点**：`tolk` 入 Tool Lock `tools[]`（release tag `tolk-1.4.2`，官方
   sha256：darwin `tolk-mac-arm64`、linux `tolk-linux-x86_64`；binary 自报
   `Tolk compiler v1.4.1`，expectedVersion 按真实输出钉 `1.4.1`；darwin 闭包
   system-only（CoreFoundation/libc++/libSystem），linux 为 static-pie 无 NEEDED）。
   `@ton/sandbox`（npm lockfile pin）留作 TON-3 验收门工具，不进 Tool Lock tools[]。
5. **数据与控制面（为 TON-2 冻结边界）**：合约状态 = `c4` cell + 固定 key 长度
   dict/hashmap 或扁平 struct cell；TVM `int257` 原生整数，DSL 多宽 UInt/Int 必须
   显式范围检查（禁止隐式 wrap）；bounded for 由 emitter 计数 + throw 承载；
   emit → external out-message（文档写明非持久业务事件总线）；schedule → 原生
   async out-message（send mode、value/gas 附着、bounce 策略属 materializer 显式
   Plan 元数据，不得隐式默认）；`compute 成功 ≠ 业务成功`（action phase 可失败），
   验收必须断言整笔交易与 out-message 序列。
6. **不做（本 ADR 明确排除）**：callback/promise_then 工作流语义（编排层方案——
   用户写第二个 entry，不升 Reference schema）；masterchain 专用指令、library
   发布、extra currencies、Tact/FunC 发射路径、TVM 汇编直写；formal TASK/TST 与
   release qualification 轴不变。

## 理由

- Tolk + sandbox 在 2026 年已具备 content-addressed 供给与可脚本化验收条件；
  纯异步 actor 模型与 DSL `schedule` 语义天然契合，而 sync call 的诚实 fail-closed
  比把 callback 伪装成同步语义更符合架构不变量（fail closed over best effort）。
- 发射 Tolk 源码（而非 TVM 汇编）复用官方 ABI/wrappers 与编译器维护面，
  是风险最低的 materializer 路径。

## 影响

- `TargetId`/`TargetKind` 新增 `ton`；registry root bytes/digest 变化（测试钉同步）；
  实现计数 8 implemented + 3 design-only；`ArtifactEncoding` 新增 `tolkSource`。
- TON-2（materializer leaf）与 TON-3（sandbox 验收）依赖本 ADR 的冻结身份；
  在 TON-2 落地前 `--target ton` 在 materialize dispatch 显式失败（无 leaf），
  不静默降级。
- 不修改 PRD Phase 1 范围声明、不新增 formal `TASK-*`/`TST-*`、不进
  release-qualification 轴；formal D5–D7 完成态不因本 ADR 改变。
