# ProofForge V2 Product Recovery

ProofForge V2 当前只推进一个产品里程碑：让真实 CLI 的 Counter 源码完成

```text
program source
  → ValidatedSourceV1
  → Typed.Program
  → Semantic.Program
  → EVM-owned Plan / TargetIR
  → deterministic artifacts
```

## 为什么重基线

历史 D1 工作把 TaskQualification、custody、formal evidence、eligible-host ceremony
放进了每个开发任务的关闭路径。结果是源码技术面已经通过，产品仍因单维护者无法完成的
多主体发布仪式而停住。恢复模式把两类结论重新分开：

- **development completion**：产品路径、类型/语义、目标制品和普通测试通过；
- **release qualification**：SBOM、主机资格、clean-room、签名/custody 和正式证据通过。

后者不能伪造，也不再阻塞前者。

## 当前范围

1. 建立快速且普通主机可运行的 `docs-check`、`test-fast`、`dev-check` 与 `ci`。
2. 把历史治理审计和正式发布检查隔离到 `governance-check`、`release-check`。
3. 直接接通 Syntax/Loader → `ProgramV1` → Typed/Semantic → EVM Counter。
4. 产品纵切面稳定后，再盘点 qualification 代码；未经确认不删除或大规模搬迁。

## 当前结果

- `docs-check`/`dev-check`/`ci` 已不再运行 Stage-0 或 TaskQualification；历史审计由
  `governance-check` 显式运行，release host preflight 在当前主机准确返回 `PF-HOST-INELIGIBLE`。
- CLI `build`/`build-counter` 只调用 `selectProgramV1` 与 `compileValidatedSourceV1`；
  `Typed.checkV1` 直接消费 ProgramV1，不构造 legacy `Source.Program`。
- Counter 已从真实 source 完成 ProgramV1 到目标制品的 CLI smoke；快速测试固定
  ProgramV1 identity/sourceHash/NodeId、Typed/Semantic、EVM Plan/IR 与 deterministic Yul/ABI。
- 旧 Lean command/export/Loader API 仍仅供历史 characterization tests，未被产品 CLI 调用；
  是否搬迁或删除将在清单完成后单独确认。
- [`QUALIFICATION_INVENTORY.md`](QUALIFICATION_INVENTORY.md) 已确认 qualification 子系统为
  84 个文件、58,429 行；ordinary product gate 无直接依赖，本轮未移动或删除任何文件。

## 明确暂停

- 新 `TASK-*`、`D1-PA-*`、`EV-*`、freeze package 或资格对象；
- TaskQualification service/supervisor、durable custody 与 formal-evidence 协议扩张；
- 新 target、更多 DSL 构造或大范围规格补齐；
- 产品路径中的 legacy→ProgramV1 adapter、dual reader、第二套 ProgramV1 decoder 与任何 fallback；
- 为了让历史表格显得“完成”而回填或降级证据。

## 命令边界

```bash
just dev-check          # 日常：docs + build + 核心产品测试
just ci                 # 普通主机：完整产品测试与负例
just governance-check   # 显式审计历史 task/freeze/evidence
just release-check      # 发布预检；非 eligible 主机应明确拒绝
```

`just ci` 成功只说明产品开发门禁通过，不等于 formal/hermetic evidence。
`just release-check` 失败也必须区分“主机/ceremony 不合格”和“产品代码失败”。

## 完成条件

恢复里程碑只有在 CLI 的 Counter 不经 legacy fallback，真实走完
`ValidatedSourceV1 → Typed → Semantic → EVM Plan/IR → artifact`，且 `just dev-check`
与 `just ci` 通过后才完成。随后再决定 legacy frontend 与 qualification machinery 的
删除/搬迁，不在本阶段提前做破坏性清理。
