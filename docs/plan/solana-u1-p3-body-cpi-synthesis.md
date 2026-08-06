---
id: PLAN-SOLANA-U1-P3
title: Solana U1 P3 — full body + optional CPI sites 同 product ELF
status: draft
owner: engineering
updated: 2026-08-06
normative: false
parent: ADR-0032
profile: solana-sbpf-cpi-elf-v1
---

# Solana U1 P3：full body + optional CPI sites 同 product ELF

> **性质**：可实施的工程设计（Lane C），**不是** ADR 改写、**不是** formal TASK-D5、
> **不是** 当日实现。成熟度仅工程；不得写成 mainnet/hermetic/formal 完成。  
> **父合同**：[`docs/adr/0032-solana-unified-materializer.md`](../adr/0032-solana-unified-materializer.md)
> P3 验收信号——「同 ELF 含 full body + 可选 CPI sites」。  
> **文件所有权切片**：[`solana-u1-p3-file-ownership.md`](solana-u1-p3-file-ownership.md)。

## 0. 代码事实锚点（read-only 调研）

| 符号 / 路径 | 当前行为 |
|---|---|
| `EmitSbpfAsmV1.buildFromCapability` | `solana-sbpf-cpi-elf-v1` 双路：`!hasSites && semanticNeedsFullBodyV1` → `productBaseFilesFullBodyHybridV1`；否则 → `CpiV1.productBaseFilesFromCapabilityV1` |
| `semanticNeedsFullBodyV1` | 任一 callable `blocks.size > 1`，或 body 含 `indexGet`/`indexSet`/`construct`/`fieldGet`/`fieldSet`/`variantTag`/`variantPayload` |
| `productBaseFilesFullBodyHybridV1` | CPI product **Plan/IDL** + `fullBodyIrFromProductCapabilityV1` → `emitSbpfAsmV1`；IR 文本为标记 schema `proof-forge.solana.full-body-hybrid-ir.v1`；bindings 带 `fullBodyHybrid:true` |
| `materializeFullBodyPlanForProductV1` / `fullBodyIrFromProductCapabilityV1` | retained `SemanticProgramV1` → LowerSemantic Plan → EmitIR `IR`（可 `admitCallerRole`） |
| `CpiV1.productBaseFilesFromCapabilityV1` | `productPlan` → `resolveSolanaCpiProductIRV1` → `emitCpiProductSbpfV1`（`CpiEscrowIRV1` candidate DTO + composite emitter） |
| `CpiEscrowIRV1.requireStraightLineCallable` | **单 block**、`entryBlock==0`、空 `loopBounds`、无 block params、terminator 仅 `return` |
| `CpiEscrowBodyOpV1` | 窄 body：UInt64/UInt8 param/lit、UInt64 state load/store、checked ±×÷%、siteArgChecks/siteChecks/invoke、envRead、context.caller Principal 9-temp、return；**拒** Map/aggregate、unary、pureCall、branch/switch/jump、`Op.Constant`、多数 ContextRead |
| `EmitCpiEscrowSbpfV1` 帧 | role table 1024B + slots + `escrowTempBaseV1` temps + CPI scratch；`escrowMaxFrameBytesV1 = 4096` |
| `EmitSbpfAsmV1` 帧 / 布局 | temps 自 `r10`：`(cursor+1)*8 ≤ maxSbpfStackBytesV1(4096)`；**默认单账户** input layout（`admitCallerRole` 时 account[1] pf_caller 部分 deferred） |
| `FinalizeV1.finalizeCpiElfProfile` | base 重算经 **sole** `buildFromCapability`；`productIrFromCapabilityV1` 失败时 `irDigestNote = "full-body-hybrid"` |
| P2 已绿 | `Examples/MiniAmm` 零 CPI + Map/CFG → hybrid product pin（`Tests/Product/MiniAmmSolanaV1`）；TipJar/TokenJar 等 **有 sites** 仍走 escrow product IR |

**P3 要闭合的空洞**：当 `cpiSites` 非空 **且** body 需要 multi-block / Map / 更广 op 时，今日只能进 escrow 路径并在 IR 边界 fail closed；hybrid 又 **禁止** sites。两者不可同 ELF。

---

## 1. 问题 / 双路径

### 1.1 产品问题

ADR-0032 U1 的 sole rail 是 `solana-sbpf-cpi-elf-v1`。P2 已把「零 CPI + 全量 body」接到 hybrid，把「有 CPI + 窄 straight-line body」接到 escrow product IR。  
E4 MiniAMM 北极星与后续 token 镜像需要：

- full body（Map Principal、if/match、checked mul/div、可选 `context.caller`）
- **可选** CPI sites（`pf.assets.*` / `solana.system.*` catalog 子集）
- **同一** product `.s` → locked `sbpf` → `{name}.so`，且 Finalize exact join 不撒谎

今日 **不存在** 该合成路径。

### 1.2 双路径图（P2 现状）

```
buildFromCapability (profile = solana-sbpf-cpi-elf-v1)
        │
        ├─ productPlanFromCapabilityV1  ──► cpiSites?
        │
        ├─ !hasSites ∧ semanticNeedsFullBodyV1
        │       └─► productBaseFilesFullBodyHybridV1
        │             Plan/IDL = CPI product
        │             IR JSON  = hybrid marker (非 productIrSchemaV1)
        │             .s       = EmitSbpfAsmV1(fullBody IR)
        │             零 sol_invoke*
        │
        └─ else (hasSites ∨ ¬needsFullBody)
                └─► productBaseFilesFromCapabilityV1
                      Plan → resolveSolanaCpiProductIRV1
                      (requireStraightLine + CpiEscrowBodyOp 窄面)
                      .s = emitCpiProductSbpfV1
```

### 1.3 失败组合矩阵

| body 需求 | CPI sites | 今日路径 | 结果 |
|---|---|---|---|
| 单块 UInt64 ±×÷% | 有 | escrow product | OPEN（TipJar/TokenJar 类） |
| multi-block / Map / aggregate | 无 | full-body hybrid | OPEN（MiniAmm pin） |
| multi-block / Map / aggregate | 有 | escrow product | **FC**（`requireStraightLine` / Index*） |
| multi-block / Map | 有 | hybrid | **不可达**（`hasSites` 短路） |

### 1.4 次要诚实债（P3 应顺手收紧，不必单独 epic）

1. Hybrid 的 `cpi-ir.json` / bindings 为 **marker**，非 `proof-forge.solana.cpi-product-ir.v1` 真 digest；Finalize 用字面 `irDigest=full-body-hybrid`。
2. Full-body 与 multi-role CPI 的 **账户序列化布局** 未统一（`EmitSbpfAsmV1` account[1] signer/dup 仍有 deferred 注释）。
3. 两套帧模型：body temps 自 `r10` 堆叠 vs escrow role table + CPI_BASE scratch。

---

## 2. 目标架构 + 拒绝的替代方案

### 2.1 目标：单一 product 合成 emit（P3）

在 **不** 发明第二套 Semantic 源、**不** 假开 catalog 外 CPI 的前提下：

1. **始终** 走 CPI product Plan 权威  
   `ResolvedEngineeringBuildV1` → `resolveSolanaCpiProductCapabilityV1` → `deriveSolanaCpiPlanFromProductCapabilityV1` → `SolanaCpiProductPlanV1`  
   （roles / pdaRules / handlers / cpiSites / contextReadSites / envReadSites 不变；profile/catalog digest exact 保持）。

2. **Body 语义 sole 源** 仍是 retained `SemanticProgramV1`  
   复用 `materializeFullBodyPlanForProductV1` + `EmitIRV1.lower` 得到 full-surface typed `IR`（或等价 private carrier），**禁止** source 再扫。

3. **合成层（本设计新增概念，名称可实现时最终敲定）**  
   建议 private 名：`synthesizeProductHandlerAsmV1` / carrier `SolanaUnifiedProductAssemblyV1`  
   对每个 handler source order：

   | 阶段 | 权威 | 复用现有实现 |
   |---|---|---|
   | A. LoaderV3 多角色 preflight + role table 物化 | product Plan | `EmitCpiEscrowSbpfV1` / preflight 路径已有 walker |
   | B. Handler body 全语言面 | full-body `IR` / Operation | `EmitSbpfAsmV1` op emitters（checked arith、Map multi-leaf、if/switch/for、pureFn inline…） |
   | C. CPI 锚点 | Plan `cpiSites` 的 `(handlerId, blockId, instructionIndex)` 与 Semantic ExternalCall 对齐 | 既有 `siteArgChecks` → `siteChecks` → `invoke*` recipes（`emitCpiProductSbpfV1` 内部） |
   | D. context.caller / envRead | Plan sites + ADR-0031 | escrow body ops 或 full-body `callerPrincipalLeaf` **二选一统一**（见风险） |

4. **单一帧合同**（强制）  
   固定有序区域，全部相对 `r10`，互不重叠，总和 `≤ 4096`：

   ```
   [ role table 1024B | fixed slots | body temps | CPI scratch ]
        ↑                      ↑           ↑            ↑
     Plan maxOuterRoles     preflight   EmitIR cursor  maxSiteScratch
   ```

   - Body 与 CPI 共享同一 `r10` 约定；**禁止** 两套互不知晓的 temp 分配器各算各的 4096。
   - CPI site 发射前/后必须恢复/文档化 callee-clobber 寄存器纪律（与 #124 sequential overlay 一致：同 handler source order 叠加；失败 full snapshot rollback 由 runtime 合同保持，不在 P3 重定义）。

5. **制品形状保持**（Finalize 友好）  
   仍输出与 #125 相同 base 序：

   ```
   {name}.cpi-plan.json
   {name}.cpi-ir.json
   {name}.idl.json
   {name}.s
   {name}.cpi-bindings.json
   ```

   P3 完成后：`cpi-ir.json` 必须是 **可重算 digest** 的统一 product IR（schema 可 versioned revision，禁止 silent 改 active catalog digest），**消灭** hybrid marker 作为长期产品路径。

6. **Dispatch 归约**  
   `buildFromCapability` 在 cpi-elf 上最终只剩 **一条** product 合成入口；P2 hybrid 与「窄 escrow-only body」变为合成器的 **子集行为**（零 sites 时不发射 `sol_invoke*`；窄 body 时可不跑 full Map lower），而非顶层 if/else 永久分叉。

### 2.2 与 ADR-0028 / #125 的关系

- 账户 / CPI 合同、frozen catalog、exact profile id、sync-only、async FC：**不变**。
- Product activation 已是 ordinary resolver；P3 不重开 preactivation lane 作为产品面。
- Preactivation `EmitCpi*Token|Ata|…` 历史 lane：**不** 要求 P3 删除（ADR-0032 非目标）。

### 2.3 拒绝的替代方案

| ID | 方案 | 拒绝理由 |
|---|---|---|
| R1 | 永久保留 P2 双路径，业务拆两个 program | 破坏「同一 handler source order overlay」与 MiniAMM+token 同构 |
| R2 | 把 Map/CFG 全部塞进 `CpiEscrowBodyOpV1` 扩张 | 第二套假 body IR，与 ADR-0032「禁止第二套假 Map IR」直接冲突；维护成本爆炸 |
| R3 | 在 `EmitSbpfAsmV1` 用现有 empty-meta `externalCall` 冒充多账户 CPI | 非真实 roles/PDA/Token 合同；破坏 #111–#125 诚实性 |
| R4 | Body 与 CPI 拆成两次交易 / 两个 ELF | 违反 sequential world overlay 与 product 单 artifact 合同 |
| R5 | 零 sites 继续 hybrid marker 永久化 | Finalize `irDigest` 分裂；inspect/bindings 不可 exact re-encode |
| R6 | 在 single-account shim 上假开 `context.caller` + CPI | ADR-0032 §5 / ADR-0031 明确禁止 |

### 2.4 推荐实现策略（合成方式选型）

**主选：A-then-B-with-site-hooks（IR 级锚点插入）**

1. Full Semantic → `IR`（EmitIRV1），ExternalCall **不** 在 full-body emitter 里降成 empty-meta invoke。  
2. 合成器扫描 handler body ops / Semantic anchors，在对应 instructionIndex 将 ExternalCall 替换为 **CPI site 伪 op 序列**（引用 Plan siteId），其余 op 走 EmitSbpfAsm 既有 emitter。  
3. Handler 序言始终发射 multi-role preflight（即使零 sites，也可退化为 state+optional pf_caller 的 role 子集——与 multi-account layout 硬化同切片或紧前切片）。

**备选（仅当 A 导入环/帧冲突过大）：文本拼接合成**  
先 emit body `.s` 片段与 CPI recipe 片段再链接——**不推荐** 为首选：标签/帧/寄存器卫生极难 exact pin。

---

## 3. 分阶段切片 + 并行 lane 文件所有权

> 详细表见 [`solana-u1-p3-file-ownership.md`](solana-u1-p3-file-ownership.md)。  
> 原则：**一次一个 shared cutover**；文件不重叠可并行；`main` 为 sole integration；Lane 不得改 ADR-0032 正文/backlog/targets 除非主代理串行文档 PR。

| 切片 | 目标 | 完成信号（工程） | 主文件（示意） | 可并行？ |
|---|---|---|---|---|
| **P3-0** | 本设计 + ownership 冻结 | 文档 merged 或 worktree 设计 commit | `docs/plan/*` only | — |
| **P3-a** | 统一 IR carrier 草图 + fail-closed 门：`hasSites ∧ needsFullBody` 从「进 escrow 后 FC」改为 **显式 planInvariant 诊断**（可选过渡） | 聚焦 Lean 负例消息稳定 | `CpiEscrowIRV1` 诊断字符串 / 或 `EmitSbpfAsmV1` dispatch 前提示 | 与 P3-b 文档可并行，代码避免同文件 |
| **P3-b** | **帧/布局合同** private 模块：role table + body temps + CPI scratch 预算 API | unit pin：零 overlap、超 4096 FC、与现有 escrow frame 公式兼容子集 | **新** `Solana/ProductFrameV1.lean`（建议） | 独立 lane |
| **P3-c** | 合成器 skeleton：零 sites 时行为 ≡ 今日 hybrid **或** 真 product IR + full-body ops（选一落地，优先消灭 marker） | MiniAmm pin **不回退**；`irDigest` 可重算 | `CpiProductV1`、`EmitSbpfAsmV1` dispatch 收敛、**新** `ProductSynthesizeV1.lean` | 依赖 P3-b |
| **P3-d** | Site hooks：单 block + 已支持 escrow body ops + **一个** catalog invoke 与 full-body temps 共存 | 小 demo：state UInt64 ± + 1× `solana.system.transfer` 或 `pf.assets.native.transfer` 同 ELF；`sol_invoke_signed_c` 出现在 `.s` | `EmitCpiEscrowSbpfV1`（recipe 复用）、synthesize | 依赖 P3-c |
| **P3-e** | CFG：if/branch 与 site 锚点 source order；仍 FC for/loop 跨 site 若帧不够 | multi-block + 1 site Lean pin | `EmitIRV1`/`EmitSbpfAsmV1` region + synthesize | 依赖 P3-d |
| **P3-f** | Map/Index* + site（MiniAMM-class body + 可选 transfer） | MapTip 类 demo product build；可选 host-optional Mollusk | LowerSemantic 已有 Map；synthesize + layout | 依赖 P3-e |
| **P3-g** | Finalize/bindings 诚实：去掉 `full-body-hybrid` 字面特例；hybrid 路径并入统一 IR | `FinalizeV1` + product pin 证据字段 | `FinalizeV1.lean`、`CpiProductV1` bindings | 与 P3-f 后期串行 |
| **P3-h** | multi-account layout 硬化（acc1 dup/signer exact）+ MiniAMM Mollusk（可拆 E4） | ADR-0032 验收剩余项 | `EmitSbpfAsmV1` layout、runtime-tests | 可与 P3-f 后并行 runtime lane |

**Import 纪律（防环）**

- 今日 hybrid 放在 `EmitSbpfAsmV1` 是为了避免 `CpiProductV1` ↔ `EmitSbpfAsmV1` 环。  
- P3 合成模块应处于 **二者之上的叶子**：只 import Plan/IR/Emit 表面，**不** 被 LowerSemantic 反向依赖。  
- 建议：`ProductSynthesizeV1` ← `CpiProductV1` + `EmitIRV1` + 抽取出的 frame/recipe helpers；`buildFromCapability` 仅 thin dispatch。

---

## 4. 最小第一纵切 demo（program sketch）

### 4.1 目标

最小程序同时满足：

1. `semanticNeedsFullBodyV1 = true`（强制今日 hybrid 条件之一）  
2. `cpiSites` 非空（强制今日 escrow 条件）  
3. 仍落在 **已 admitted** catalog / extension 内（不新开 Token-2022、schedule、dynamic CPI）  
4. 可在 ordinary product CLI 下 `--target solana --profile solana-sbpf-cpi-elf-v1` build

### 4.2 推荐 sketch：`BodyCpiMapTip`（设计名，非已存在 Example）

```lean
-- 设计草稿：非仓库现成 Example；实现 P3-f 时再落 Examples/ + Tests/Product
program BodyCpiMapTip where
  requires extension pf.assets version "1.1.0"
    digest "sha256:59412f732e634b0256a02c9ec23a253c38478879d6b74b279e750b220879aaa9"
  -- 若首刀只开 system.transfer，可改 extension solana.cpi.accounts 与 digests
  -- 以当时 active profile/catalog 钉值为准（禁止本文硬编码新 digest）。

  state tips : Map Principal UInt64

  init() do
    tips := Map.empty()

  entry tip(dst : Principal, amount : UInt64) : UInt64 do
    assert amount > 0
    call pf.assets.native.transfer(dst, amount)
    match tips[dst] with
    | Option.some(v) => do
        tips[dst] := v + amount
        return v + amount
    | _ => do
        tips[dst] := amount
        return amount

  view get(dst : Principal) : UInt64 do
    match tips[dst] with
    | Option.some(v) => do return v
    | _ => do return 0
```

**为何够「最小」**

- Map + match → multi-block / Index* → full body。  
- 一个 sync `call` → 一个 CPI site。  
- 无 Token mint/ATA 组合复杂性（相对 TokenJar）；比 MiniAmm 少乘除分支。

### 4.3 更小的 P3-d 垫脚石（若 Map 帧风险过高）

```lean
program BodyCpiIfPay where
  requires extension solana.cpi.accounts version "1.0.0"
    digest "«active pin — 实现时从 profile 读取，不在此发明»"

  state bal : UInt64

  init() do
    bal := 0

  entry credit(x : UInt64) : UInt64 do
    bal := bal + x
    return bal

  entry pay(payer : Principal, recipient : Principal, amount : UInt64) : UInt64 do
    assert amount > 0
    if bal >= amount then
      bal := bal - amount
      call solana.system.transfer(payer, recipient, amount)
      return bal
    else
      return bal
```

- if → multi-block；+ system.transfer site。  
- 无 Map，便于先钉 CFG×CPI source order。

### 4.4 非 demo

- 完整 MiniAMM + token transfer / remove-liquidity：属 **E4**，P3 只提供能力底座。  
- TipJar 现状（单块 UInt64 + CPI）**不是** P3 完成信号（P2 已覆盖）。

---

## 5. 风险

### 5.1 帧（frame）

| 风险 | 缓解 |
|---|---|
| Body cursor + CPI maxSiteScratch + role table > 4096 | P3-b 统一预算 API；超限 **materialize 期** FC，不靠 assembler 偶然失败 |
| CPI recipe 写死 `escrowTempBaseV1` / tempId 与 full-body temp 冲突 | 合成期重新分配 tempId 或 body temps 从 `escrowTempRegionEnd` 起算；禁止两套 base 并存 |
| Principal 9-temp + Map multi-leaf 瞬时峰值 | 复用 escrow `principalLeafEqIx` 式「避免第二份 9-temp」技巧；Map leaf 与 CPI scratch 分时复用需 pin 测试 |

### 5.2 分支（branch）

| 风险 | 缓解 |
|---|---|
| Site 落在 if 臂内，16-bit branch 跨度爆炸 | 延续 SBPF long-range dispatch 纪律；合成后对 handler 做 span 检查 |
| Site 落在 loop body | 首刀 **FC**（与 escrow 拒 loopBounds 一致）；P3-e 仅 if/match |
| Escrow 仅 return terminator vs full-body 多 terminator | 合成以 full-body CFG 为准；site 为 block 内 instruction 锚点，不引入第二套 CFG |

### 5.3 布局（layout）

| 风险 | 缓解 |
|---|---|
| Full-body 单账户 offsets vs CPI multi-account walker | Product 路径 **统一** 走 role-table 布局；state 数据区通过 role local → account data 指针，不再假设固定 ACC0-only（P3-h 可与 P3-c 绑定最小子集） |
| `context.caller`：hybrid 的 `callerPrincipalLeaf` vs escrow `contextReadCaller` | 统一 rail 上 **只保留一种** 物化（推荐 Plan contextReadSites → 与 #125 相同 signer-role 检查）；删除双语义 |
| account[1] dup/signer deferred | 不得在文档中声称 runtime 已硬化；P3-h / Mollusk 才关闭 |

### 5.4 Finalize / 身份

| 风险 | 缓解 |
|---|---|
| `productIrFromCapabilityV1` 仍 FC 而 `buildFromCapability` 成功 → 假 hybrid digest | P3-g：合成成功 ⇒ product IR resolve 必须成功且 sourcePlanDigest join |
| Bindings 缺 package pins（hybrid 简化 JSON） | 统一走 `encodeProductBindingsJson`（active catalog admitted 包） |
| 双路径字节漂移 | Finalize 继续 sole `buildFromCapability` 重算；禁止 Finalize 私有第二 emit |

### 5.5 工程过程

- 超大文件（`CpiEscrowIRV1` ~3k、`EmitCpiEscrowSbpfV1` ~2.8k、`EmitSbpfAsmV1` ~2.3k、`LowerSemanticV1` ~4k）并行易冲突 → 见 ownership 硬边界。  
- ordinary `just ci` **不得** 因 Mollusk 变红；runtime 保持 host-optional / `just solana-runtime`。

---

## 6. 测试计划

### 6.1 Lean（ordinary `just ci` / `dev-check` 可进）

| 类 | 内容 | 建议位置 |
|---|---|---|
| Dispatch | `hasSites∧needsFullBody` 走合成路径，不再 escrow FC / 不再 hybrid 短路 | `Tests/Targets/*` 或 `Tests/Materialization/*` |
| 制品形状 | 五 base 文件序；`.s` 含 `sol_invoke_signed_c`（有 site 时）与 body 标签 | Product pin |
| IR 身份 | `cpi-ir.json` schema/digest 可 `resolve` 重算；bindings 含 planDigest/irDigest/profile/catalog | Product pin |
| 回归 | `MiniAmmSolanaV1`（零 site full body）、`TipJarSolanaV1` / TokenJar 类（有 site 窄 body） | 既有 Fast 套件不红 |
| 帧 | 预算边界 unit：equal accept / +1 FC | 新 frame suite |
| 负例 | loop 内 site、unadmitted package、async schedule、legacy profile call | FC 诊断稳定 |

### 6.2 Host-optional Mollusk（**不**并入 ordinary ci 计次）

| 阶 | 内容 |
|---|---|
| P3-d+ | 小 demo：credit/pay 或 transfer + state 读写；成功路径 + 内层 CPI fail 全账户 rollback（复用 #124 纪律语言，不新声称 formal） |
| P3-f+ | Map tip 更新 + transfer 效果观察 |
| P3-h / E4 | MiniAMM 应用门；真实 asset movement 另册 |

Mollusk 失败不得用「CI 绿」掩盖；也不得把 Mollusk 绿写成 Stage-0/hermetic。

### 6.3 明确不测（P3）

- formal Reference↔SBPF  
- mainnet deploy / upgrade authority  
- Token-2022 / 任意 remaining accounts  
- cross-host 可复现 / Tool Lock 扩面（除非触 assemble 工具版本——应避免）

---

## 7. 非目标

1. 删除 `solana-sbpf-plan-v1` / `solana-sbpf-elf-v1` shim（属 P4）。  
2. 默认 profile 切换到 cpi-elf（属 P4）。  
3. 打开 schedule/async、dynamic CPI、Token-2022、arbitrary invoke。  
4. 重写 ADR-0032 为 accepted 或宣称 formal D5/TASK。  
5. 清扫全部 preactivation `EmitCpi*Token|Ata|System|Pda|Unsigned|Preflight` 历史 lane。  
6. 一次 PR 合并 P3-a…P3-h。  
7. 在 single-account shim 上开放 `context.caller`。  
8. 把 hybrid marker 当作长期「第三 schema」产品化。  
9. 修改 active profile/catalog **silent** digest（若 revision，必须 versioned 原子更新 + 文档/SBOM 主代理串行）。  
10. 本设计文档之外的代码/runtime-tests/Tests 实现（Lane C 边界）。

---

## 8. 下一主 PR checklist

面向 **第一个代码 PR**（建议范围 = **P3-b + P3-c 最小竖切**，或更窄的 P3-a 诊断 + P3-b 帧模块 only）：

### 8.1 合并前必须

- [ ] 读本设计 + ownership；确认无跨 lane 文件  
- [ ] 新 API 仅 private / capability 内部；**无** public Semantic→files bypass  
- [ ] 零 CPI + MiniAmm 类 pin：**字节或契约** 不回退（允许 irDigest 从 marker 升为真 IR，但需同 PR 更新 pin 期望）  
- [ ] 有 CPI + 窄 body（TipJar 类）：不回归  
- [ ] `hasSites ∧ needsFullBody`：不再 silent 进 escrow 后含糊 FC（显式不支持 **或** 合成成功）  
- [ ] Finalize 仍 sole `buildFromCapability` 重算 base  
- [ ] `just dev-check` 与 ordinary `just ci` 绿  
- [ ] 触 `ProofForgeV2/**` 时 `just sbom-package-files-refresh`  
- [ ] 文档：仅当行为变化时由主代理更新 `02-solana` / backlog 一行——**不** 改 ADR-0032 阶段表 unless 完成信号真达  
- [ ] 成熟度措辞：engineering only；无 formal/mainnet  

### 8.2 第一个实现 PR 的建议最小范围（推荐）

**PR-P3-1（推荐）**

1. 新增 private `ProductFrameV1`（或等价）预算类型与 pure 检查。  
2. 新增 `ProductSynthesizeV1` skeleton：  
   - 输入：`SolanaCpiProductPlanV1` + full-body `IR`（零 sites 路径先接通）  
   - 输出：与 `SolanaCpiProductAssemblyV1` 兼容的 text/frameBytes  
3. `buildFromCapability`：零 sites ∧ needsFullBody 改为走 synthesize（目标：`cpi-ir` 真 schema，去掉 marker）  
4. 更新 `MiniAmmSolanaV1` pin 期望（若 IR 文本变化）  
5. **不含** site hooks / Map+CPI demo / Mollusk  

**PR-P3-2**

- Site hooks + `BodyCpiIfPay`（或等价）Lean product pin  
- Finalize 去掉 `full-body-hybrid` 特例（若 PR-P3-1 已使 productIr 常成功）

**PR-P3-3**

- Map + site demo + 可选 Mollusk host-optional  

### 8.3 完成 P3（整期）的定义（对照 ADR-0032）

- [ ] 同 profile 下 full body + 可选 CPI sites **同一** product ELF  
- [ ] CPI preflight/invoke 前缀/recipes 保留 catalog 纪律  
- [ ] 顶层双路径 dispatch 删除或退化为合成器内部策略  
- [ ] Finalize/bindings/inspect exact 可重算  
- [ ] MiniAmm（零 site）+ 至少一有 site full-body demo 钉测  
- [ ] **仍不** 声称 E4 MiniAMM token 镜像 / formal / 默认 profile 切换（P4）

---

## 9. 参考（只读）

- ADR-0032 `docs/adr/0032-solana-unified-materializer.md`  
- ADR-0028 / ADR-0031（账户、caller）  
- `ProofForgeV2/Targets/Solana/EmitSbpfAsmV1.lean`（`buildFromCapability` ~2309–2343，hybrid ~2261–2308）  
- `ProofForgeV2/Targets/Solana/CpiProductV1.lean`  
- `ProofForgeV2/Targets/Solana/CpiEscrowIRV1.lean`（`requireStraightLineCallable`，`CpiEscrowBodyOpV1`）  
- `ProofForgeV2/Targets/Solana/EmitCpiEscrowSbpfV1.lean`（`emitCpiProductSbpfV1`）  
- `ProofForgeV2/Targets/Solana/LowerSemanticV1.lean`（`materializeFullBodyPlanForProductV1`）  
- `ProofForgeV2/Targets/Solana/FinalizeV1.lean`（`finalizeCpiElfProfile`）  
- `Examples/MiniAmm.lean`，`Examples/TipJar.lean`，`Examples/TokenJar.lean`，`Examples/TransferSol.lean`  

---

## 10. 修订记录

| 日期 | 说明 |
|---|---|
| 2026-08-06 | Lane C 初稿：基于 tip `19f148a19` P2 hybrid + escrow product 代码事实 |
