---
id: ADR-0051
title: SPEC-honesty：external call typed return 的 SPEC-SEM-001 收口（void vs typed）
status: proposed
owner: architecture
updated: 2026-08-16
normative: true
---

# ADR-0051：SPEC-honesty — external call typed return 收口

## 状态

proposed

## 背景

当前存在三方分裂（RPT-028 P1；`docs/research/28-project-wide-honesty-audit.md`）：

1. **SPEC-SEM-001**（[`docs/specs/semantic-core.md`](../specs/semantic-core.md) L154–156）
   仍写：「v1 external call 无 return value，因此 response 没有 value 字段；增加
   typed return 必须升级 semantic/reference schema，而不能塞入 context。」
   其 `ExternalResponseV1` 载体（L79–81）只有 `occurrence` + `disposition` 两字段。
2. **Wire spec**（[`docs/specs/semantic-program-wire.md`](../specs/semantic-program-wire.md)
   L555–560 与 step-j 表）已记 **N-CALL-RET**：`Op.ExternalCall` 的
   `Instruction.result` 可选——`none` 为 void statement call，`some` 为
   value-position sync call，result typeId 必须为可序列化标量
   （Bool / UInt/Int {8,16,32,64,128,256} / Bytes ≤ maxTypeLengthV1），
   其余形状 `.badCfg`。
3. **产品代码**（N-CALL-RET，2026-08-04 done）：值位置 `call` 已进 ProgramV1 /
   Normalize / Wire / Reference；`ReferenceMachineV1.ExternalResponseV1` 已带
   `returnValue? : Option ReferenceValueV1 := none`。

`docs/05-test-spec.md` L294 要求 TST-SEM-002 使用 SPEC-SEM-001 的 `ReferenceV1`
载体；载体过期使 formal TST-SEM-002 无法诚实闭合。semantic-core L146–152 的
2026-08-15 诚实横幅已声明收口须经本类 ADR，不得静默改写正文。

## 决策

1. **canonical 语义采纳产品/Wire 侧**：v1 semantic `Op.ExternalCall` 的 typed
   return 是合法一等形态。SPEC-SEM-001 的 `ExternalResponseV1` 升级为三字段：
   `occurrence`、`disposition`、`returnValue? : Option Value := none`；
   `returnValue?` 仅当 `disposition = returned` 且 call site 绑定 result 时为
   `some`，其 canonical valueBytes 必须精确匹配 call site 声明的 result TypeId。
2. **schedule 维持 void**：`Op.Schedule` 无 result、无 response cursor 行。
   semantic-core L160–163 的 workflow-intent 语义不变，不受本 ADR 影响。
3. **本 ADR accepted 后**授权对 `docs/specs/semantic-core.md` 做一次显式修订：
   替换 L154–156 旧句为「v1 external call 的 typed return 经 N-CALL-RET schema
   升级为一等形态（本次升级即旧句要求的 semantic/reference schema 升级）；
   response 携带 optional `returnValue?`」，并同步 L79–81 载体定义与
   2026-08-15 诚实横幅（改为指向本 ADR 的收口记录）。acceptance 前不得改写。
4. **result 形状边界**跟随 Wire spec 现行 gate：serializable scalar
   （Bool / 合法 UInt/Int 宽度 / Bytes ≤ cap）；Unit/Map/Struct/Enum/Option/
   Array/Principal/Field/String result 仍 `.badCfg` fail closed。放宽属未来
   独立 ADR。
5. **target 非均匀性不变**：本 ADR 只收口 target-neutral semantic/reference
   schema 的文字权威。各 target 的 returndata ABI（EVM UInt8–256 open、
   Bool/Int/Bytes FC；Noir witness-binding；等）继续由 resolver capability 与
   `B-CALL-SEM` 管辖，不由本 ADR 代签。

## 后果

- TST-SEM-002 的 SPEC 载体障碍移除（**不**等于 TST-SEM-002 done：formal
  corpus/evidence 门槛独立存在，且 `TASK-D1-01` 资格前置不变）。
- `docs/research/14-n5-call-return-schema.md` / `11-feature-coverage-audit.md`
  的历史快照注记保持为历史；live 权威为 Wire spec + 本 ADR。
- 不改任何代码：产品/Wire/Reference 已是决策后的形态；本 ADR 是文字权威收口。

## 排除

- 不开 schedule response / 跨 tx deferred 语义。
- 不开 aggregate / String result。
- 不决定 EVM deployment-address binding（`B-CALL-SEM` / ADR-0029 轴）。
- 不关闭任何 formal TASK/TST/EV。
