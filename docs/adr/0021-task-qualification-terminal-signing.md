---
id: ADR-0021
title: Task qualification protected acceptance 的一次性终结签名
status: proposed
owner: architecture
updated: 2026-07-23
normative: true
---

# ADR-0021：Task qualification protected acceptance 的一次性终结签名

## 背景

accepted `SPEC-TASKQUAL-001` §8.4 同时规定：

1. production protected consumer 的唯一入口恰为七个 required positional 参数；
2. 五个继承 channel 中只有 `authorityStoreFd` 是 authenticated service channel；
3. `pf.taskqual.authority-store.rpc.v1` 只允许 lookup，禁止其他 operation；
4. 运行后生成的 `ProtectedTaskQualificationAcceptanceV1` 必须由 current、non-revoked
   Architecture + Quality + Security 三个 distinct principals 对其独立 statement domain 会签。

最终 acceptance statement 只有在 trusted clock、current revocation head、safe-open archive/Git、
live session、profile/pin、provenance bundle 和 pure verifier 全部验证完成后才能确定。当前七参数
入口、closed provenance roles 与 lookup-only store 均没有 signer/HSM capability；public policy 也不能
推导 Ed25519 private signature。handoff signature、store service signature 和 acceptance signature
覆盖不同 wire、message domain 与授权语义，不能复制或复用。

因此当前 accepted contract 不可实现。现有 `ProtectedAdapterInput.signing_seeds` 是规范外 caller
注入，只能用于 synthetic test，不能形成 `production-candidate-bound` authority。

## 决定

### 1. 保留唯一七参数 API

production API 仍且只能是：

```text
protect_taskqualification_v1(operationBytes, handoffBytes,
  authorityPolicyFd, authorityStoreFd, candidateArchiveFd,
  provenanceBundleFd, trustedClockFd)
```

七个参数均 required positional-only；继续禁止 path、environment、kwargs、default、typed shortcut、
signing seed、private-key bytes 或 signer handle。继承 FD 集合和五个 channel 的 exact 约束不变。

### 2. v1 保持 lookup-only，production 改用 v2

`pf.taskqual.authority-store.rpc.v1` 保持原 accepted lookup-only 语义，不原地扩大。
`SPEC-TASKQUAL-001` §8.4 的 production protected handoff 必须改为钉住：

- protocol：`pf.taskqual.authority-store.rpc.v2`；
- service descriptor schema/version：对应的 taskqualification-owned v2 closed type；
- v2 复用 v1 的 authenticated hello/current-head/lookup 语义，并只增加恰一个 terminal
  `sign-acceptance` operation。

v1 descriptor、frame 或 client 不得被 v2 consumer 接受；不存在 fallback、protocol negotiation、
dual reader 或 best effort。

### 3. terminal sign-acceptance 不是通用签名服务

v2 在同一 `authorityStoreFd` session 上只允许：

1. exact current/non-revoked lookup 序列；
2. 全部 required lookup 已成功且 head 未漂移后，恰一次 terminal acceptance-signing request；
3. terminal response 后立即关闭 session，并永久消费 `(taskId, operation, runId, nonce)`。

禁止 arbitrary digest/message signing、第二次 sign、publish、store-object mutation、key export、
seed readback 或跨 task/operation/session 使用。任一失败、EOF、extra frame、timeout、head drift、
nonce replay 或 response mismatch 均永久 spend nonce，不得在同 nonce 重试。

### 4. terminal request 的最小授权闭包

v2 specification 必须定义 canonical closed request/response。request 至少逐字段绑定：

- `requestId`、`taskId`、`operation`、`runId`、`nonce`；
- 当前 `headSequence`、`headDigest`；
- signed protected handoff 的 full digest；
- exact adapter identity、production profile pin 与 snapshot parser identity；
- canonical unsigned `ProtectedTaskQualificationAcceptanceV1` bytes，且 `signatures=[]`；
- 按 `pf.taskqual.protected-acceptance-statement.v1` 重算的 exact statement digest。

service 必须在任何 principal signing 前：

1. exact-decode/re-encode request 与 unsigned acceptance；
2. 重算 statement digest，并拒绝 unknown/extra/missing field；
3. 验证 task/operation、adapter/profile pin/parser、trusted instant 与该 session 已认证的
   handoff/current lookup state一致；
4. 确认 required lookup 已完成、nonce 未使用且 current head 再查询仍相等；
5. 确认 acceptance 的 authority class、candidate key、bundle/subject/provenance digests及
   D0 receipt-only nullable fields满足 `SPEC-TASKQUAL-001` closed rules。

service 只对 acceptance signature domain 签名，不接受 caller 提供的 domain 或 message。

### 5. terminal response 与角色会签

response 必须逐字段 echo request/session/head/statement digest，携带：

- 按 keyId ASCII 严格升序且唯一的 `ApprovalSignatureV1`；
- current activated `BootstrapAuthorityPolicyV1` 中 Architecture + Quality + Security
  fixed rule 的三个 distinct principals；
- v2 service key 对完整 response 的独立 service signature。

adapter 必须同时重验角色 signatures、quorum、response service signature、echo tuple、最终 current head，
随后才可组装 signed acceptance。角色 signature 与 service signature不可互换。

### 6. private-key custody

角色 private keys 只存在于 candidate-external operator/HSM-backed signer backend。D0-10 ceremony
可以在独立受保护 service 进程中以 safe-open、single-link、mode-restricted seed FD 初始化该 backend；
这些 seed FD：

- 不继承给 protected adapter；
- 不出现在七参数 API、handoff channels、provenance bundle、candidate archive、Git tree、EV 或日志；
- 必须逐一派生公钥并 exact 匹配 current policy principal 后才启用；
- session 结束后关闭，best-effort 清零可变 buffer。

production adapter 模块不得导出 caller-injected `signing_seeds`、`authority_principals` 或等价 seam。
RFC 8032 fixture seeds 只允许测试 namespace，curve work 前与 production policy静态不相交。

### 7. authority 与 docs-check 边界不变

本决定只修复 protected acceptance 的可达签名能力：

- pure verifier 仍只返回 `production-content-verified` 或 `fixture-non-authoritative`；
- 只有完整 v2 protected path 可返回 `production-candidate-bound`；
- root `docs_check` 永远 structural-only，不调用 signing RPC、不读取 candidate-external completion，
  也不把 optional P mirror 当 authority；
- D0-10 的 C→approval→D→external receipt/acceptance→optional P 无环状态机不变；
- `BootstrapAuthorityPolicyV1` six-item activation、taskRules、RequiredTestSet 与 release aggregate不变。

## 变更分类与冻结判定

这是 C3 protocol/schema repair：v1 不变，新增 v2 并让 §8.4 production pin 使用 v2。它不改变
`TASK-D0-10` 的 Output、Tests、Dependencies、Prerequisites 或 done 语义；它使冻结完成包已经要求的
protected consumer 可实现。按 `GOV-TASK-FREEZE-001` R2，TASK-D0-10 在本 ADR 与配套 spec 未
accepted 前保持 `blocked`，不申请 Freeze Exception，也不新增 TASK/TST。

## 替代方案

1. **给七参数 API 增加 signer FD**：边界清楚，但会改变 handoff channels、exact FD set 和 public API，
   变更更大，拒绝。
2. **把 seeds 作为 Python 参数或环境变量交给 adapter**：违反唯一 API、key custody 和 fail-closed
   provenance，拒绝。
3. **预签 acceptance 或把 signatures 放入 provenance**：statement 尚未确定并产生循环，拒绝。
4. **复用 handoff/service signatures**：message/domain/quorum 均不同，密码学和授权语义均不成立，拒绝。
5. **adapter 内嵌三把长期私钥**：无可接受 custody/rotation/role isolation，拒绝。

## 安全后果

- 好处：不增加 adapter FD 或 ambient secret；signing capability 由 authenticated、current-head-bound、
  one-shot service session承载；v1 不被静默扩义。
- 风险：v2 signer 若只实现 `sign(digest)` 会成为三角色签名 oracle。实现与测试必须证明 request closed、
  exact acceptance-domain、session tuple、adapter/profile/head、nonce 和 terminal state全部绑定。
- 独立性：当前三个角色映射同一 maintainer；仍必须按 `GOV-MAINTAINERS-001` 取得独立只读安全复审，
  且 review P0/P1=0 后才可 accepted。

## 验证要求

配套 spec 与既有 `TST-DOC-001/task-qualification-v1` subprofile必须至少覆盖：

- public protected API 恰七个 positional-only 参数，无法注入 seed/path/env/kwargs；
- v1 descriptor/frame 被 production v2 路径拒绝；
- terminal request canonical/closed，domain、statement、session/head/handoff 任一漂移拒绝；
- generic message、第二次 sign、nonce replay、旧 head、signing 中 head drift 均拒绝；
- 缺任一 required role、同 principal 多角色、revoked key、fixture key均拒绝；
- role signatures 与 service signature互换或复制 handoff signature均拒绝；
- failure 后零 acceptance，成功仅生成 exact signed `ProtectedTaskQualificationAcceptanceV1`；
- root docs-check 保持 structural-only，D/P mirror不获得 authority。

## Rollback

在任何 production acceptance 签发前，可删除 v2 proposal/implementation并让 TASK-D0-10 保持
`blocked`；v1 lookup-only behavior与既有 D0-01…09 历史均不变。若 v2 已激活后发现缺陷，立即撤销
v2 service/profile pin和未消费 handoff nonce，禁止回退 v1或 caller-seed adapter；修复必须走新 ADR/
protocol major。
