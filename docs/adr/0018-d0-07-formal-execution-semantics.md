---
id: ADR-0018
title: D0-07 formal 执行语义：fixture 验收域、linux bwrap stage 引擎、freshness 判定与 finalizer 身份
status: proposed
owner: architecture
updated: 2026-07-19
normative: true
---

# ADR-0018：D0-07 formal 执行语义——fixture 验收域、linux bwrap stage 引擎、freshness 判定与 finalizer 身份

- 状态：`proposed`
- 日期：2026-07-19

## 背景

`TASK-D0-04` 的真实 six-item activation（`EV-20260719-0075`，cutover）使 `TASK-D0-07`
进入 `in_progress`（冻结包
[`task-freeze-packages/TASK-D0-07.json`](../governance/task-freeze-packages/TASK-D0-07.json)）。
冻结后的实现缺口分析发现四处规格级冲突/歧义，不先裁决就无法定义
`TST-EVIDENCE-002`/`TST-ISO-002` 的 RED 正例：

1. **77-ID 精确分派陷阱**：`formal_evidence.py` 强制 formal record 的
   `gates[].testIds` 精确等于 resolved `requiredTestIds`，而真实 activation 的
   required set 是整个 Phase 1 分母（当前 77 个 TST，含未实现的 D1+/D3/D8 与
   `TST-ISO-003`）；spec（[`gate-catalog-finalization.md`](../specs/gate-catalog-finalization.md)
   formal finalization 节）还要求每个非 D0 gate 的 EV 为 formal qualification。按字面，
   D0-07 将等价于全部 77 个 gate 的 formal 证据——那是 release 门槛（`05-test-spec.md`
   Release Acceptance 节），不是单个任务。
2. **SBPL 钉死的 wire vs 唯一 eligible linux host**：sandbox invocation receipt 与
   catalog locks 的 join 目标是 darwin SBPL 字面量（`engine.path=/usr/bin/sandbox-exec`、
   `policies/<stage>.sb`、`-p` + policy text 的 Popen vector），而 ADR-0016 §5 把 linux
   沙箱引擎 defer 到"新引擎 + 独立 ADR/任务"。当前唯一 eligible host 是 linux
   （`linux-x86_64-mint223-eligible`），TST-ISO-002 的 deny-default stages 必须在其上
   执行。
3. **freshness 窗口未定义**：spec 只钉 `maximumAgeSeconds != 0` 与
   `finalizedAt < expiresAt`，未定义 `expiresAt` 的推导与判定时刻。
4. **finalizer 身份钉矛盾**：真实 activation 的 `tcb.formalFinalizerDigest` 钉的是
   `scripts/gate_evidence.py` 当前字节（"development finalizer candidate"），而真实
   formal finalizer 语义尚未实现。修改该文件会使 TCB 漂移、令 D0-04 关闭门禁 fail
   closed 并强制重跑仪式；另置新脚本则使 formal record 的 finalizer 身份陈述为假。

## 决定

### 1. `TST-EVIDENCE-002`/`TST-ISO-002` 的验收域为 fixture namespace

与 `TST-BOOTSTRAP-001` 的 rehearsal 纪律同型（`05-test-spec.md` 既有条款：activation
positive vector 必须使用与 production lookup tuple 不相交的 fixture namespace 且永不
关闭当前 task）：

1. 两个 TST 的验收在 fixture namespace 执行：fixture required set（fixture 分母等于
   fixture gates，使精确分派可满足）、fixture activation、fixture handoff、fixture
   candidate。真实 activation 只作为 authority 输入形态与 host eligibility 的事实
   来源被消费，不被 fixture 替代或冒充。
2. fixture 产出永不构成本任务的关闭证据，也不构成 formal/hermetic evidence；任务
   关闭仍按冻结包 doneWhen（fixture 验收全绿 + 治理证据 + 信任升级义务）。
3. 77-ID 全量 formal partition 与对真实 activation 的 formal gate 确认为 release 级
   范围，归 `TASK-D8-04`（`TST-ISO-003`），不属于 `TASK-D0-07` 完成面；本决定不修改
   D0-07 冻结包（fixture 验收域是对 TST 语义适用既有 rehearsal 纪律的澄清，不改变
   Tests 集合或完成面语义）。
4. fixture 验收域的规范表述落在 [`gate-catalog-finalization.md`](../specs/gate-catalog-finalization.md)
   （不被 activation 钉住）。`05-test-spec.md` 的文字同步**递延**：该文件被真实
   activation 的 `RequiredTestSetV1.phase5Document.contentDigest` 精确钉住，
   docs_check 的 D0-04 关闭门禁从当前字节重算该 join，直接编辑会使关闭证据失效；
   同步义务记入 P2 债务（owner=quality），在下一次 required-set 重签发（如 D8 的
   real catalog/activation 升级）时一并落地。

### 2. linux stage 引擎 = bwrap profile（修订 ADR-0016 §5）

ADR-0016 §5 的"Linux 沙箱引擎不在本期"由本 ADR 修订为：linux stage 引擎为
**bubblewrap profile 引擎**，darwin SBPL 引擎与既有 wire/证据逐字节不变。

1. **新组件**（D0-07 实现，均为新文件）：`scripts/sandbox_bwrap.py`（profile
   renderer + launcher + receipt publisher）与 per-stage profile（`materialize`/`core`/
   `evm-runtime`）。`scripts/stage0_containment.py` 保持 Stage-0 containment runner
   语义不变，不被复用为 policy 引擎。
2. **stage 语义**：
   - `materialize`/`core`：`--unshare-net` 全断网、tmpfs workspace、只读 bind 白名单
     （locked tool root、candidate archive、stage 输入）、禁止写 candidate tree；
   - `evm-runtime`：`--unshare-user --unshare-net` 的独立 net namespace 内将 loopback
     置 up——网络可达面恰为 loopback（严格强于 exact-local-port：根本不存在 LAN/外部
     路由，LAN refusal 与 adjacent-port refusal 自动成立）；payload 绑定端口记入
     receipt `runtimePort`；LAN IP、相邻端口与非 loopback 连接的拒绝仍以 probe 实证。
   - closed-FD/stdin EOF/output cap/timeout 复用 Stage-0 containment 的既有原语
     （`--die-with-parent`、rlimits、bounded capture）。
3. **engine-neutral receipt 扩展**（`proof-forge.sandbox-invocation.v1` 的兼容扩展）：
   - `engine` 由字面 `{path: "/usr/bin/sandbox-exec", observedSha256}` 扩展为
     `{id: "sbpl" | "bwrap", path, observedSha256}`；darwin 既有 receipt 的 engine
     值在扩展语法下逐字节等价（`id:"sbpl"`），genesis/development 证据不失效；
   - `policy.path` 约定扩展为 `policies/<stage>.sb`（sbpl）或
     `policies/<stage>.bwrap.json`（bwrap rendered profile，closed JSON）；
   - Popen vector 重构规则按 `engine.id` 分派：sbpl 为 engine + `-p` + exact policy
     text + payload argv；bwrap 为 engine + rendered profile argv + payload argv；
   - probe wrapper 契约（exit 77、stderr 恰为 `PF-SANDBOX-PROBE-DENIED\n`、只接受
     EACCES/EPERM）引擎中立，逐字复用现有规格条款；
   - catalog `locks` 的 `sandboxEngine/Renderer/Launcher/ProbeWrapper` 在 linux 钉
     bwrap 组件真实 digest（fixture catalog 在其 namespace 内钉，real catalog 归 D8）。
4. spec 的 receipt/catalog 条款按本扩展做 engine-neutral 化修订（落地变更集），
   darwin 具体值不变。

### 3. freshness 判定谓词

`FreshnessAuthoritySnapshotV1` 补全语义：`expiresAt == observedAt + maximumAgeSeconds`；
finalizer 产生 record 时必须满足 `finalizedAt < expiresAt`（在 finalization 时刻判定）；
`clockSourceDigest` 绑定一份本地观测时钟声明文档（记录时钟来源与最大可信漂移，
development 级，无远程时间权威）。过期或窗口反转一律
`PF-EVIDENCE-FORMAL-UNVERIFIED` 零输出。spec 相应节补文（落地变更集）。

### 4. finalizer 身份

真实 activation 的 `tcb.formalFinalizerDigest` 维持 `scripts/gate_evidence.py` 当前
字节（其 docstring 已声明 development harness 语义）；真实 activation **不重跑**。
fixture 验收域内，fixture handoff 钉 fixture finalizer executable——即 D0-07 交付的
真实 finalizer 脚本，formal record 的 finalizer 身份在 fixture 域内自洽且为真。
`gate_evidence.py` 的字节冻结状态与 D0-04 关闭门禁（TCB 漂移 fail closed）不受影响；
对真实 activation 的 formal finalizer 升级归 D8，届时按新 ADR 重钉。

### 5. 杂项确认

1. `private-scan-policy.json`（真实 private scan 策略文档）提交至
   `docs/governance/bootstrap-closure/private-scan-policy.json`，使
   `policy.privateScanPolicy` 可从 committed 字节解析（当前仅在 gitignored ceremony
   workdir）。
2. support-binding 的 "producer/store" 确认为 publish + readback（与
   `formal_evidence_producer.py` 既有 no-clobber receipt-last 发布一致），不另设
   tuple-lookup service；binding 读取时刻的 `finalizedAt < expiresAt` 按本 ADR §3
   判定。

## 后果

- `TASK-D0-07` 可在 fixture 验收域按冻结包推进 RED/GREEN；本 ADR 不改变其 Tests
  集合、Dependencies 或完成面语义。
- 77-ID formal partition、真实 activation 的 formal gate、真实 catalog 与其
  FormalGateCatalogApproval 归 `TASK-D8-04`/`TST-ISO-003` 范围。
- ADR-0016 仅 §5 被本 ADR 修订（linux 引擎由"不在本期"变为"bwrap 引擎"），其余各条
  与 darwin 全部字节/语义不变；ADR-0016 保持 `accepted`，本 ADR 为其唯一修订来源。
- 既有 SBPL receipt/catalog 证据不失效；engine-neutral 扩展保持 darwin 值逐字节等价。
- `scripts/gate_evidence.py` 等五个 activation 钉住文件的字节冻结状态不变。

## 验证

- 本 ADR 转 `accepted` 后，落地变更集：`gate-catalog-finalization.md` 的 fixture
  验收域条款、freshness 谓词、engine-neutral receipt 与 finalizer 身份注记、
  `docs/adr/README.md` 索引行、implementation log 记录；`05-test-spec.md` 文字
  同步按 §1.4 递延（P2 债务，owner=quality）。
- `TST-EVIDENCE-002`/`TST-ISO-002` 的 RED 正例按本 ADR 定义（fixture namespace、
  bwrap stages、freshness 谓词、fixture finalizer 身份）。
- docs_check 全绿；darwin 回归不受影响（无 darwin 字节变更）；D0-04 关闭门禁
  （required-set PHASE-5 join 与 TCB 复算）不受影响（不触碰 `05-test-spec.md`
  与五个钉住脚本）。
