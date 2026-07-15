---
id: PHASE-6
title: 实现日志
status: draft
owner: engineering
updated: 2026-07-15
normative: false
---

# Phase 6：实现日志

已进入 pre-acceptance alpha 实现阶段。本文件只追加实际完成的工作；这些结果验证架构
可行性，不会越过仍为 `proposed` 的规范或自动关闭正式 Phase 1 任务。

## 2026-07-15 — TASK-A0-01 / TASK-A0-02

- Commit/worktree：父仓库 `26d2a8dd33b76201eb7062e3a86fbf87641697cd` 上的未提交
  `new_design/` 独立目录；没有父源码 import 或运行时 fallback。
- Spec/Test：`SPEC-LANG-001`、`SPEC-SEM-001`、`SPEC-MAT-001`；
  `TST-SRC-003`、`TST-SEM-002/003`、`TST-MAT-001`。
- Changed：建立独立 Lean/Lake package、`program ... where` command DSL、目标中立 Program、
  requirement inference、参考解释器、associated `Materializer.Plan/TargetIR` 与稳定错误码。
- Commands：`lake build ProofForgeV2 proof_forge_next`；
  `lake build proof_forge_next_tests && .lake/build/bin/proof-forge-next-tests`。
- Results：均 exit 0；测试覆盖 init、increment、overflow、无源码 kind、需求推导、四目标
  materialization、Noir sync-call 拒绝和 private witness 不泄漏到 EVM。
- Evidence：`EV-20260715-0001`、`EV-20260715-0002`。
- Limitations：grammar 仍是 Counter/PrivateSum4 所需最小子集；尚无完整 name/type/effect、
  span/NodeId、循环/结构体/事件/扩展 elaboration。
- Next：正式接受规格后扩展 D1/D2，不把 alpha subset 标为完整 frontend。

## 2026-07-15 — TASK-A0-03

- Spec/Test：`SPEC-OUT-001`、四个 target dossier；`TST-EVM-003/004/005`、
  `TST-NEAR-003/004`、`TST-SOL-003`、`TST-NOIR-003`。
- Changed：同一 Counter 生成 EVM Yul/ABI/bytecode、Solana assembly plan/IDL、NEAR
  host-import WAT/Wasm、Noir source/Prover input；manifest 绑定同一 semantic hash。
- Commands：`just target-smoke`；`bash scripts/smoke_evm.sh`。
- Results：artifact validation exit 0；EVM 在 Anvil 验证 initial=7、increment=12，max+1
  revert 后状态仍为 max；NEAR `wat2wasm` 通过。
- Evidence：`EV-20260715-0003`、`EV-20260715-0004`。
- Limitations：Solana `.s` 是 plan-level assembly，尚非语义完整 ELF；NEAR 未跑 sandbox；
  Noir 未安装 Nargo/BB，故没有 ACIR、proof、VK 或 verify，二者 manifest 保持 non-deployable。
- Next：先补 sBPF ELF/runtime 与 Nargo/BB exact profile，再提升对应 maturity。

## 2026-07-15 — TASK-A0-04

- Spec/Test：`SPEC-REPRO-001`、`TST-ISO-002/003`。
- Changed：加入 docs checker、负语法 gate、四目标 artifact validator 与 archive-style
  isolation harness。
- Command：`just isolated-check`。
- Results：临时目录从归档源码重建 45 jobs，测试、文档检查和父 `ProofForge` import/
  symlink 扫描全部 exit 0。
- Evidence：`EV-20260715-0005`。
- Limitations：脚本没有创建新 HOME/Lake cache，没有把 PATH 限制为锁定工具 shims，也没有
  证明父 Git root 不可发现；因此这只是 archive isolation smoke，不是 `SPEC-REPRO-001`
  定义的完整 clean-room gate。当前还是 dirty development evidence；release evidence 必须
  在提交后重新生成。
- Next：完成正式评审后在候选 commit 重跑并记录 artifact digest。

## 2026-07-15 — TASK-A0-05

- Commit：`6d1d0b5a334e2575e140e1be28392da2710c013c`。
- Changed：CLI source loader 改为 Lean Parser 加 DSL command 白名单，不 elaboration 用户
  module；command elaborator 与 loader 共用 syntax decoder。编译边界拆成独立
  `Source.Program → Typed.Program → Semantic.Program`，target materializer 只接收后者；
  SourceHash 与 SemanticHash 分离。外部工具按 lock 校验版本与 executable SHA-256，输出
  先写 sibling staging，已有 destination 默认 `PF-OUTPUT-COLLISION`，不再覆盖用户目录。
- Commands：`just check`；`just evm-runtime`；`just reproducibility`；
  `just isolated-check`；`git diff --cached --check`（暂存后执行）。
- Results：完整 alpha gate exit 0；Lean parser/typed/semantic/target/negative/path tests 通过；
  EVM Anvil 验证 nonpayable、7+5=12 与 max+1 回滚；四目标两次构建共 19 文件逐字节一致；
  archive isolation smoke 在临时目录重建 61 jobs 并运行测试/docs-check。独立复核发现的
  existing-output/source-directory 数据丢失风险已修复，并由回归测试确认原文件保持不变。
- Evidence：`EV-20260715-0006`、`EV-20260715-0007`。
- Limitations：当前仍是 Counter/PrivateSum4 alpha 子集；完整 span/NodeId、effect/bound/
  disclosure 系统及正式 hermetic clean-room gate 均未完成；Solana 仍无 ELF/runtime、NEAR
  仍无 sandbox receipt、Noir 仍无 ACIR/prove/verify。
- Next：先完成 `TASK-D0-04` hermetic clean-room gate，再继续正式 D1/D2；不能以本条提升
  目标 maturity。

## 2026-07-15 — TASK-A0-06

- Commit/input：clean-room 输入为已提交树
  `e3b16063a97964d1da1958c5bfc2a6ed075206d5:new_design`；归档 SHA-256 为
  `c3bbb8dbf1d888eb6ce9446e865e7a02e2df47fbc70f407030f1786246c00bdc`。
- Spec/Test：`SPEC-REPRO-001`、`TST-ISO-002`、`TST-EVM-005`。
- Changed：`verify_isolation.sh` 只归档已提交 V2 子树，拒绝 symlink/submodule、父路径和
  父 `ProofForge` import；在随机 HOME/cache/tool/output 下以 `env -i` 运行，Core sandbox
  禁止全部网络，EVM sandbox 仅允许 localhost；复制并校验 Lean/Lake 与外部工具可执行文件，
  clean build/test 后验证四目标制品、19 个文件逐字节复现及 Anvil Counter runtime。
- Command：`just v2-clean-room-alpha`。
- Results：Darwin arm64 上 exit 0；61-job clean build、测试、docs-check、四目标 artifact
  validator 和两轮 reproducibility 通过；sandbox probe 证明 Core 无 localhost，EVM profile
  允许 localhost 且拒绝非本地地址；EVM 验证 nonpayable、7+5=12 与 max+1 回滚。
- Evidence：`EV-20260715-0008`。
- Limitations：这是 network-denied clean-room alpha，不是正式 hermetic gate。复制的
  `/opt/homebrew/bin/solc` 与 `wat2wasm` 仍从宿主加载未锁定 dylib；Lean toolchain closure
  不是内容寻址发布归档；`/usr/bin/python3`、Git、tar、shasum、`sandbox-exec` 等 harness
  runtime 也未锁定。未生成 schema-complete `EV-ISO-*` JSON，且只验证 Darwin arm64。
- Next：完成 `TASK-D0-03` 的完整工具/运行时 closure 锁定后解除 `TASK-D0-04` blocker；
  在此之前不得把 alpha 改称 hermetic 或 release evidence。

## 2026-07-15 — TASK-A0-07 / TASK-D0-03 external closure slice

- Changed：增加 `proof-forge.toolchains.v2` 与 `proof-forge.host-profiles.v1`；冻结 Lean、
  official solc、official WABT、OpenSSL bottle dependency 与 official Foundry archive 的
  URL/size/archive SHA/member/file SHA。`toolchain_assets.py` 实现严格 schema、自测、独立
  network provision、content-addressed private snapshot、安全 member extraction、原子 external
  bundle、Mach-O 静态图和 `DYLD_PRINT_LIBRARIES` 实际闭包验证。Compiler 在每次 managed spawn
  前验证 exact bundle tree、file size/hash/mode/link count 与目录权限，只通过 hash-locked
  `/usr/bin/env -i` 注入固定 allowlist。clean-room 外层改用 OpenSSL KAT、显式 Git/Python
  环境净化、锁定 external bundle，并从 committed archive 复制 runner；sandbox 拒绝
  `/opt/homebrew`。
- Commands：`just toolchains-validate`；`python3 scripts/toolchain_assets.py provision --group
  external`；`materialize-external`；`verify-external`；`just toolchains-closure-negative`；
  `just toolchains-environment-negative`；`just toolchains-root-negative`；`just target-smoke`；
  `just evm-runtime`。
- Results：全部 exit 0；五个 bundle file hash/mode 与 archive member 一致；official solc
  仅加载 Apple system dylib；WABT 实际从 bundle 加载 `lib/libcrypto.3.dylib`；Anvil/Cast
  official archive 运行 Counter nonpayable、7+5=12 与 max+1 rollback。篡改 libcrypto 后
  verifier 与 compiler 均按预期失败；用户注入错误 `DYLD_LIBRARY_PATH` 不影响锁定 WABT
  resolution。world-writable root、root/child symlink、extra node 与 hardlink 均 fail closed。
- Review repair：独立审查复现 `DYLD_IMAGE_SUFFIX=_debug` 可令有限 denylist 选择未锁库；工具
  子进程现改为 hash-locked `/usr/bin/env -i` + `inheritEnv=false`；在带该父环境变量运行的
  self-test 中，child environment 逐字等于单项 allowlist，另以同目录 `_debug` dylib 证明
  exact tree 会先拒绝未锁候选。
- Evidence：`EV-20260715-0009`。
- Limitations：`TASK-D0-03` 仍为 in_progress。Lean archive 已记录但尚未从 770 MB official
  ZIP 在 gate 中物化；当前 host profile 因 APFS root `Sealed: Broken` 为
  `eligibleForHermetic=false`，且目前只是局部 system-tool hash 检查、尚非完整 Stage-0
  attestation；sandbox 仍是 allow-default 加 deny 列表；同 UID 主动 race 与不可变 EV JSON
  尚未闭合。
- Next：官方 Lean ZIP 离线物化/closure → host Stage-0/profile 判定 → deny-default sandbox 与
  schema evidence；完成前不解除 `TASK-D0-04` blocker。

## 2026-07-15 — TASK-D0-03 Lean cache consumer preparation

- Commit/evidence：实现 commit `0b0aebda8b020d083b8fca37626ae9646fd643c8`；post-commit
  clean-room archive SHA-256 `05b5bda6e83b4bbf53856e65a3b4a9df6c0b9ebc76c803099f94156e9cf2115c`。
- Changed：`verify_isolation.sh` 删除 elan lookup/tree copy，改由 committed archive 内的
  `toolchain_assets.py materialize-lean` 从显式 content-addressed cache 离线生成临时 Lean
  root；同一 cache 继续物化 external root。增加独立的 Lean provision/materialize recipes；
  Lean 默认 materialize root 与 external exact bundle root 分离；clean-room 退出时只对私有
  临时 tool root 的只读目录恢复 owner 写权限，确保完整清除 2.6 GiB 工具树。
- Review repair：独立审查复现 user-site `.pth` 可在 toolchain validator 之前执行，并指出
  materialize 内的 version probe 尚在网络 sandbox 外。所有 toolchain/gate Python 调用现固定
  `/usr/bin/python3 -I -S`，validator 拒绝 site-enabled interpreter，并加入真实 `.pth` 注入
  负向 gate；clean-room materialize 及其子进程改由 `env -i` + no-network sandbox 执行。
- Commands：`/bin/bash -n scripts/verify_isolation.sh`；`just toolchains-validate`；
  `/usr/bin/python3 -I -S scripts/toolchain_assets.py materialize-lean --destination
  build/lean-official-audit`；从该 root 以 `env -i` 执行 Lean/Lake version probe 与
  `lake --no-cache build ProofForgeV2.CLI.Toolchain`；`just python-isolation-negative`；
  `just check`；`just evm-runtime`；`just reproducibility`；`just docs-check`；
  `git diff --check`。
- Results：以上聚焦门禁全部 exit 0；schema/ZIP 负向 self-test 同时通过。官方 ZIP 精确匹配
  15,194 entries 与 2,761,381,330 unpacked file bytes；Lean/Lake 的静态可达内部 Mach-O
  closure 分别为 5/6 节点，且与实际 dyld 集合一致；V2 全套静态/负向 gate、EVM localhost
  runtime 和四目标 19-file reproducibility 均通过；临时 2.6 GiB root 已完整清除。
- Evidence：`EV-20260715-0010`；精确 commit 的 locked-cache archive clean-room 已通过，但
  仍是 development alpha，不关闭 `TST-ISO-003`。
- Limitations：当前 host 仍 `eligibleForHermetic=false`；
  allow-default sandbox、Stage-0 host attestation 与 schema EV 未闭合；`TASK-D0-03` 保持
  `in_progress`，`TASK-D0-04` 保持 blocked。
- Next：继续 host Stage-0/deny-default/schema evidence；完成前不解除 `TASK-D0-04` blocker。

## 2026-07-15 — TASK-A0-08 / TASK-D0-03 H0 Host Stage-0

- Commit/worktree：实现 commit `4c6756a4e83cd461520bcacc713a8b13a81cfe3b`；post-commit
  clean-room archive SHA-256 `2af10f30458bf98c261802632f1096b54ab015c767cec4f76dfa16d99bd0037b`。
- Spec/Test：`ADR-0013`、`SPEC-TOOL-001`、`SPEC-REPRO-001`、`TST-HOST-001`；同时澄清
  `TST-ISO-002` 是正式 hermetic harness，`TST-ISO-003` 是 D8 release aggregate。
- Changed：新增严格固定顺序的 `host-bootstrap.lock` 与
  `scripts/verify_host_stage0.sh`。调用者必须直接以 `env -i` +
  `/bin/bash --noprofile --norc` 启动；record 只用 Bash builtin 读取，不执行 `source`/`eval`。
  Bootstrap 绑定 launcher、Python verifier、tool/host locks、Apple env/bash/sleep/rm/openssl/
  codesign、direct Xcode Python/Git，并在启动锁定 Python 前完成 KAT、摘要与 Xcode
  deep/strict signature。Python verifier 拒绝 duplicate JSON key 和多 profile，逐项验证系统
  tool node/symlink target/resolved path/hardlink count/mode/hash/signature，观察 live OS、Rosetta、
  SIP、authenticated root、volume seal、Xcode identity/team/designated requirement/CDHash/build、
  direct tool version 与 allowed runtime roots；eligibility 由严格 policy 与 exact observation 推导。
- Review repair：独立审查指出 inherited Bash 可在脚本第一行前执行 `BASH_ENV`，因此 `just`
  明确降为 convenience wrapper，权威入口保留在调用者侧；又指出前置 OpenSSL/codesign 无
  timeout/output bound，现以独立 process group、wall/CPU/file limits 和残留 group reap 修复，
  Python runner 同样以新 session + `killpg` 收敛 timeout/overflow。Xcode pathname 祖先 symlink
  或非 canonical path 直接失败；eligible policy 的 arch/Rosetta/SIP/authenticated-root/seal/
  mutability 分项 self-test 与 dyld canonical-path 检查已补齐。
- Commands：权威 development Stage-0；同入口 `--require-eligible`；
  `just host-stage0-negative`；`just toolchains-validate`；`just check`；
  `just evm-runtime`；`just reproducibility`；
  `/bin/bash -n scripts/verify_host_stage0.sh scripts/verify_isolation.sh`；
  `/usr/bin/python3 -I -S scripts/docs_check.py`；`git diff --check`。
- Results：development exit 0 并输出 canonical JSON：macOS `26.4.1/25E253`、kernel `25.4.0`、
  native arm64、SIP/authenticated-root enabled、`systemVolumeSeal=broken`、Xcode `26.3/17C529`、
  `mutableByCurrentUser=true`、`eligibleForHermetic=false`。formal exit 1 且稳定
  `PF-HOST-INELIGIBLE`。host-lock mutation、bootstrap trailing field 与 `BASH_ENV` marker 均按
  预期失败/未执行；完整 V2 static/negative/build/test/四目标 gate exit 0；EVM localhost
  nonpayable/init/increment/overflow rollback 与四目标 19-file reproducibility 再次通过。
- Post-commit：`just v2-clean-room-alpha` 从上述 committed archive 重跑 Stage-0、锁定
  Lean/Lake/external 物化、61-job clean build/test、四目标 19-file reproducibility、sandbox
  policy probes 与 EVM localhost runtime，exit 0；临时 2.6 GiB tool root 已完整清理。
- Evidence：`EV-20260715-0011/0012`。这是 development attestation、预期 formal rejection 与
  committed development clean-room evidence，不是 eligible/hermetic evidence。
- Limitations：Stage-0 是 local、point-in-time attestation，不是 remote proof；`/usr/bin/env`、
  `/bin/bash` 及 bootstrap watchdog 工具属于 Apple platform 前置 TCB，KAT 不能独立建立信任。
  同一 checkout 内 launcher/record 不能自证外部真实性；candidate archive binding、同 UID/
  privileged TOCTOU、Xcode bundle 内部 current-user-writable-node 扫描、eligible host、
  deny-default sandbox 与 schema-complete immutable EV 均未闭合。当前 alpha isolation 外层仍先
  经过 inherited Bash，不能替代权威入口。
- Next：`TASK-D0-03/H1` 实现 candidate/archive binding、deny-default policy 与正式 evidence
  schema；当前 host 不得运行或声明正式 hermetic gate。`TASK-D0-03`、`TST-ISO-002/003`
  均保持 open。

## 2026-07-15 — TASK-D0-03 H1a candidate/archive binding

- Commit/candidate：实现 commit `7b143aa7e7043a4f93dab78fe168b5c518b15fa1`；subtree tree
  `0dc77113aa2e63d45a21ee99f971b0e23d351329`；稳定 archive SHA-256
  `5a18767ed0dcc8a5cd73d61675df020b625b3054fefe45b551b6df542fac821a`。
- Spec/Test：`SPEC-REPRO-001`、`TST-ISO-002`；新增 `just candidate-binding`，覆盖两次 tar
  byte equality、embedded commit、提取路径和 malformed commit/tree/archive anchors。
- Changed：archive 从不稳定的 `git archive "$commit:new_design" .` 改为已验证 direct Git
  对 commit object + `new_design` pathspec 归档；显式禁用 replace objects/optional locks，绑定
  external commit/tree/archive 三元组，并用 `git get-tar-commit-id` 复核 tar。pre/post 以
  porcelain-v2 NUL stream digest 复核 HEAD、subtree tree 与 status。continuation 现在必须显式
  `--development`；未实现 Stage-0 digest-bound handoff 前不暴露 formal 模式。
- Commands：`just candidate-binding`；`just docs-check`；`bash -n scripts/verify_isolation.sh`；
  `git diff --check`；`just check`；post-commit 以 checkout 外生成的上述三项 anchor 执行
  `scripts/verify_isolation.sh --development --candidate-commit ... --candidate-tree ...
  --candidate-archive-sha256 ...`。
- Results：全部 exit 0。post-commit gate 从精确 candidate 物化锁定 Lean/Lake/external root，
  61-job clean build/test、四目标 19-file reproducibility 与 EVM localhost runtime 均通过；
  candidate HEAD/tree/status 前后相同。
- Evidence：`EV-20260715-0013`，仅为 development candidate-binding evidence。旧 evidence
  使用 tree object 归档时的 SHA 受调用时刻 mtime 影响；历史记录保持不可变，不把旧值改写成
  可重算 anchor。
- Limitations：formal 必须从权威 Stage-0 直接 handoff 到 digest-bound continuation，external
  anchor 必须来自 checkout 外受保护元数据；same-UID/privileged TOCTOU 仍需受控 runner。
  当前 host ineligible，sandbox 仍 allow-default，schema-complete JSON EV 未接入，所以
  `TASK-D0-03` 保持 `in_progress`，`TASK-D0-04` 与 `TST-ISO-002/003` 保持 open。
- Next：H1b strict evidence core/finalizer，再实现 deny-default stage profiles 与负向 probes。

## 2026-07-15 — TASK-D0-03 H1b strict development evidence core

- Commit：`ac55da706c575f3d308e9bfa383797b89f05032c`；实现脚本 SHA-256
  `a16f16e80ab03f279fb3a2222f5c1e7d293005ad6a7157593abf64b04a6ebb7a`。
- Spec/Test：`TRACE-EV-001`、`MOD-TEST-001`、`TST-EVIDENCE-001` 的 pre-acceptance
  development slice；未关闭正式验收。
- Changed：新增标准库-only strict parser/validator、PF integer-only/ASCII-graphic-key JCS
  restricted profile、result/attempt/qualification 代数、candidate-archive claim binding 与
  domain-separated artifact-set digest。`verify-bundle` 以逐组件 `O_NOFOLLOW`、single-link、
  exact/casefold/inode alias rejection 和 1,024-file/64-MiB/256-MiB budgets 复核声明文件；
  development publisher 使用固定 `<root>/<gate>/<EV>.json`、不可覆盖 hard-link 发布与
  inode/exact-byte readback。formal publication 在 gate catalog 不存在时稳定 fail closed。
- Review repair：第一次独立攻击矩阵复现 formal 自声明、attempt/probe/log 矛盾、祖先 symlink、
  staging close→link replacement 和 schema/JCS 漂移；重写后第二轮又复现 input/artifact exact
  path 复用与 case-insensitive APFS alias。最终增加全局 claim namespace、observed inode 去重、
  I/O 预算、stable EIO 与 Python literal duplicate-key AST 自检；冻结哈希未发现 P0/P1。
- Commands：`just evidence-core`；`just docs-check`；`git diff --check`；`just check`；formal
  publish、missing bundle、artifact mutation、retry/timeout/signal、failed probe/observation/scan、
  candidate mismatch、path alias、symlink、TOCTOU、limit 与 injected EIO 独立负向矩阵。
- Results：全部 exit 0 或按预期稳定拒绝；完整 `just check` exit 0。`validate` 只输出
  `claims-not-verified`，`verify-bundle` 只输出 `gate-catalog-not-verified`；formal publish
  exit 2、`PF-EVIDENCE-FORMAL-UNVERIFIED` 且不生成文件。post-commit targeted gate 再次通过。
- Evidence：`EV-20260715-0014`，仅为 development evidence-core implementation evidence。
- Limitations：没有 gate catalog、freshness/clock authority、revocation store、private-data 实际
  scanner、remote attestation 或受控 formal workspace；同 UID/privileged actor 的剩余时序风险
  未消除。`TASK-D0-03`、`TST-EVIDENCE-001`、`TST-ISO-002/003` 保持 open。
- Next：H1c 验收 deny-default stage policy renderer，然后接入 clean-room continuation 与
  development finalizer；当前 ineligible host 仍不得产生 formal EV。

## 记录模板

```markdown
### YYYY-MM-DD — TASK-*

- Commit/worktree: `<sha>` / clean|dirty（列出 task-owned diff）
- Spec/Test: `SPEC-*`, `TST-*`
- Changed: 精确文件与行为
- Commands: 完整可复现命令
- Results: exit code、case 数和关键观测
- Evidence: `EV-*` 路径与 artifact hashes
- Limitations: 未验证工具/网络/安全边界
- Next: 下一项唯一任务
```

禁止用“看起来正常”“应该通过”代替命令结果；失败和回退尝试也应记录。
