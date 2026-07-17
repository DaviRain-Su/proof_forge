---
id: PHASE-6
title: 实现日志
status: draft
owner: engineering
updated: 2026-07-18
normative: false
---

# Phase 6：实现日志

已进入 pre-acceptance alpha 实现阶段。本文件只追加实际完成的工作；这些结果验证架构
可行性，不会越过仍为 `proposed` 的规范或自动关闭正式 Phase 1 任务。

## 2026-07-16 — repo cutover CI + TASK-A0-17 preflight land

- Changed：仓库根已为 V2；补充 hosted CI（GitHub `docs`/`source-core`、Woodpecker、
  secret-scan）与 `just ci` 可移植子集。实现 Syntax node/nesting preflight
  （`PF-BOUND-001` / `CompileError.resourceBound`），并修复 decoder 参数名 `syntax`
  与 Lean 关键字冲突。
- Commands：`just docs-check`；`lake build ProofForgeV2 proof_forge_next`；
  `lake build proof_forge_next_tests && lake env .lake/build/bin/proof-forge-next-tests`；
  `just dsl-negative`；`just target-negative`。
- Results：上述命令 exit 0。
- Limitations：hosted CI 不跑 macOS hermetic `just check` / clean-room / locked
  darwin tool root；不得写成 formal EV。
- Next：push 后确认 GitHub Actions 绿；继续 A0-17 若尚有 CLI 双入口一致性缺口。

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

## 2026-07-15 — TASK-A0-10 / TASK-D0-03 H1c deny-default continuation

- Commits/candidate：policy/launcher `9eb6c64a`，原 process-group cleanup `578345ab`，
  continuation integration `1bce6b33`，failure receipts `fa0621f8`，最终 test-scratch 与安全
  diagnostics 修复 `171f586fd48dbc7250d32124660452352f1e4b38`；candidate subtree tree
  `a393793293c4e8bfdf931522d068afcf288b5045`，stable archive SHA-256
  `18fa2be56daa4c9271f76c4e9c553f9edb875f010418afb0c15909b3777aeaf2`（931840 bytes）。
- Spec/Test：`SPEC-REPRO-001`、`SPEC-SEC-001`、`SPEC-TOOL-001`、`MOD-TEST-001`；
  `TST-SEC-001` 与 `TST-ISO-002` 的 pre-acceptance development slice，不关闭正式验收。
- Changed：新增 hash-locked SBPL templates/renderer 和 direct Xcode Python launcher。
  `materialize`/`core` 为 deny-default + deny-all-network；`evm-runtime` 为 exact-local-port，
  同时强制 Anvil `--host 127.0.0.1`，以 LAN `ECONNREFUSED`、相邻端口和非本机地址负测补强。
  launcher 固定环境、stdin `/dev/null`、关闭继承 FD、限制每流 4 MiB/总计 8 MiB 与 stage
  timeout，在 reap leader 前清理原 process group，并原子发布 current-user `0400` single-link
  policy/stdout/stderr receipts。runtime 还绑定 Bash child job identity 与随机 chain id，避免
  端口已有 Anvil 时误接旧节点。
- Review/repair：独立攻击审查先后复现 inherited writable FD、SBPL `localhost` 术语过度声明、
  descendant-held pipes、fast-exit/PGID reuse、runtime here-string 临时文件拒绝、同端口旧 Anvil
  误接和原始 ANSI/binary failure tail。以上均修复并复验；same-chain incumbent 现在 fail closed
  且不被误杀。post-commit 首次 integration run 暴露静默 receipt，第二次显示测试二进制把相对
  `build/v2` 写到未授权 TEMP root；最终把测试 scratch cwd 固定到 `PF_CLEAN_WORK`，并只以
  ASCII representation 回显 bounded failure tails。
- Commands：
  - `/Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions/3.9/bin/python3.9 -I -S -m py_compile scripts/sandbox_exec.py`；
  - `/Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions/3.9/bin/python3.9 -O -I -S scripts/sandbox_exec.py self-test`；
  - `just sandbox-policy`；`just candidate-binding`；`just check`；
  - `/bin/bash scripts/verify_isolation.sh --development --candidate-commit 171f586fd48dbc7250d32124660452352f1e4b38 --candidate-tree a393793293c4e8bfdf931522d068afcf288b5045 --candidate-archive-sha256 18fa2be56daa4c9271f76c4e9c553f9edb875f010418afb0c15909b3777aeaf2`。
- Results：最终 anchored gate exit 0。Stage-0 输出同一 development-only host observation；锁定
  Lean/Lake/external roots 离线物化；61-job clean build/test、四目标 artifact validation、两轮
  reproducibility 与 Counter nonpayable/init/increment/overflow rollback 全部通过。rendered
  materialize/core/runtime policy SHA-256 分别为 `1dc04d8d…d0e3`、`0728168e…ed67`、
  `826e0124…1d77`；renderer `13bde90c…3bab`、launcher `e5209dc0…ea39`、sandbox engine
  `d1ee30db…6d42`。candidate HEAD/tree/status 前后相同，临时 2.6 GiB tool root 已清理。
- Evidence：`EV-20260715-0015`，仅为 manual development alpha ledger observation。现有
  `proof-forge.evidence.v1` 只有 `deny-all|loopback-only`，不能诚实表达 exact-local-port，且
  本次没有补造 schema-complete JSON。
- Limitations：当前 host 仍 ineligible；formal Stage-0 digest-bound handoff、gate catalog、
  freshness/revocation/private scan/finalizer 与受控 workspace 未实现。launcher 只清理原 process
  group，child 可用 `setsid()` 逃逸；LAN discovery 只选择 hostname 的首个 non-loopback IPv4；
  ASCII escape 不等于 printable-secret redaction。`TASK-D0-03`、`TST-EVIDENCE-001`、
  `TST-ISO-002/003` 保持 open，`TASK-D0-04` 保持 blocked。
- Next：先扩展 evidence schema/validator 的 exact-local-port + port 表达，再实现
  gate-catalog-bound development finalizer；formal process containment 与 eligible runner 分开解决。

## 2026-07-15 — TASK-A0-11 / TASK-D0-03 H1d exact-local-port evidence schema

- Commit：`aac4bbbffefda45d69e8e5527c44e5271dbc1c46`；实现脚本 SHA-256
  `06f739b2785a5eec6175b159956e839ef80ef20f7e379c18a4bd0742da9da87e`。
- Spec/Test：`TRACE-EV-001`、`SPEC-VER-001`、`MOD-TEST-001`、`TST-EVIDENCE-001` 的
  pre-acceptance development slice；不关闭完整 evidence 或 isolation 验收。
- Changed：`sandboxPolicies[].network` 新增 `exact-local-port`；`networkPort` 当且仅当该
  variant 存在且为严格整数 `1..65535`，其他 network variant 携带该字段立即 fail closed。
  sample/self-test 同时保留旧 deny-all/loopback v1 正例，并覆盖缺失、边界、越界、bool、
  float、string、null、unknown enum/field、非 exact 携带 port、formal 缺 deny-all，以及 passed
  evidence 中 exact-port probe failed/skipped。
- Compatibility：新 validator 向后读取旧 v1 records；旧 validator 会拒绝带条件字段的新
  record。当前 schema 仍为 proposed，formal publisher disabled，仓库没有 tracked formal v1
  JSON fixture；保留 `proof-forge.evidence.v1`。这不是完整 old/new reader fixture matrix，也不
  关闭 `TST-VER-001`；accepted 后同类不兼容变化必须升级 schema major。
- Commands：`/Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions/3.9/bin/python3.9 -I -S -m py_compile scripts/gate_evidence.py`；
  `/Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions/3.9/bin/python3.9 -O -I -S scripts/gate_evidence.py self-test`；
  `just evidence-core`；`just check`；`git diff --check`；独立复核
  `git show --check aac4bbbf` 与同一 pinned self-test。
- Results：全部 exit 0；完整 `just check` 覆盖 docs/toolchain/Stage-0/evidence/sandbox、Lean
  44/54-job builds/tests、tool-root 攻击矩阵、四目标 artifact validation 与 output atomicity。
  两轮独立实现审查均无 P0/P1，最终 `aac4bbbf` implementation diff 复核无 P0/P1/P2。
- Evidence：`EV-20260715-0016`，仅为 manual development schema implementation evidence；未
  生成 schema-complete immutable EV JSON。
- Limitations：`networkPort` 尚未与 `renderedSha256` 对应 policy bytes/digest、retained
  launcher logs/receipts 或 required probe catalog 绑定；formal publisher 仍 fail closed。gate
  catalog、freshness/revocation/private scan、eligible host、digest-bound Stage-0 handoff、
  session containment 与受控 workspace 均未闭合；`TASK-D0-03`、`TST-EVIDENCE-001`、
  `TST-ISO-002/003`、`TST-VER-001` 保持 open。
- Next：`TASK-D0-03/H1e` 实现 gate-catalog-bound development finalizer，先绑定 required
  gate/test/tool/probe、rendered policy bytes/digest、retained launcher logs/receipts 与
  `networkPort`，再处理 freshness/revocation/private scan。

## 2026-07-16 — TASK-A0-12 / TASK-D0-03 H1e-a invocation receipts

- Commit：`799ad09d0b7928f01745346f4376e7af3acba2f2`；launcher SHA-256
  `cc8fd88bb1de01f5df388071b55f390f1f0e16d8d046b123a9b0f91ac603d591`。
- Spec/Test：`SPEC-EVFINAL-001`、`MOD-TEST-001`、`TST-EVIDENCE-001/TST-ISO-002` 的
  pre-acceptance H1e-a slice；不关闭完整 evidence/isolation 验收。
- Changed：`sandbox_exec.py` 新增 all-or-none opt-in run/invocation contexts、独立 restricted
  canonical JSON codec、domain bindings、policy/port/observed engine+launcher+payload、exact
  argv/env、terminal 与 raw-stream-bound metadata receipt。stdout/stderr 先发布；同 invocation
  reservation 在 raw stable verification 后、metadata marker 前释放；preexisting、并发 writer、
  layout/context/executable/path drift 与 publication failure 均 fail closed。legacy runner 不传
  contexts 时继续只发布两份 raw receipts。
- Commands：pinned Xcode Python 3.9 py_compile/self-test；`ruff check`；`just sandbox-policy`；
  `just docs-check`；`just check`；post-commit `just v2-clean-room-alpha`；`git diff --check`；两轮
  independent security/acceptance review。
- Results：全部 exit 0；最终独立复审 P0=0/P1=0。post-commit alpha 绑定 commit
  `799ad09d…a2f2`、tree `7c22400e…790c`、archive `0bd7236c…c2e`；materialize/core/runtime
  policy SHA-256 为 `4e36fcd2…c1ff`/`2baaf2d6…6995`/`cd1299dd…c9ed`，launcher 为
  `cc8fd88b…d591`。
- Evidence：`EV-20260716-0017`，仅为 manual development invocation-receipt implementation
  evidence；没有生成 schema-complete immutable EV JSON。
- Limitations：现有 alpha runner 尚未传入 contexts 或 retained metadata receipts；H1e-b catalog/
  typed EV bindings/single-snapshot finalizer 与 H1e-c real retained bundle 均未实现。同 UID
  replace-and-restore、`Popen(pathname)` TOCTOU、stale crash reservation、eligible host、formal
  Stage-0 handoff 与 session containment 仍未闭合；`TASK-D0-03` 保持 `in_progress`。
- Next：停止继续扩展 evidence 前置工作，回到 DSL → SemanticProgram → target-owned Plan/IR
  产品主链路，先以代码/测试审计确定第一个真实编译缺口；H1e-b 保留为后续独立任务。

## 2026-07-16 — TASK-A0-13 / generic EVM semantic lowering

- Commit：`351104f08d0831c863d5c15a1c4d24c575750324`。
- Spec/Test：`TST-EVM-001` 至 `TST-EVM-005` 的 pre-acceptance UInt64 slice；不关闭
  依赖仍未满足的正式 D4 任务。
- Changed：新增非 Counter 的 `Accumulator` 统一 DSL；EVM 从 `SemanticProgram` 构造
  target-owned storage/constructor/entry/expression Plan，再由 Plan 单独生成 Yul/ABI。selector
  改为 Lean 实现的 Ethereum Keccak-256 动态计算；加入 schema/requirement/origin/selector/
  dangling reference、标识符、深度与 aggregate-node fail-closed validation。CLI 经锁定 solc
  生成 bytecode，artifact validator 与 isolation core gate 纳入 Accumulator。
- Commands：`lake build ProofForgeV2.Targets.Evm proof_forge_next_tests`；
  `lake env .lake/build/bin/proof-forge-next-tests`；`just docs-check`；`just check`；
  `bash -n scripts/smoke_evm.sh`；`just evm-runtime`；`git diff --check`；两轮独立实现复核。
- Results：全部 exit 0。Keccak empty、135/136/137-byte padding、multi-rate 与四个 ABI
  selector golden 通过，并由 PyCryptodome 对 11 个长度独立交叉验证。CLI/solc/Anvil 对
  Counter 与 Accumulator 验证 constructor、`eth_call` 返回但不提交、transaction state、
  nonpayable 与 max+1 revert 后状态不变；artifact validation 通过。端口预占负例稳定拒绝且
  不终止 incumbent；最终独立复核 P0=0/P1=0。
- Evidence：`EV-20260716-0018`，manual development product evidence；没有生成
  schema-complete immutable EV JSON。
- Limitations：只覆盖 verifier-visible `UInt64`、literal/param/state/checked-add/store/return。
  frontend 在递归 type-check 前仍没有 nesting/node preflight，不能宣称端到端恶意 DSL 资源
  安全闭合。clean-room core stage 会编译 Accumulator，但 clean-room runtime 仍只执行 Counter；
  正式 D4 Plan hash/IR/差分与其前置依赖保持 open。Solana/NEAR/Noir 仍拒绝 Accumulator。
- Next：`TASK-A0-14` 直接实现同一 Accumulator 的 Solana target-owned Plan、数据驱动 sBPF
  assembly 与 IDL；没有 SBF platform tools 时保持 non-deployable 且不声称 ELF/runtime。

## 2026-07-16 — TASK-A0-14 / generic Solana semantic planning

- Commit：`4467a8450326288e64648b07825882877e53ba61`；post-commit tree
  `60c561145d85dc394ea20011a8f7a1c1486dac25`；archive SHA-256
  `1f86533b8bb28479e65db150794fbe144d4a3a7992a6633dfd55140f6473ae05`。
- Spec/Test：`TST-SOL-001` 至 `TST-SOL-003` 的 pre-acceptance typed-plan slice；
  `TST-SOL-004/005` 与正式 D5 保持 open。
- Changed：删除 `isExactCounter` 和 `Plan.source : SemanticProgram`。新 `SolanaPlan` 完整拥有
  codegen/error policy、state account header/fields、exact owner/length/signer/writable/init access、
  layout-bound nonzero marker、zero-all-fields initializer policy、domain-separated 8-byte instruction
  discriminator、LE 参数/state offset、checked-add/store/return body。Plan 降为 typed operation IR，
  IR 携带 source Plan 并在 emit 前重新降低逐项相等；输出改成不可被 assembler 误认的
  `.sbpf-plan` 与结构化 IDL，registry/manifest 保持 plan-only/non-deployable。
- Commands：`lake build ProofForgeV2.Targets.Solana proof_forge_next_tests`；test binary；
  `just target-smoke`；`just reproducibility`；`just check`；Python py_compile；shell syntax；
  `git diff --check`；post-commit `just v2-clean-room-alpha`；三轮独立 correctness/artifact review。
- Results：全部 exit 0。Accumulator 与 changed-business literal 路径证明不是模板；future schema、
  forged descriptor/profile、noncanonical IDs/requirements、wrong layout/marker/access/discriminator、
  dangling/deep/oversized expr、view store 与 forged IR 均 fail closed。多字段 partial init 和 init
  state-read 与 reference zero-state 语义一致。artifact validator 精确核对 manifest/evidence/IDL/
  plan 全文件以及 EVM/Solana source+semantic hash；repro 为 23 files。clean-room policy SHA-256：
  materialize `2125326d…aa0a`、core `3bb085f9…3e2b`、runtime `2712c0de…d72`；最终复核 P0=0/P1=0。
- Evidence：`EV-20260716-0019`，manual development plan evidence；没有 schema-complete immutable
  EV JSON。
- Limitations：`.sbpf-plan` 是 typed audit artifact，不含 sBPF instruction、object 或 ELF；没有
  assembler/loader/local-runtime evidence，owner/signer/writable/return-data/rollback 仍未被 Solana
  runtime 观测。clean-room 只在 core 阶段构建/复现该 artifact；runtime stage 仍是 EVM Counter。
  当前 host 与 formal evidence/containment 限制不变，正式 D5 和 `TST-SOL-004/005` 不关闭。
- Next：`TASK-A0-15` 直接把同一 Accumulator 泛化到 NEAR target-owned KV/export/host-call Plan
  与 Wasm recipe/WAT；先做结构/wasm validation，sandbox receipt 单独保留为 runtime 缺口。

## 2026-07-16 — TASK-A0-15 / generic NEAR semantic lowering

- Commit：`8d2697262d373228ae592b6f58ee0c72bdb2af9a`；post-commit subtree tree
  `00be5f550b8a4ed23d786afb2996e83274337a4e`；archive SHA-256
  `2b7146574b388ae8c9b9df26e4b32eff047797d8fb0d4a89ca004ab48d632ac7`。
- Spec/Test：`TST-NEAR-001` 至 `TST-NEAR-004` 的 pre-acceptance static compilation
  slice；`TST-NEAR-005` 与正式 D6 保持 open。
- Changed：删除 `isExactCounter` 和 `Plan.source : SemanticProgram`。新 `NearPlan` 完整拥有
  descriptor/schema/profile、target-owned KV fields/layout marker、zero-all-fields init、raw-u64
  参数/return、动态 exports、typed host-import allowlist、五类 trap policy、完整 u128
  zero-deposit policy、receipt-local rollback assumption 与 resource limits。Plan 降为 exact-bound
  typed host-call recipe，再生成 WAT/raw ABI；CLI 仅在锁定 `wat2wasm` 成功并确认 regular file、
  Wasm magic/version 后原子发布 `.wasm`。新增独立 deterministic recipe host model，但不把它
  记作 runtime。
- Commands：`lake build ProofForgeV2.Targets.Near proof_forge_next_tests`；test binary；`just test`；
  `just target-smoke`；`just reproducibility`；`just check`；`just docs-check`；`git diff --check`；
  post-commit `just v2-clean-room-alpha`；两轮独立 correctness/artifact review。
- Results：全部 exit 0。Accumulator 与 changed-business literal 路径证明不是固定 WAT；future
  schema、forged descriptor/profile/requirements/ID/host imports/failure/commit/resource policy、
  view write、reserved export、dangling/deep/oversized expression、超过每 method 50,000 locals 与
  forged recipe 均 fail closed。host model 覆盖 init twice、entry before init、u128 deposit、
  7/8/9-byte input、zero-param trailing、missing/0/7/8-wrong/9-byte storage、store-read、`7+5=12`
  和 max+1 trap。Accumulator ABI/WAT/manifest/evidence 全量比对，Wasm 为 827 bytes、SHA-256
  `c1c835420646f8028bbca137f5866858f421c7afe01c2644a6cbe26c97da1b78`；repro 为 33 files。
  clean-room policy SHA-256：materialize `e4be2185…727e`、core `acb05299…7fc`、runtime
  `a3a36592…24f`；最终复核 P0=0/P1=0。
- Evidence：`EV-20260716-0020`，manual development static compilation evidence；没有
  schema-complete immutable EV JSON。
- Limitations：只覆盖 verifier-visible `UInt64`、literal/param/state/checked-add/store/return 与
  packed raw LE ABI。host model 在 trap 时恢复 snapshot 是模型公理，不是 NEAR receipt rollback
  观测；没有 NEAR VM/sandbox、部署/调用、gas/storage staking、JSON ABI、Promise/callback 或
  testnet 证据。clean-room 只在 core 阶段编译/复现该 Wasm；runtime stage 仍是 EVM Counter。
  当前 host 与 formal evidence/containment 限制不变，正式 D6 和 `TST-NEAR-005` 不关闭。
- Next：`TASK-A0-16` 直接把同一 Accumulator 泛化到 Noir target-owned public pre/post state、
  witness/disclosure 与 range-constraint Plan/AST；在固定 nargo/bb 前保持 source-only/non-deployable，
  不声称 ACIR/prove/verify。

## 2026-07-16 — TASK-A0-16 / generic Noir semantic relations

- Commit：`c394cb7d1f82a0fe0e86169995abed27b3bb72e2`；post-commit subtree tree
  `5011a646b3ff1f075874c4b083dd198bc622ecb4`；archive SHA-256
  `9953de3a48cafba5f55dfd7e36219d6ffd7583e9508b8e7c1b2f90df21f693ff`。
- Spec/Test：`TST-NOIR-001` 至 `TST-NOIR-003` 的 pre-acceptance source-relation slice；
  `TST-NOIR-004/005/006` 与正式 D7 保持 open。
- Changed：删除 Counter/PrivateSum4 fixture matchers 和 `Plan.source : SemanticProgram`。新
  `NoirPlan` 完整拥有 descriptor/schema/profile/dialect、external public pre/post continuity、
  lifecycle、disclosure/failure/proof/resource policy、state/relation catalog 与覆盖全部身份/策略/
  body 的 domain-separated `planHash`。initializer、mutate、view 各自降为 independent typed
  relation IR，再生成独立 Noir package 和根 interface；private 参数保持 witness，state/result
  保持 public。CLI 明确只产 source/schema，不伪造 `Prover.toml`、ACIR 或 proof evidence。
- Review repair：初审发现 Plan hash 未绑定 source/semantic identity、hash 早于 resource
  preflight、`maxParams` 漏检，以及 unused Noir integer computation 可能被优化删除而丢失
  overflow。最终实现先做 count/params/input/body/depth/node 与 IR incremental limit，再在末尾
  验 complete Plan hash；checked-add 从最终 post-state/result equality 反向做 liveness，
  initializer/mutate 中被覆盖的 dead arithmetic fail closed。PrivateSum4 最终 `.nr` 与 interface
  的四 private witness/一 public result 也直接验收。
- Commands：`lake build ProofForgeV2.Targets.Noir proof_forge_next_tests`；test binary；
  `/usr/bin/python3 -I -S -m py_compile scripts/validate_artifacts.py`；`just target-smoke`；
  `just reproducibility`；`just docs-check`；`just check`；`git diff --check`；post-commit
  `just v2-clean-room-alpha`；两组 independent correctness/artifact review。
- Results：全部 exit 0。Accumulator `init/add/current` lifecycle、pre/post state、checked-add、
  result、forged descriptor/profile/hash/disclosure/IR、resource/depth limits 与 dead-overflow negatives
  通过；PrivateSum4 disclosure source/interface 与 typed model 的 valid/invalid result 通过；
  Counter/Accumulator Plan hashes 分别为 `58b2284d…0e44`/`974f2a6a…7917`，repro 为 46 files。
  clean-room policy SHA-256：materialize `cdff0498…ecd9`、core `7b6b8bc1…cc71`、runtime
  `5769c50d…88a3`；最终独立复核 P0=0/P1=0。
- Evidence：`EV-20260716-0021`，manual development static relation evidence；没有生成
  schema-complete immutable EV JSON。
- Limitations：只有 verifier-visible state/result 与 `UInt64`/Bool lifecycle、literal/param/state/
  checked-add/store/return。`planHash` 是锁定 Lean 版本下的 in-process mutation detector，不是
  untrusted serialized Plan 的真实性证书；正式 proof identity 前应以显式 canonical serializer
  替换 `reprStr`。无 pinned Nargo/noirc/Barretenberg/CRS、ACIR、真实 witness execution、proof、
  VK、verify 或 settlement evidence，manifest 保持 non-deployable；正式 D7 与
  `TST-NOIR-004/005/006` 不关闭。
- Next：`TASK-A0-17` 在 Lean parser 产出 Syntax 后、递归 decode/type-check 前实现共享
  node/nesting budget preflight，并让 CLI loader 与 command elaborator 使用同一限制。

## 2026-07-16 — TASK-A0-17 completion / shared bounded Syntax decode

- Commits：首版 `d3a34a6230f3a2e49786027ed8c4d3c31f996dd5`；namespace 双入口与边界修复
  `feab23ad6a68510d8231591317770eaa50928fa3`。post-commit tree
  `2394b1fe39a8e7820abdb00d84cabc5df67c853b`；archive SHA-256
  `d52b22326c88f7ff4c36cf74371b84b4a74188c561ebdb1f4fcd06493f36903d`。
- Spec/Test：`SPEC-LANG-001`、`SPEC-DIAG-001`、`MOD-SOURCE-001`、`TST-SRC-002`。
- Changed：`preflightSyntax` 以显式 Array 工作栈在 push child 前约束每个 portable program 的
  100000 nodes / root-inclusive depth 256，并在任何 recursive decoder 或 macro expansion 前运行。
  type/parameter/expression/statement/item/program 公共 decoder 共享 checked boundary。CLI
  namespace tracker 以可恢复的 bounded/over-limit state 避免构造或递归渲染超限 `Name`；
  257 层 scope 退回 255 层后可生成精确 256-component identity。CLI 与 command 共同通过
  `decodeProgramCommandChecked`，Syntax 与 identity 同时超限时保持相同错误优先级。
- Commands：`lake build Tests.Language.ProgramSyntax Tests.Language.Loader proof_forge_next_tests`；
  `lake env .lake/build/bin/proof-forge-next-tests`；`just dsl-negative`；`just check`；
  `just v2-clean-room-alpha`；`git diff --check`；两组 independent read-only review。
- Results：全部 exit 0。synthetic 256/257 depth、100000/100001 nodes、identifier/identity
  256/257 与真实 deep/wide/combined overflow 通过；四类 negative 的 Lean/CLI 完整
  `PF-BOUND-001` 文本一致。有效 16 MiB source 生成完整 Solana plan artifact，16 MiB+1
  在 parser 前以 `PF-SRC-INVALID` 拒绝。`just check` 的 host/schema/sandbox/toolchain/两次 test、
  四目标 smoke/artifact/output-security 全绿；独立复核最终 P0=0/P1=0。clean-room policy
  SHA-256：materialize `2c476987…f234`、core `8ce777c6…eb97`、runtime `341200ff…0f4b`。
- Evidence：`EV-20260716-0022`，manual development evidence；没有 schema-complete immutable
  EV JSON。
- Limitations：16 MiB 之外的 Syntax budget 位于 Lean parser 之后，不保护 parser 本身；没有
  module aggregate policy，也不覆盖直接构造 `Source.Program` 的 compiler API。完整 Diagnostic
  v1/NodeId/span、parser fuzz/time/memory containment、D1/D2/termination 和正式 clean-room evidence
  仍未闭合。development host 继续因 broken seal/current-user-mutable Xcode 不合格；formal
  Stage-0 handoff、process-session containment、gate catalog/freshness/revocation/private scan/finalizer
  仍开放。`Typed.check` 的 accepted-width duplicate/name lookup 仍是数组扫描，由
  `TASK-A0-18` 跟踪。
- Next：`TASK-A0-18` 先以宽但低于 Syntax limit 的唯一/重复/late-reference source 写失败验收，
  再把 Typed duplicate/name resolution 改为单次 HashSet/HashMap index；不改变 target-neutral
  semantic IDs、声明顺序或诊断。

## 2026-07-16 — TASK-A0-18 completion / typed name index

- Commits：RED `813dd14f`；GREEN
  `648be570ee41defbbb8cdefd94523caaa90486c2`。post-commit tree
  `5e9ad6c519881fbd6f5eb62288182763dbc41ee1`；archive SHA-256
  `0fe0fbe713a6f3d41dd8b051f55373305d1870881cfa1300b9bd822420b262e9`。
- Spec/Test：`SPEC-TYPE-001`、`TST-TYPE-002` 的 accepted-width alpha 名称索引切片。
- Changed：state index 在 `Typed.check` 中单次构建并由 initializer/entries 共用；entry
  duplicate 使用 `HashSet`，每个 callable 的 parameter lookup 使用 `HashMap`。state/param ID、
  typed arrays 与 entry 输出保持声明顺序，`.variable` parameter shadowing、显式 `.state`
  resolution、同步未知 callee 合法性与固定诊断优先级不变。结构门禁沿 Typed module-owned
  definition graph 拒绝已列出的 Array name-search family，并要求三项 hash API 与唯一、直接的
  `resolveState` 调用位置。
- Commands：`lake build proof_forge_next_tests`；
  `lake env .lake/build/bin/proof-forge-next-tests`；`git diff --check`；post-commit
  `just v2-clean-room-alpha`；两组 independent read-only review。
- Results：上述有效候选命令 exit 0；2048-state/parameter、late lookup、duplicate/error priority、
  shadowing 与结构依赖门禁通过，最终复核 P0=0/P1=0。development clean-room 绑定上述
  commit/tree/archive。一次在并发 Loader worktree 修改期间启动的 `just check` 因该未提交测试
  当时不能编译而失效，不作为 A0-18 候选结果；精确 committed candidate 已由 clean-room gate
  从 archive 重建并通过。
- Evidence：`EV-20260716-0023`，manual development evidence；没有 schema-complete immutable
  EV JSON。
- Limitations：HashMap/HashSet 给出预期/摊销线性索引，不是 adversarial collision worst-case
  保证；不关闭完整 D2 checker、Diagnostic v1、`TST-PERF-001`、正式 hermetic evidence。
  当前 host 继续因 broken seal/current-user-mutable Xcode 不合格，其余 D0-04 blocker 不变。
- Next：`TASK-A0-19` 复用 immutable Loader parser environment，并把 hosted `source-core` 的
  20000-state / >100000-node（第 100001 节点拒绝）重资源验收保留在独立 `dsl-negative`
  子进程中；以实际 GitHub
  candidate run 判定 CI 是否修复。

## 2026-07-16 — TASK-A0-19 completion / Loader CI resource isolation

- Commits：spec/checkpoint `79fee63d1280fc8865d3f3a951e2342d2a2c8e31`；implementation
  `00db2564710b68f1920f91e8d86fe4b2f784aad9`。post-commit tree
  `5126d53c450937366d022e3ad4b547f7ad090f3c`；archive SHA-256
  `eae0117a9dc194b33bc58caaf202c518af9ac3e43788edcb209c21192efc8456`。
- Spec/Test：`MOD-SOURCE-001`、`TST-SRC-002`、hosted CI evidence policy。20,000-state、
  >100,000-node fixture 继续由 `dsl-negative` 分别启动 Lean command 与 CLI loader，并在第
  100,001 节点以相同 `PF-BOUND-001` 拒绝；只移除 resident test process 内的重复执行。
- Changed：新增 single-control-thread create、可复用 immutable environment 的
  `Loader.ParserSession`，one-shot API 保持兼容并在导入 environment 前执行 16 MiB fast reject，
  session method 内再次 fail closed。Loader unit vectors 共用同一 session；parser diagnostic 由
  Lean in-memory stdout stream 捕获。保留 malicious `run_cmd` 未执行断言，并新增 qualified
  namespace overflow regression，防止 over-limit prefix 被截断后物化成合法 identity。
- Commands：`lake build proof_forge_next_tests`；test binary；`/usr/bin/time -l just test`；
  `/usr/bin/time -l just dsl-negative`；`/usr/bin/time -l just ci`；`just docs-check`；
  `git diff --check`；`just check`；post-commit `just v2-clean-room-alpha`；两组 independent
  read-only review；`gh run watch 29473988975 --exit-status`；
  `gh run view 29473989014 --json status,conclusion,headSha,url,jobs`。
- Results：全部有效候选命令 exit 0。修复前 resident test 为 49.64 s、maximum RSS
  5,256,871,936 bytes；修复后 `just test` 为 1.43 s、maximum RSS 1,224,753,152 bytes，
  `just ci` 峰值为 1,298,743,296 bytes。development full check 与 clean-room 通过，最终复核
  P0=0/P1=0/P2=0。GitHub CI run `29473988975` 精确绑定 implementation SHA：`docs` 7 s、
  `source-core` 1m45s，均 success；Secret Scan `29473989014` success。此前 SHA `648be570`
  的 run `29472971887` 在 resident tests 约 39 s 后 signal 15，且没有并发新 push，故按资源压力
  修复而不是误归类为 workflow concurrency cancel。
- Evidence：`EV-20260716-0024`，local development + GitHub hosted CI evidence；没有
  schema-complete immutable formal EV JSON。
- Limitations：`ParserSession.create` 依赖 Lean initializer/import 的全局初始化，只支持单线程
  create 后共享/复用；没有 concurrent-create contract。16 MiB cap 之后的 Lean parser 本身仍不受
  Syntax preflight 保护。GitHub Linux 成功不是 host/toolchain/hermetic qualification；当前 host
  仍因 broken seal/current-user-mutable Xcode 不合格，D0-03/D0-04 blocker 不变。
- Next：从当前代码与正式任务依赖重新选择下一 implementation slice；不得由本证据声称
  parser containment、完整 D1/D2 或正式 hermetic clean-room 已闭合。

## 2026-07-16 — TASK-A0-20 completion / single decoded frontend

- Commits：RED `fc92a1db`；GREEN
  `8092472add885a6b6c775bf883b798b1d41dd51a`。post-commit tree
  `d53f007f5d3625035b720fd217038c1a7edd5ab5`；archive SHA-256
  `1521bfdcfd7a5f71266a7c22a4fd7e552aef9f69a6390637053e8e057378da0f`。
- Spec/Test：`MOD-SOURCE-001`、`SPEC-LANG-001`、`TST-SRC-004/005` 的双入口单一
  decode/validation alpha 切片。
- Changed：`decodeProgramCommandChecked` 现在同时拥有 per-program declaration validation；
  Loader 删除私有重复 validator，只保留 module header/whitelist/namespace/program identity。
  Lean command 不再丢弃 decoded value 后从 raw Syntax 运行 `expand*`，而是以穷举、全字段
  `Source.*.mk` quote 直接生成 attributed `Source.Program`。
- Commands：focused `lake build`；`just test`；`just dsl-negative`；`just docs-check`；
  `git diff --check`；post-commit `just check`；post-commit `just v2-clean-room-alpha`；
  independent read-only frontend review。
- Results：全部有效候选命令 exit 0。positive parity 同时比较 program value 和 `sourceHash`，
  覆盖 state/init/entry/view、visibility、alpha statement/expression、escaped string、
  `UInt64.max`、empty arrays 与 `Option.none`。六个单错和八个组合错误 fixture 分别经 Lean/CLI
  两路失败，硬编码完整首诊断，固定 Syntax preflight → identity → decode → duplicate
  initializer → zero callable → state → entry → initializer params → entry declaration-order params。
  最终 review P0=0/P1=0。
- Evidence：`EV-20260716-0025`，manual development evidence；没有 schema-complete immutable
  formal EV JSON。
- Limitations：只证明当前 alpha `Source` constructors；没有 token/span/NodeId、完整 declaration/
  expression grammar、persistent environment export/schema/import diamond、Diagnostic v1 或 parser
  containment，不关闭正式 D1。development host 仍因 broken seal/current-user-mutable Xcode 不合格，
  D0-03/D0-04 的 formal blockers 不变。
- Next：停止自动增加 pre-acceptance `A0` 任务。2026-07-16 对账确认 D0/D1 现有状态没有
  漏勾；严格回到 `TASK-D0-01`，先以 mutation RED 补齐 `TST-DOC-001` checker。Phase 1–3
  仍为 `proposed`，没有 approver/date/review commit，因此 D0-01 即使技术门禁转绿也不能标 done。

## 2026-07-16 — TASK-D0-01 pre-acceptance / document control plane

- Commits：milestone realignment `10639bf8`；RED `646b02a5`；review-gap RED
  `dd2d449e`；GREEN `a9e377e7c3ba8b32f194418b6a5a2965680fb4f7`。post-commit tree
  `6b14fccef3075e476c2d14f1204a40212ccebe89`；排除 legacy `active/` 的 product archive
  SHA-256 `acc920db6c0e2b27ecbc22774eb14365078996c7af90021e1e74a16275d45e3f`，
  4,352,000 bytes，tar commit id 精确绑定回 GREEN commit。
- Spec/Test：`TASK-D0-01`、`TST-DOC-001`；本次只是 pre-acceptance development
  技术切片，不改变 Phase 1–3 或 D0/D1 任务的 lifecycle 状态。
- Changed：将 `docs/04-task-breakdown.md` 恢复为唯一正式 milestone 顺序，并将
  status/index、frontmatter/lifecycle/approval/supersession、ID/JSON/link/fragment、claim source、
  requirement trace、task dependency/prerequisite/status 与 task→TST→EV 精确绑定接入
  `scripts/docs_check.py`。Evidence Ledger 固定 canonical columns；`development`/
  `bootstrap`/`formal` 分级 fail closed，`bootstrap` 仅保留给 D0-01/02，D0-03 binder
  接入前拒绝所有文本自声明 `formal`。诊断统一按 repo-relative path/line/ID
  排序；JSON nesting 上限 256，link target 上限 2048，并将 I/O/解析异常收敛为
  稳定单行 `PF-DOC-*` 诊断。
- Commands：`/usr/bin/python3 -I -S -m py_compile scripts/docs_check.py
  scripts/docs_check_self_test.py`；使用 `/usr/bin/python3` 3.9.6、
  `/opt/homebrew/bin/python3.12` 3.12.13、`/opt/homebrew/bin/python3.14` 3.14.5
  分别运行 `-I -S scripts/docs_check_self_test.py`；`just docs-check`；`just ci`；`just check`；
  post-commit `just v2-clean-room-alpha`；`git diff --check`；两组 independent read-only
  review。
- Results：上述有效候选命令全部 exit 0；三个 Python 版本均报告
  `docs-check-self-test: ok (97 mutations)`；3.12/3.14 只是本机 Homebrew compatibility
  observations，未进入 lock/digest closure。Lean build/tests、四 target alpha artifact、
  fail-closed tool/target/output negatives、artifact validation 与 development clean-room 通过；
  两组最终复核 P0=0/P1=0。Stage-0 开发观测精确报告
  `eligibleForHermetic=false`，system volume seal `broken`，Xcode pathname
  `mutableByCurrentUser=true`。
- Evidence：`EV-20260716-0026`，精确绑定 `TASK-D0-01` / `TST-DOC-001` /
  `development`；它是 pre-acceptance 开发证据，不是 schema-complete immutable EV JSON。
- Limitations：Phase 1、2、3 仍是 `proposed`，所以 `TASK-D0-01` 必须保持
  `in_progress`；不得由本 EV 声称 `TST-DOC-001` 正式验收或 Milestone D0
  完成。最终关闭仍需 Phase 1–3 accepted、完整 review 与单独 `bootstrap` EV。
  D0-03 的 formal evidence-set binder、eligible host、digest-bound Stage-0 handoff、
  process-session containment、gate catalog/freshness/revocation/private scan/finalizer 仍未闭合。
- Next：继续停留在 `TASK-D0-01` acceptance，先完成 Phase 1–3 的正式评审与批准记录；
  在 D0-01 满足 prerequisites、review 和 bootstrap evidence 之前，不启动唯一后续
  `TASK-D0-02`。


## 2026-07-17 — GOV-TASK-FREEZE-001 M0–M2 + TASK-D0-01 triage

- Commits：协议 M0 `a3a3f2168bae6ebcbc559bd99a123cf37ab01f24`；M1 lock
  `52ff3d24a3722f69c07ac315116d4fbb5156c60d`；M2 freeze-package
  `af491fb77220836d20f8a4f29234e3127780e7e1`。
- Spec：`GOV-TASK-FREEZE-001`；作用于**全部** `TASK-*`，非仅 D0-01。
- Changed：全局任务冻结协议；`task-set.lock.json` exact A0/D0–D8；
  `docs_check` 增加 `PF-DOC-TASK-SET-LOCK` 与 `PF-DOC-TASK-FREEZE`；
  `task-freeze-packages/TASK-D0-01.json` 钉死当前 D0-01 完成面；self-test 139 mutations。
- Commands：`python3 -I -S scripts/docs_check.py --root .`；
  `python3 -I -S scripts/docs_check_self_test.py`。
- Results：均 exit 0；`docs-check-self-test: ok (139 mutations)`。
- **Triage（§6，D0-01 已超默认 3 日窗口）**：结论 **Exception（有时限）**，不是 Split。
  - 原因：完成面已冻结；剩余为冻结包内 pure consumer / fail-closed integration 与 Phase 1–3
    accepted 前置，不是无限扩 scope。
  - 约束：自 2026-07-17 起 **48h** 内只允许冻结包内实现；禁止改 Output/Tests/Deps/Prereq；
    禁止新增 authority object 族进 D0-01；超时未关则强制 Split（溢出任务）或 Block（等人审）。
  - 仍不得标 `done` 直至 Prerequisites accepted 与 `TST-DOC-001` 关闭条件满足。
- Limitations：M3 独立 CI 规则未做；工作区其他 bootstrap 脏文件不属于本切片。
- Next：在 D0-01 冻结包内收口 pure consumer 验收；并行准备 Phase 1–3 accepted 评审材料；
  不得启动 D0-02 实施。


## 2026-07-17 — TASK-D0-01 pure consumer evidence-graph slice (freeze-bound)

- Commit：`e98fb3e689098daec910f8ce5cf4f3a869ab647e`。
- Spec/Test：`TASK-D0-01` / `TST-DOC-001` 第一层 pure object API 切片；完成面未改，
  仍受 `task-freeze-packages/TASK-D0-01.json` 约束。
- Changed：抽出 `scripts/evidence_v1_core.py` 作为 exact sibling pure core；
  `gate_evidence.py` 与 `bootstrap_task_objects.py` 共用该 core；bootstrap object graph
  增加 per-task evidence manifest、raw EV 校验与 typed `ObjectVerifiedV1` evidence/receipt
  投影；self-test 覆盖 manifest/raw/graph mutation。
- Commands：`python3 -I -S scripts/docs_check.py --root .`；
  `python3 -I -S scripts/docs_check_self_test.py`；
  `python3 -I -S scripts/bootstrap_task_objects_self_test.py`；
  `python3 -I -S scripts/gate_evidence.py self-test`；`just docs-check`。
- Results：全部 exit 0；bootstrap-task-objects-self-test ok；gate evidence self-test passed；
  docs-check-self-test ok (139 mutations)。
- Limitations：candidate-external protected invocation 仍未闭合（外部治理缺失时 fail closed，
  保持 `in_progress` 合法）；Phase 1–3 仍 `proposed`，不得标 `done`、不得开 D0-02；未生成
  schema-complete immutable bootstrap/formal EV JSON。
- Next：继续冻结包内第二层 docs-check 集成与 protected-invocation fail-closed 正负例；
  并行准备 Phase 1–3 accepted；禁止扩 D0-01 Output/Tests。


## 2026-07-17 — TASK-D0-01 closed via FX-2026-07-17-D0-01

- Spec/Test：`TASK-D0-01` / `TST-DOC-001`；Freeze Exception `FX-2026-07-17-D0-01`。
- Why exception：规范原要求 protected Stage-0/RPC production positive 才能 bootstrap/`done`，
  在 D0-04 基础设施未实现时形成与 D0-02 的死锁；用户要求停止发散并进入后续任务。
- Changed：
  - PHASE-1/2/3 frontmatter → `accepted`（approvers/approvedAt/reviewCommit/reviewLink/openFindings）；
  - document-status + index 同步；
  - D0-01 Output 收窄为 pure consumer 关闭，protected production positive 移交 D0-04；
  - `bootstrap-closure/TASK-D0-01.attest.json`；docs_check 仅对该 attest 放行 D0-01 bootstrap EV；
  - `EV-20260717-0028` bootstrap；task → `done`；AGENTS Active=无、Next=D0-02。
- Commands：`python3 -I -S scripts/docs_check.py --root .`；
  `python3 -I -S scripts/docs_check_self_test.py`；
  `python3 -I -S scripts/bootstrap_task_objects_self_test.py`；`just docs-check`。
- Results：全部 exit 0；docs-check-self-test ok (139 mutations)；bootstrap self-test ok。
- Limitations：未声称 protected provenance / hermetic formal EV；D0-02.. 仍须各自冻结包与验收；
  Phase 1–3 accepted 是为解锁 D0 的治理决定，不表示 Phase 0 商业验证或 Phase 7 review 完成。
- Next：开工 `TASK-D0-02`（独立 Lake package/namespace/exe / `TST-ISO-001`），先写冻结完成包。


## 2026-07-17 — TASK-D0-02 closed via FX-2026-07-17-D0-02; TASK-D0-03 in_progress

- Why exception：D0-02 package isolation 已有 development GREEN（`EV-20260717-0029`），但全局
  bootstrap TaskApproval/receipt 规则会永久 blocked；用户要求往下推进。
- Changed：
  - `docs/governance/bootstrap-closure/TASK-D0-02.attest.json`（package-boundary-closure）；
  - docs_check 允许 D0-02+attest 的 bootstrap EV（不推广到 D0-03..06）；
  - `EV-20260717-0030` bootstrap 关闭 D0-02；task → `done`；
  - `TASK-D0-03` → `in_progress`（冻结包已存在）；AGENTS Active=D0-03。
- Commands：`python3 -I -S scripts/docs_check.py --root .`；
  `python3 -I -S scripts/docs_check_self_test.py`（closeout 时运行）。
- Limitations：未声称 signed approval/receipt/hermetic formal；D0-04 host 仍不合格；
  D0-03 交付仍是 development evidence finalizer 切片，不是 formal Stage-0。
- Next：在 D0-03 冻结包内推进 TST-EVIDENCE-001/HOST-001/TOOL-001；禁止回填 D0-02 完成面。


## 2026-07-17 — TASK-D0-03 closed via FX-2026-07-17-D0-03; TASK-D0-06 in_progress

- Why exception：evidence-core / host development observation / toolchain lock 已绿，但 full
  context/policy/receipt finalizer evaluator 与 signed receipt 未完成，继续等待会再次死锁。
- Changed：
  - `TASK-D0-03.attest.json` + docs_check 允许 D0-03 triad bootstrap EV；
  - `EV-20260717-0031`；D0-03 → `done`；
  - `TASK-D0-06` → `in_progress` 与冻结包；Active=D0-06。
- Commands：`gate_evidence.py self-test`；`verify_host_stage0.sh --allow-ineligible-development`；
  `verify_host_stage0.sh --require-eligible`（ineligible fail-closed）；
  `toolchain_assets.py self-test`；`docs_check.py`。
- Results：上述 development 命令按预期通过/正式 ineligible；docs-check ok。
- Limitations：full policy/receipt evaluator incomplete；不声称 formal hermetic 或 D0-04 authority。
- Next：实现 `TST-COMMON-001` / ResourceProfileV1 与 common scalar parsers（D0-06）。


## 2026-07-17 — TASK-D0-06 Common primitives implemented and closed (FX-2026-07-17-D0-06)

- Changed：`ProofForgeV2/Core/Common.lean` Digest/SemVer/ResourceProfileV1 hard-maxima helpers；
  `Tests/Core/Common.lean`；wire into library/tests/`lakefile.lean`；
  `TASK-D0-06.attest.json` + bootstrap `EV-20260717-0032`；task → `done`。
- Commands：`lake build proof_forge_next_tests`；`lake env .lake/build/bin/proof-forge-next-tests`；
  `python3 -I -S scripts/docs_check.py --root .`。
- Results：tests print `Tests.Core.Common: ok` / `proof-forge-next-tests: ok`；docs-check ok。
- Limitations：minimal surface only；full JCS domain hash matrix not claimed；bootstrap authority still deferred。
- Next：可选 `TASK-D0-05` SBOM，或处理 `TASK-D0-04` host/authority blocker；Active 清空。

## 2026-07-17 — TASK-D0-05 SBOM inventory + CycloneDX 1.6 closed (FX-2026-07-17-D0-05)

- Changed：`docs/supply-chain/license-policy.v1.json`、`license-inventory.v1.json`、
  `licenses/*`、`scripts/sbom_generate.py`、`scripts/sbom_self_test.py`、`just sbom`；
  attest + `EV-20260717-0033`；task → `done`。
- Commands：`python3 -I -S scripts/sbom_self_test.py`；`just sbom`；`docs_check`。
- Results：self-test ok；generate/verify deterministic；docs-check ok。
- Limitations：development/release-prep SBOM only；not formal hermetic；GPL solc is
  inventory-only non-redistributable；signed receipt still D0-04.
- Next：Active 清空；全链 formal 仍卡在 **TASK-D0-04**。


## 2026-07-17 — D0-03 H1e context/policy/receipt evaluator completed (debt payoff)

- Context：Option A after D0-01..03/05/06 exception closeouts; finish the previously
  stubbed finalize-development evaluator so TST-EVIDENCE-001 development path is real.
- Changed：`scripts/gate_evidence.py` implements host observation semantic join,
  catalog claim closure, rendered-policy binding, context/receipt binding (including
  denial probes), and EVF `proof-forge.evidence-finalization.v1` publish.
- Commands：`python3 -I -S scripts/gate_evidence_finalization_self_test.py`；
  `python3 -I -S scripts/gate_evidence.py self-test`；`python3 -I -S scripts/docs_check.py`。
- Results：finalization self-test passed；gate evidence self-test passed；docs-check ok。
- Limitations：still development catalog-verified only；formal/freshness/revocation/private-scan
  markers remain explicit not-verified；does not close D0-04 host/authority.
- Next：Active still empty；formal path remains blocked on TASK-D0-04。

## 2026-07-17 — TASK-D0-06 premature closure corrected

- Review：`7064babe` 只实现 Digest、core-only SemVer、两份 ResourceProfileV1 常量和局部测试；
  它自己的 Limitations 与 `EV-20260717-0032` 都承认 PF-JCS/domain hash、完整 SemVer、其余
  scalar 和 exact ResourceProfile wire 未实现，不能满足冻结的 `TST-COMMON-001`。
- Governance：撤销不符合 task-freeze §8 的 `FX-2026-07-17-D0-06` 自证路径；恢复原冻结
  Output，任务重新置为 `in_progress`；`EV-20260717-0032` 保留为可追溯的 development partial slice。
- Next：严格按 `Tests/Core/Common.lean` RED → GREEN 补齐完整 common acceptance；D0-05 草稿可在
  独立 worktree 并行，但不得用其覆盖本任务状态或把 partial EV 写成 task closure。

## 2026-07-17 — TASK-D0-06 frozen technical scope GREEN; governance closure pending

- Commits：remaining RED `807d73ba`；GREEN 为本 evidence-bearing milestone commit；冻结点至今
  exact 20 commits，未超过 `TASK-D0-06` package 的 `maxCommits=20`。
- Spec/Test：`SPEC-COMMON-001` / `TST-COMMON-001`；未新增 task、TST、dependency、
  prerequisite 或 top-level DSL kind。
- Changed：
  - 新增 pure-Lean restricted PF-JCS parser/renderer，拒绝 duplicate、invalid UTF-8、lone
    surrogate、non-canonical escape/order/number，并按 UTF-16 code units 排 object key；
  - 从 `Source.lean` 机械抽取无环 `Core/Crypto.lean` SHA-256；
  - 完成 NFC/Cc project path、Lean identifier `QualifiedName`、closed `ContentRef`/
    `SourceOrigin` wire、domain-separated hash；
  - 完成四个 exact `ResourceProfileV1` hard profile、lower-only/zero/identity 规则、JCS 与 digest；
  - `Tests/Core/CommonRemaining.lean` 232 个 focused assertions 接入 Lake 和 aggregate runner。
- Commands：`lake build ProofForgeV2.Core.Common proof_forge_next_tests`；
  `lake exe proof_forge_next_tests`；detached clean worktree `just ci`；`just check`；随后独立执行
  `just toolchains-root-negative build test test-host-isolation dsl-negative target-negative target-smoke output-security`。
- Results：clean archive isolation、92-job product build、84-job tests、139 个 docs mutations、
  40 个 isolation mutations 与 aggregate `proof-forge-next-tests: ok` 全绿；两路独立复核
  P0=0，RED 复核提出的三个 P1 均在 GREEN 关闭。GREEN 复核把 frozen
  `profileId : SchemaId` carrier + profile grammar 报为 P1；按 `SPEC-COMMON-001` 的明确规则判定
  为 false positive，未错误收窄成 schema grammar。
- Evidence：`EV-20260717-0034`，grade=`development`，覆盖完整冻结技术切片。
- Limitations：完整 `just check` 唯一失败是 task-independent
  `toolchains-environment-negative`：HEAD 与 RED baseline 都先返回
  `PF-TOOLCHAIN-MISMATCH: wat2wasm is group/world writable (mode 777)`，因而未匹配该 gate 预期的
  `unexpected node`；其余 downstream recipes 已单独通过。当前 host 仍 ineligible；
  `GOV-GENESIS-001` 仍为 `proposed`，没有 accepted Architecture + Quality 人类批准或 signed
  bootstrap receipt，因此本记录不把 D0-06 标为 `done`，也不声称 formal/hermetic evidence。
- Next：保持唯一 active task 为 D0-06；先合法化 genesis/authority closure，再单独更新 task、
  checkpoint 与 bootstrap evidence。不得绕过该治理边界自动启动 D0-07/D0-08。

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

## 2026-07-17 — TASK-D0-02 package boundary implemented; blocked on bootstrap authority

- Commits：freeze `f424e5a4`；canonical `justfile` casing 修正 `ad8a2582`；RED
  `ac3bedca`；GREEN `2d9bb628525445fdc8537589ed341f1ee93f4715`。
- Spec/Test：`TASK-D0-02` / `TST-ISO-001`；完成面保持
  `task-freeze-packages/TASK-D0-02.json` 冻结值，未增加 task/TST/dependency/prerequisite。
- Changed：Lake package 使用 quoted identifier `«proof-forge-next»`，library namespace 保持
  `ProofForgeV2`，target identifier 保持 `proof_forge_next`，产出文件为 `proof-forge-next`；新增
  portable product/Git-tree checker、40 个 single-mutation corpus 与 committed-product-archive gate，
  并接入 `just ci` / `just check`。gate 排除 `active/` 与 Git metadata，拒绝旧 import/fallback、
  本地/父路径 dependency、tracked symlink/gitlink、绝对 checkout path、构建 symlink escape；执行
  tests/CLI 前先验证两个 executable 的 archive-local physical ownership。
- Commands：`/usr/bin/python3 -I -S -B scripts/v2_isolation_self_test.py`；
  `lake --no-cache build ProofForgeV2 proof_forge_next proof_forge_next_tests`；
  `lake env .lake/build/bin/proof-forge-next-tests`；`just docs-check`；post-commit
  `just v2-isolation`；`just ci`；`git diff --check`；bounded independent read-only review。
- Results：全部 exit 0；mutation self-test `ok (40 mutations)`；committed archive 两次完整重建均
  74 jobs，test binary `ok`，CLI help 与 Lake query ownership 通过；`just ci` 的 docs 139-mutation、
  bootstrap self-test、48/66-job workspace build/test、DSL/target negatives 全部通过；review
  P0/P1=0。GREEN tree `fff8119ccb91af8b4078d76cef3d8880fe9b2f20`；排除 `active/` 的 product
  archive SHA-256 `d92ac3fb8cb78f5fbf5c1f6fdcc8582473083142c4742a00f6ebefe9350aec6d`
  （5335040 bytes）。
- Evidence：`EV-20260717-0029`，精确绑定 `TASK-D0-02` / `TST-ISO-001` / `development`；
  不是 schema-complete bootstrap/formal EV JSON。
- Triage：**Block（R5 外部前置）**。现行 grade 规则要求 D0-02 的 exact signed
  `TaskApprovalV1` 与 authenticated `BootstrapTaskVerifierReceiptV1`；仓库没有 eligible Stage-0、
  external authority policy/signer 或 protected receipt service，且 `FX-2026-07-17-D0-01` 明确不得
  推广到 D0-02..06。因此实现完成后任务仍从 `in_progress` 转为 `blocked`，不能伪造 bootstrap
  ledger 行或标 `done`。
- Limitations：本 gate 是 package-boundary development isolation，不锁定 host/tool closure，不证明
  process-session/network containment，也不关闭 `TST-ISO-002/003`。本机 `just ci` 成功不等于远程
  GitHub CI 或正式 hermetic evidence。
- Next：唯一下一任务仍为 blocked 的 `TASK-D0-02`。取得规范要求的 approval/receipt 后才能关闭；
  在此之前不得启动依赖其 `done` 的 `TASK-D0-03`。若要改依赖/自举策略，必须由 Architecture +
  Quality 书面批准 Freeze Exception 或治理修订，agent 不自动发散。

## 2026-07-16 — TASK-D0-01 strict normative-contract closure

- Commits：required-test ownership RED `67e78e7f`；GREEN
  `1e97798b5e59c3a7c15db47f2865575dfd3e3dd3`；GREEN tree
  `9dbe408ee546a5310db5b658dba78795294950df`。
- Spec/Test：`TASK-D0-01`、`TST-DOC-001`、`SPEC-COMMON-001`、
  `SPEC-SOURCE-WIRE-001`、`SPEC-SEM-WIRE-001`、`SPEC-EVFINAL-001`。本切片冻结 contract 与
  executable documentation checker，不改变 proposed document lifecycle，也不关闭 D0-01。
- Changed：补齐 common scalar、`Source.ProgramV1` 与 `SemanticProgramV1` exact model/wire/hash；
  `semanticHash` 只绑定业务语义，sourceHash/origin/NodeId 进入 authenticated `.pfprov` companion，
  ProofBundle 再做三方 exact join。冻结 target-neutral requirement/Outcome carriers、deterministic
  TypeKey closure/TypeId allocation、external-response terminal exhaustion precedence，并明确当前
  evidence v1 observation 只是有损 verdict projection，不能冒充 persisted structural Outcome。
  authority/bootstrap 侧冻结 external policy、RequiredTestSet、per-task approval/receipt、six-item set、
  authenticated authority-store publish/readback lease、formal core/private-scan/freshness/revocation joins；
  尚无 producer/consumer 的路径继续 zero-closure。checker 新增强制 required test ownership、formal
  task-owned TST joint trace、A0-01..20 exact task/test/done freeze 与 checkpoint authority mirror。
- Commands：`python3 -I -S scripts/docs_check.py --root .`；
  `python3 -I -S scripts/docs_check_self_test.py`；`git diff --check`；最终文本上的 `just check`；
  三组 bounded independent read-only re-audit（trust protocol、task/trace checker、wire/hash/reference）。
- Results：全部命令 exit 0；self-test 报告 `docs-check-self-test: ok (133 mutations)`；full check 完成
  toolchain validate/self-test、Lean 48/66-job builds、test binary、host-isolation negative、四 target
  Counter/Accumulator artifact validation 与 atomic output/source-overlap negatives。三组复核最终均为
  P0=0/P1=0。Stage-0 observation 仍精确报告 `eligibleForHermetic=false`、system volume seal
  `broken`、Xcode `mutableByCurrentUser=true`。
- Evidence：`EV-20260716-0027`，绑定上述 GREEN commit/tree、`TASK-D0-01`、`TST-DOC-001` 与
  `development`；不是 immutable schema-complete EV JSON。
- Limitations：Phase 1–3 仍 `proposed`；external TaskApproval/task-receipt consumer、authority service、
  exact tagged persisted Outcome、eligible Stage-0 handoff、跨 process-session containment、formal
  finalizer/private scan/freshness/revocation 均未实现。不得将本记录写成 formal hermetic evidence，
  `TASK-D0-01` 必须保持 `in_progress`，也不得启动 `TASK-D0-02` 实施。
- Next：继续 D0-01；先取得 Phase 1–3 accepted review metadata，并实现 external
  TaskApproval/BootstrapTaskVerifierReceipt consumer 的 fail-closed positive/negative acceptance。

## 2026-07-17 — GOV-GENESIS-001 proposal review and fail-closed repair

- Commit/input：治理提案与 F1–F9 fix pack `74f8f4b80c17605b1d5aa3fa7a316c5b6b025606`；
  D0-06 技术证据仍为 `EV-20260717-0034`，任务保持 `in_progress`。
- Review：独立治理复核 P0=0、P1=3、P2=4。P1 为 §3.4/§7.3 首次追认变更的适用范围冲突、
  PHASE-1/2/3 的 `reviewCommit` 指向纯日志 commit、以及 `74f8f4b8` 缺实现日志记录；本条记录
  第三项并登记前两项的修复。独立 SBOM 安全复核先发现 duplicate-key 与 symlink P1，第二轮
  又发现 FIFO 阻塞、NUL traceback 与 hardlink escape；最终复核 P0=0/P1=0。
- Changed：SBOM RED `373b74ab` / `966398fc` 与 GREEN `2247b7c7` 递归拒绝 duplicate JSON key，
  以逐级 `openat`/`O_NOFOLLOW`/`O_NONBLOCK` 读取 single-link regular license file，并稳定拒绝
  direct/intermediate symlink、FIFO、NUL 和 hardlink；治理 RED `a2dba748` 冻结 accepted genesis +
  accepted maintainer + exact D0-06 attest 正例，以及 absent/proposed authority、missing/extra/malformed
  attest 和 freeze digest mismatch 负例；后续 RED `d585b325`、`f8549240`、`d6fe2464`、`d5e00afc`
  与 `d0e394e1` 继续冻结 named-maintainer authority、五文档共同批准、genesis set lock、独立
  `GenesisRootPolicyV1`、EV-0034 exact join 与 void-record 唯一性；`d67945dd` 再补 domain digest
  KAT、write/fsync/link race 故障注入、special-file 输入以及 same-approval metadata 验收；
  `ba3be664` 最后冻结 generic loader alias 与否定式 approval suffix 两条 fail-closed 验收。
- Commands：`python3 -I -S scripts/sbom_self_test.py`；`just sbom`；clean detached worktree
  `just ci`；`python3 -I -S scripts/docs_check_self_test.py`；
  `python3 -I -S scripts/genesis_root_policy_self_test.py`；`git diff --check`；两轮 bounded
  independent read-only review。
- Results：SBOM self-test/generate/verify 与 clean `just ci` exit 0；第二轮 SBOM review 在 system
  Python 3.9.6 与当前 Python 验证 P0/P1=0，2,000 轮 fd probe 为 `4 → 4`。治理 RED 先以
  `PF-DOC-EVIDENCE-BOOTSTRAP-UNVERIFIED` 失败；实现中的 exact consumer 后 docs self-test 为
  `ok (186 mutations)`，Genesis root policy self-test 为 `ok`。最终两路独立只读复核均为
  P0=0/P1=0：generic docs loader 的 FIFO hardlink alias 在 3 秒内 fail closed，同进程 2,000 次
  拒绝的 fd probe 为 `5 → 5`；root policy 的 write/fsync/link race fault injection、稳定诊断、
  `0400` 权限与 digest KAT 均真实命中。
- Limitations：`GOV-GENESIS-001`、`GOV-MAINTAINERS-001`、`GOV-AUTH-001`、`GOV-CHANGE-001` 与
  `GOV-TASK-FREEZE-001` 仍为 `proposed`；新 gate 因而在当前仓库正确返回
  `PF-DOC-FX-APPROVAL`。本条不记录人类批准，不生成实际 genesis root key/policy，
  不创建 D0-06 closeout attest，也不把 development SBOM 写成 point-in-time release binding；后者仍属
  `TASK-D0-08`。
- Next：取得 `davirain` 对五份治理文档的明确书面批准，并由其离线仪式提供 public key/keyId
  生成 policy 后，先以独立接受变更落地治理状态与 fail-closed gate 并跑全量门禁；再以另一
  变更关闭 D0-06。不得把两步合并。

## 2026-07-17 — TASK-D0-06 R5 external-prerequisite block triage

- Trigger：`TASK-D0-06` 冻结包以 `68b0b528579b521fe6a3f172c1358af36853bdf5` 为基线、
  `maxCommits=20`；到输入 HEAD `70717a20` 的 repository-level 距离为 33 个 commit，其中技术
  GREEN 前的 20 个归属 D0-06，之后 13 个为治理/SBOM fail-closed 修复、不得冒充 task-owned
  commit。D0-06 已到达冻结 budget 边界且剩余输入属于 R5 外部前置，因此在任何后续实现前
  主动执行 Block triage。
- Decision：选择 **Block**（R5 外部前置），只把任务状态由 `in_progress` 改为 `blocked`；冻结
  output、dependencies、prerequisites、`TST-COMMON-001`、doneWhen 与 `EV-20260717-0034`
  均不改变，不创建新 EV 或 closeout attest。
- Blocker：五份 genesis 治理文档尚未取得实名书面批准，离线 maintainer 也尚未提供 Ed25519
  public key/keyId；这些输入不允许由实现 agent 伪造、替代或通过生成私钥来绕过。
- Proposal consistency：D0 task-set 文本统一为已登记并锁定的 `TASK-D0-01`…`TASK-D0-08`；
  D0-02 顶部历史注记与表格 `done` 状态对齐；`TST-SBOM-002` 仍保持 catalog-only，待先解决
  Tool Lock digest authority、完整 supply-chain closure 与 release-binding wire 后再写可执行验收；
  本变更不把 D0-08 标为开工。
- Validation boundary：本 triage 是任务控制面事实，不把 development common-primitives 证据提升为
  bootstrap/formal，也不使仍为 `proposed` 的 genesis 治理生效。

## 2026-07-17 — TASK-D0-06 genesis closeout completed

- Authority：genesis root policy 已由独立提交 `306b7b6a` 建立；五份治理文档随后由人类批准并在
  `be7b3642` 统一转为 `accepted`，`GOV-GENESIS-001` 因而生效。本关单与批准变更保持分离。
- Closure：新增 `docs/governance/bootstrap-closure/TASK-D0-06.attest.json`，精确绑定冻结包
  `sha256:2693340d0ce99a54cd63e2ee0e7c2e4c76570cddcb137c7c6d60e962470d7f35`、技术证据
  `EV-20260717-0034`、RED `807d73ba`、GREEN `343a08f2`、232 个 focused assertions、clean
  detached `just ci` 与独立复核 P0=0/P1=0。
- Evidence/state：新增 bootstrap `EV-20260717-0035`；任务表将 D0-06 从 `blocked` 更新为
  `done`，checkpoint 的 blocker 集合收窄为 D0-04。历史 partial `EV-0032` 与 technical
  `EV-0034` 保留在 ledger，但不再作为 task row 的完成证据。
- Validation：重新执行 focused Common build/aggregate test、严格 docs check 与 diff hygiene；结果见
  本关单提交。该结果只关闭 common-primitives genesis/bootstrap 边界，不声称 formal 或 hermetic。
- Next：进入 D0-04 的冻结 bootstrap foundation 实现；当前机器的 broken system-volume seal 与
  current-user-mutable Xcode 继续使 eligible Stage-0 fail closed，因此先推进不伪造正式收据的
  pre-acceptance RED/GREEN 切片。

## 2026-07-17 — D1 source/declaration pre-acceptance slices（formal tasks remain pending）

- Commits：NodeId RED/GREEN/FIX `51cce575`/`75b7a62c`/`cdeff9d3`；source span
  RED/GREEN/FIX `6e559103`/`0e2013f6`/`6dc5acaa`；`Bool`/`commitment` declaration
  RED/GREEN `bc8324fe`/`d174e130`；review-gap RED/FIX `89a611b5`/
  `4d4f7c7961b93b3ea20982a4eeafdc93cbfef89d`。
- Spec/Test：`SPEC-LANG-001`、`SPEC-SOURCE-WIRE-001`、`TST-SRC-001`、`TST-SRC-002`、
  `TST-SRC-004`。这是任务表明确允许的 pre-acceptance evidence，不改变 `TASK-D1-01`/
  `TASK-D1-03` 的 pending 状态、依赖、Tests 集合或 Done 语义。
- Changed：新增 canonical NodeId v1 preimage/path vocabulary 与 topology validation；新增从 Lean
  original parser Syntax 整树提取并验证 byte span 的 snapshot/token 防伪边界；扩展共享 DSL decoder，
  支持 `Bool` 和 `commitment` parameter，同时把 `pfType` 解析为 ident 后在 decoder 中对白名单
  `UInt64`/`Bool` 的原始 token spelling fail closed，避免把 `Bool` 注册成污染宿主 Lean term grammar
  的全局关键字或接受 escaped spelling。新增 `value.bool`/`disclosure.commitment` 独立 requirements；
  当前四个 descriptor 不声明支持，从而在 target Plan 前拒绝。
- Commands：`lake build Tests.Language.SourceIdentity Tests.Language.SourceSpan proof_forge_next_tests`；
  `lake build Tests.Language.PrimitiveDeclarations proof_forge_next_tests`；
  `lake env .lake/build/bin/proof-forge-next-tests`；分别在 `6dc5acaa` 与 `d174e130` 执行 `just ci`；
  `just dsl-negative`；final `just ci` at `4d4f7c79`；`git diff --check`；bounded independent
  read-only review/re-review。
- Results：focused aggregate、双入口 escaped/unknown/qualified type negatives 与前两次 `just ci`
  exit 0；clean detached `4d4f7c79` 的 final `just ci` 也 exit 0。source identity/span review
  P0=0/P1=0；首轮 Bool review 的三个 P1 已由 `89a611b5`/`4d4f7c79` 修复：raw spelling exact、
  commitment 独立 requirement、Bool support envelope；re-review P0=0/P1=0。development evidence
  为 `EV-20260717-0036` 与 `EV-20260717-0037`。
- Limitations：D0 formal milestone 仍为 5/8；`TASK-D0-04` blocked，`TASK-D0-07`/`D0-08`
  pending。D1 没有冻结完成包或 eligible formal authority，完整 grammar、ProgramV1 traversal、
  Diagnostic v1、contained frontend worker 与 hermetic evidence 均未完成；不得把这些切片写成
  `TASK-D1-01` 或 `TASK-D1-03` done。
- Next：当前唯一 development pointer 是 D1-PA-03 的文档/evidence/review 收口；完成后进入
  D1-PA-04，为 exact `Field bn254_fr` 写 RED，并固定其他 field identifier 的 fail-closed 行为。

## 2026-07-17 — D1 exact Field declaration pre-acceptance slice

- Commits：RED `1a81418e`；GREEN `d99d67a2`；coverage hardening `4c4b0eb2`。
- Spec/Test：`SPEC-LANG-001`、`SPEC-TYPE-001`、`TST-SRC-004`。本切片只追加 D1-PA-04
  development evidence，不改变 `TASK-D1-03` 的 pending 状态、依赖、Tests 集合或 Done 语义。
- Changed：portable type decoder 只接受 raw exact `Field bn254_fr` 并映射当前唯一 Phase 1
  `Source.ValueType.field`；state、initializer parameter、entry parameter/result 与 view result 经 Lean
  command/ParserSession 产生相同 AST/sourceHash。Semantic normalization 推导独立
  `value.field.bn254-fr` requirement，canonical requirement tag 仅在既有 0..9 后追加 10；当前四个
  descriptor 均不声明支持，因此在 target-owned Plan 前 fail closed。
- Negatives：escaped constructor、escaped/alternate/qualified/missing field identifier 与 unknown
  constructor 均由 direct Loader matrix 覆盖；六份 fixture 同时经过 Lean command 与 CLI build，固定
  `PF-SRC-INVALID: unsupported portable type` 且零制品。
- Commands：`lake build Tests.Language.FieldDeclarations proof_forge_next_tests`；
  `lake env .lake/build/bin/proof-forge-next-tests`；`just dsl-negative`；clean committed archive
  `just ci` at `4c4b0eb2`；bounded independent read-only review。
- Results：focused aggregate、dual-entry negatives 与完整 `just ci` exit 0；independent review
  P0=0/P1=0。development evidence 为 `EV-20260717-0038`。
- Limitations：当前 `.field` 是唯一 `bn254_fr` 的 alpha nullary carrier，不是完整
  `Source.ProgramV1 Type.Field.spec`；没有 target materializer 声称 Field 支持。D0 formal milestone
  仍为 5/8，D1 formal task 仍为 pending，本结果不是 eligible/hermetic/formal evidence。
- Next：唯一 active development pointer 推进到 D1-PA-05（state visibility carrier、canonical source
  binding 与 disclosure support envelope）；D1-PA-06 排队为 event/error declaration carriers 与
  declaration-order duplicate rejection。

## 2026-07-17 — D1 state visibility pre-acceptance slice

- Commits：carrier RED `e1a61872`；GREEN `f2b3f02e`；forged-resolution RED `cf0805d3`；
  support revalidation FIX `be71e864`。
- Spec/Test：`SPEC-LANG-001`、`SPEC-SOURCE-WIRE-001`、`SPEC-TYPE-001`、`TST-SRC-004`。
  本切片只追加 D1-PA-05 development evidence，不改变 `TASK-D1-03` 的 pending 状态、依赖、
  Tests 集合或 Done 语义。
- Changed：`state` declaration 支持 omitted/public/private/commitment visibility；omitted 与 explicit
  public materialize 为同一值，private/commitment 保持不同 Source AST/sourceHash。visibility 逐 state
  贯穿 Source→Typed→Semantic，并按 source wire 的 `visibility,name,type` 与 semantic wire 的
  `id,name,type,visibility` 顺序进入 canonical bytes。
- Support：private/commitment state 分别推导 `disclosure.private-state` 与
  `disclosure.commitment-state`，canonical requirement tags 在既有 0..10 后追加 11/12；当前四个
  Phase 1 descriptor 均在 Plan 前拒绝。该边界不借用 Noir 的 parameter-only private witness support。
- Security review：首轮独立审查发现 public `ResolvedProgram` 可被伪造后直接送入 `makePlan`，从而
  绕过 resolver；`cf0805d3` 固定 exploit，`be71e864` 新增共享 `validateResolved` 并让 EVM、Solana、
  NEAR、Noir 在任何 Plan 构造前重验 exact descriptor、requirement envelope 与 support。复核
  P0=0/P1=0；Noir private parameter/PrivateSum4 正常 witness 路径保持通过。
- Commands：`lake build Tests.Language.StateVisibility Tests.Materialization.Targets
  proof_forge_next_tests`；`lake env .lake/build/bin/proof-forge-next-tests`；`just dsl-negative`；
  clean committed archive `just ci` at `be71e864`；`git diff --check`；bounded independent
  review/re-review。
- Results：focused、aggregate、parser negatives、forged resolver negative、DSL negatives 与完整
  `just ci` exit 0；development evidence 为 `EV-20260717-0039`。
- Limitations：只实现 declaration carrier、canonical binding 与 fail-closed support envelope；D2
  visibility flow、state custody/continuity、target private/commitment state Plan 均未实现。D0 formal
  milestone 仍为 5/8，D1 formal task 仍 pending，本结果不是 eligible/hermetic/formal evidence。
- Next：唯一 active development pointer 推进到 D1-PA-06（event/error declaration carriers）；
  D1-PA-07 排队为 struct/enum declaration carriers 与 field/variant duplicate rejection。

## 2026-07-17 — D1 event/error declaration pre-acceptance slice

- Commits：initial RED `4a85ffed`；canonical hardening RED `0a348f7e`；payload/escaped-keyword
  RED `7ac2d531`；carrier GREEN `481b59fb`；reserved-identifier RED `795e1b45`；contextual
  identifier FIX `3da5e09b`。
- Spec/Test：`SPEC-LANG-001`、`SPEC-SOURCE-WIRE-001`、`TST-SRC-004`。本切片只追加
  D1-PA-06 development evidence，不改变 `TASK-D1-03` 的 pending 状态、依赖、Tests 集合或
  Done 语义。
- Changed：新增 `Source.EventDecl`/`Source.ErrorDecl`、对应 `Source.Item` alternatives 与
  `Source.Program.events/errors` declaration-order arrays；Lean command 与 ParserSession 共享 decoder
  并保留 exact name、parameter name/type/visibility/order。`error E` 与 `error E()` 物化为同一
  carrier；同类 declaration order、kind、array count 与完整 parameter payload 都进入 alpha
  canonical source binding。
- Validation：event/error 名称分别唯一，parameter duplicate 按各自 declaration order 选择首错；
  fixtures 通过 Lean command 与 CLI Loader 固定相同 `PF-SRC-INVALID` 且零输出。escaped leading
  `«event»`/`«error»` 不冒充关键字。
- Safety：声明表未进入 Typed/Semantic 前，`Typed.check` 与 `Compiler.compile` 对任一非空 table
  fail closed，不能静默丢弃后进入 resolver/Plan；仅声明 event 不推导 `eventEmission`。为避免污染
  Lean 宿主 keyword，event/error 仅在 `pfItem` 首位按 raw token 识别；共享 identifier decoder
  同时拒绝 DSL 名称中的普通/escaped `event`/`error`，宿主 `def event`/`def error` positive control
  保持通过。
- Security review：首轮审查补出 parameter payload/kind/error-order/compiler-bypass 攻击向量；复核
  又发现 contextual word 可被当作 DSL 名称的 P1，并由 `795e1b45`/`3da5e09b` 固定和关闭。最终
  independent re-review P0=0/P1=0。
- Commands：`lake build Tests.Language.EventErrorDeclarations proof_forge_next_tests`；
  `lake env .lake/build/bin/proof-forge-next-tests`；`just dsl-negative`；clean committed archive
  `just ci` at `3da5e09b`；`git diff --check`；bounded independent review/re-review。
- Results：focused、aggregate、canonical mutation matrix、dual-entry negatives、host-positive control、
  isolation archive、108-job build、186 项 docs mutation、SBOM/runtime closure 与完整 `just ci` exit 0；
  development evidence 为 `EV-20260717-0040`。
- Limitations：alpha projection 尚未保留完整 `Source.ProgramV1.items` 的跨 kind source order；没有
  Typed/Semantic event/error tables、emit/revert statement、ABI lowering 或 target support。D0 formal
  milestone 仍为 5/8，D1 formal task 仍 pending，本结果不是 eligible/hermetic/formal evidence。
- Next：唯一 active development pointer 推进到 D1-PA-07（struct/enum declaration carriers）；
  D1-PA-08 排队为 const declaration carrier、canonical value binding 与 duplicate/type boundary。

## 2026-07-17 — D1 struct/enum declaration pre-acceptance slice

- Commits：initial RED `876770e5`；canonical hardening RED `0b5767d5`；parser/reserved-name RED
  `71d10745`；carrier GREEN `9ce2227a`；declaration-name binding hardening `199e54f7`。
- Spec/Test：`SPEC-LANG-001`、`SPEC-SOURCE-WIRE-001`、`TST-SRC-004`。本切片只追加
  D1-PA-07 development evidence，不改变 `TASK-D1-03` 的 pending 状态、依赖、Tests 集合或
  Done 语义。
- Changed：新增 `Source.FieldDecl`、`Source.StructDecl`、`Source.EnumVariant`、`Source.EnumDecl`，
  对应 `Source.Item` alternatives 与 `Source.Program.structs/enums` declaration-order arrays；
  Lean command 与 ParserSession 继续共享同一 decoder/validator/quote 路径。struct field 支持当前
  alpha primitive 与 exact `Field bn254_fr`，enum 支持 bare nullary 与 nonempty typed payload。
- Binding：struct/enum kind、declaration name/count/order、field name/type/count/order、variant
  name/count/order 及 payload type/count/order 全部进入 canonical source bytes；每个维度均有单变量
  sourceHash mutation，command/Loader 的完整 `Source.Program` 与 sourceHash 相等。
- Validation：struct/enum declaration、field/variant duplicate 按声明序确定首错；empty aggregate 与
  `Variant()` fail closed。`struct`/`enum` 只在 `pfItem` 首位按 raw contextual spelling 识别，escaped
  introducer 不冒充关键字；共享 identifier decoder 同时拒绝普通/escaped 保留名，宿主 Lean 的
  `def struct`/`def enum` positive control 保持通过。
- Safety：named-type table 尚未进入 Typed/Semantic，因此 `Typed.check` 与 `Compiler.compile` 对
  struct-only、enum-only 分别使用稳定诊断 fail closed，不能静默擦除后进入 resolver/target Plan。
- Security review：首轮审查要求隔离 canonical count/order/kind 与普通/escaped identifier 攻击面；
  补强后仅剩 declaration name 单变量 binding 的 P1，由 `199e54f7` 固定并关闭。最终 independent
  re-review P0=0/P1=0。
- Commands：`lake build Tests.Language.AggregateDeclarations proof_forge_next_tests`；
  `lake env .lake/build/bin/proof-forge-next-tests`；`just dsl-negative`；clean committed archive
  `just ci` at `199e54f7`；`git diff --check`；bounded independent review/re-review。
- Results：focused、aggregate、canonical mutation matrix、dual-entry negatives、host-positive control、
  isolation archive、110-job build、186 项 docs mutation、治理/SBOM/runtime closure 与完整 `just ci`
  exit 0；development evidence 为 `EV-20260717-0041`。
- Limitations：alpha projection 只分别保留 structs/enums declaration order，尚无完整跨 kind
  `Source.ProgramV1.items`；没有 named-type checker、constructor/match、Typed/Semantic aggregate
  tables 或 target materialization。当前 alpha 全局 parser 也尚未强制 parent-relative 首 child
  indentation；该统一 layout contract 不在本切片内。D0 formal milestone 仍为 5/8，D1 formal task
  仍 pending，本结果不是 eligible/hermetic/formal evidence。
- Next：唯一 active development pointer 推进到 D1-PA-08（const declaration carrier、canonical
  value binding 与 duplicate/type boundary）；D1-PA-09 排队为 pure fn declaration carrier、
  canonical signature/body binding 与 duplicate/fail-closed boundary。

## 2026-07-17 — D1 const declaration pre-acceptance slice

- Commits：initial RED `1c792f72`；validation-priority RED `cd29bf21`；decode-binding RED
  `05aa1efa`；carrier GREEN `8cc05c57`。
- Spec/Test：`SPEC-LANG-001`、`SPEC-SOURCE-WIRE-001`、`TST-SRC-004`。本切片只追加
  D1-PA-08 development evidence，不改变 `TASK-D1-03` 的 pending 状态、依赖、Tests 集合或
  Done 语义。
- Changed：新增 `Source.ConstDecl{name,type,value}`、`Source.Item.constDecl` 与
  `Source.Program.consts`；Lean command/ParserSession 共享 contextual raw `const` decoder、validator
  与 quote。仅复用当前 alpha literal/variable/checked-add expression，不扩张 D1-04 grammar。
- Binding：const 固定投影槽位于 enums/events 之间；declaration name/type/value/count/order、
  expression kind/variable/literal/operand order 全部进入 canonical source bytes。新增 empty const slot
  会改变既有 program 的 development sourceHash，因此完整 clean archive/aggregate 已重跑。
- Validation：duplicate const 位于 enum duplicate 与 initializer parameter duplicate 之间；const item
  内部显式按 name→type→value 解码。双入口 fixtures 固定两组邻接优先级、reserved-name/type/value
  优先级、unknown type、UInt64 overflow、escaped introducer 与普通/escaped保留名。
- Safety：`const` 只按 contextual raw spelling 识别，未污染宿主 Lean identifier。D2 const
  type/name resolution 与 folding 尚未实现，因此 `Typed.check`/`Compiler.compile` 对任一非空 const
  table 使用稳定诊断 fail closed，不能进入 Semantic、resolver 或 target Plan。
- Review/commands：最终 independent review P0=0/P1=0；`lake build
  Tests.Language.ConstDeclarations proof_forge_next_tests`；`lake env
  .lake/build/bin/proof-forge-next-tests`；`just dsl-negative`；clean committed archive `just ci` at
  `8cc05c57`；`git diff --check`。
- Results：focused、104-job aggregate、dual-entry negatives、isolation archive、112-job clean build、
  186 项 docs mutation、治理/SBOM/runtime closure 与完整 `just ci` exit 0；development evidence 为
  `EV-20260717-0042`。
- Limitations：只保证 const 同类 declaration order，不保留跨 kind `Source.ProgramV1.items`；没有
  const type/name resolution、folding、forward reference、Semantic constant table 或 target
  materialization。D0 formal milestone 仍为 5/8，D1 formal task 仍 pending，本结果不是
  eligible/hermetic/formal evidence。
- Next：唯一 active development pointer 推进到 D1-PA-09（pure fn declaration carrier、canonical
  signature/body binding 与 duplicate/fail-closed boundary）；D1-PA-10 排队为 invariant declaration
  carrier、canonical expression binding 与 duplicate/fail-closed boundary。

## 2026-07-17 — D1 pure fn declaration pre-acceptance slice

- Commits：initial RED `0e8b82ca`；carrier-binding RED `337eedff`；validation RED
  `7df85988`；priority RED `ecb517da`；carrier GREEN `c62937d1`；review-gap hardening
  `419c1564`；legacy-block order RED/FIX `1c94e414`/`6c88b376`。
- Spec/Test：`SPEC-LANG-001`、`SPEC-SOURCE-WIRE-001`、`TST-SRC-004`。本切片只追加
  D1-PA-09 development evidence，不改变 `TASK-D1-03` 的 pending 状态、依赖、Tests 集合或
  Done 语义。
- Changed：新增 `Source.FnDecl{name,params,result,body}`、`Source.Item.fnDecl` 与
  `Source.Program.functions`；Lean command/ParserSession 共享 contextual raw `fn` decoder、
  validator 与 quote，并保持 fn 同类源码顺序。当前只复用 alpha parameter/type/statement/
  expression carrier，未扩张 D1-04 expression grammar。
- Binding：fn declaration kind/name/count/order、parameter name/type/visibility/count/order、result、
  body statement count/order、expression kind/value/operand order 与 synchronous call callee 全部进入
  canonical source bytes；同前缀 1→2 count 及 parameter 字段与 body 解耦 mutation 均有独立回归。
- Validation/Layout：duplicate fn 位于 const duplicate 与 initializer parameter 之间；
  fn 内部按 name→params→result→body 解码，parameter duplicate 优先于 empty body。
  `fn` 只按 raw contextual spelling 识别，escaped introducer 与普通/escaped 保留名 fail closed，
  宿主 Lean `def fn` 保持可用。评审发现旧 `ppIndent` 会拒绝合法后继 fn，因此
  init/entry/view 与 fn 统一使用 `manyIndent(pfStmt)` block termination，三种
  `legacy block → fn` source order 均由 command/Loader parity fixture 锁定。
- Safety：D2 local-call lookup、type/effect/return/acyclicity 检查尚未实现，因此
  `Typed.check` 与 `Compiler.compile` 对任一非空 fn table 使用稳定诊断 fail closed，
  不能静默擦除后进入 Semantic、resolver 或 target Plan。
- Review/Commands：最终 independent re-review P0=0/P1=0；`lake build
  Tests.Language.FnDeclarations`；`lake build proof_forge_next_tests`；
  `lake env .lake/build/bin/proof-forge-next-tests`；`just dsl-negative`；clean committed
  `just ci` at `6c88b376`；`git diff --check`。
- Results：focused、106-job aggregate、canonical mutation matrix、dual-entry negative/layout positive、
  isolation archive、114-job clean build、186 项 docs mutation、治理/SBOM/runtime closure 与完整
  `just ci` exit 0；development evidence 为 `EV-20260717-0043`。
- Limitations：当前 alpha 只接受 explicit result type，没有 optional `Unit` return、local-call
  resolution、type/effect/return/acyclicity、跨 kind callable namespace、完整 ordered
  `Source.ProgramV1.items`、Semantic fn table 或 target materialization。D0 formal milestone 仍为
  5/8，D1 formal task 仍 pending，本结果不是 eligible/hermetic/formal evidence。
- Next：唯一 active development pointer 推进到 D1-PA-10（invariant declaration carrier、
  canonical expression binding 与 duplicate/fail-closed boundary）；D1-PA-11 排队为
  extension requirement carrier、exact version/digest binding 与 duplicate/fail-closed boundary。

## 2026-07-17 — D1 invariant declaration pre-acceptance slice

- Commits：carrier RED `c635815b`；dual-entry/priority RED `469c4d7a`；carrier GREEN 与 parser
  boundary fix `5b01b4bf`。
- Spec/Test：`SPEC-LANG-001`、`SPEC-SOURCE-WIRE-001`、`TST-SRC-004`。本切片只追加
  D1-PA-10 development evidence，不改变 `TASK-D1-03` 的 pending 状态、依赖、Tests 集合或
  Done 语义。
- Changed：新增 `Source.InvariantDecl{name,predicate}`、`Source.Item.invariantDecl` 与
  `Source.Program.invariants`；Lean command/ParserSession 共享 contextual raw `invariant` decoder、
  validator 与 quote，并保持 invariant 同类源码顺序。当前只复用 alpha expression carrier，未扩张
  D1-04 expression grammar。
- Binding：invariant declaration kind/name/count/order、predicate literal/variable/checked-add kind、
  value与 operand order 全部进入 canonical source bytes；同前缀 count、declaration name 与各 expression
  分量均有独立 mutation 回归。
- Validation/Layout：duplicate invariant 位于 duplicate fn 与 initializer parameter 之间；item 内部按
  name→predicate 解码。escaped introducer、普通/escaped保留名、reserved predicate 与 UInt64 overflow
  均由 Lean command 和 ParserSession exact fail closed。实现时发现旧 `pfType ::= ident | ident ident`
  会跨行把后继 `invariant` 吞作第二个 type identifier；现已统一为带同行约束的 portable type parser，
  并由 state/legacy declaration 后接 invariant 的 parity fixture 固定。低优先级 shape fallback 同样带
  同行约束，只把 malformed contextual forms 导向共享稳定诊断，不生成 Source item。
- Safety：D2 predicate Bool typing、name/const/pure-fn resolution 与 proof binding 尚未实现，因此
  `Typed.check` 与 `Compiler.compile` 对任一非空 invariant table 使用稳定诊断 fail closed，不能静默
  擦除后进入 Semantic、resolver 或 target Plan。
- Review/Commands：最终 independent review P0=0/P1=0；`lake build
  Tests.Language.InvariantDeclarations Tests.Language.FieldDeclarations Tests.Language.ConstDeclarations
  Tests.Language.EventErrorDeclarations Tests.Language.FnDeclarations`；`lake build
  proof_forge_next_tests`；`lake env .lake/build/bin/proof-forge-next-tests`；clean committed `just ci`
  at `5b01b4bf`；`git diff --check`。
- Results：focused、aggregate、canonical mutation matrix、dual-entry negatives、isolation archive、
  116-job clean build、108-job aggregate、186 项 docs mutation、治理/SBOM/runtime closure 与完整
  `just ci` exit 0；development evidence 为 `EV-20260717-0044`。
- Limitations：当前 alpha 只保留 invariant 同类 declaration order；没有 predicate Bool checking、
  name/const/pure-fn resolution、proof reference binding、Semantic invariant table/ordinal/provenance/
  requirements、完整 ordered `Source.ProgramV1.items` 或 target materialization。D0 formal milestone 仍为
  5/8，D1 formal task 仍 pending，本结果不是 eligible/hermetic/formal evidence。
- Next：唯一 active development pointer 推进到 D1-PA-11（extension requirement carrier、exact
  version/digest binding 与 duplicate/fail-closed boundary）；D1-PA-12 排队为 proof reference carrier、
  exact invariant/qualified theorem binding 与 duplicate/fail-closed boundary。

## 2026-07-17 — D1 extension requirement pre-acceptance slice

- Commits：完整 carrier/negative matrix RED `5d73bf65`；parser、Source canonical、quote 与 Typed
  fail-closed GREEN `5dca8069`。
- Spec/Test：`SPEC-LANG-001`、`SPEC-SOURCE-WIRE-001`、`SPEC-CAP-001`、`TST-SRC-004`。本切片
  只追加 D1-PA-11 development evidence，不改变 `TASK-D1-03` 的 pending 状态、依赖、Tests 集合或
  Done 语义。
- Changed：新增 `Source.ExtensionReq{id,version,digest}`、`Source.Item.extensionReq` 与
  `Source.Program.extensionRequirements`；Lean command/ParserSession 共享 contextual raw
  `requires extension ... version ... digest ...` parser/decoder、validator 与 quote，并保持同类源码顺序。
- Exact scalar boundary：ID 复用 locked common lowercase dotted ASCII grammar；version 复用完整
  SemVer parse+render 且保留 prerelease/build identity；digest 复用 exact lowercase SHA-256
  parse+render。Source wire 仍保存规范要求的 canonical strings，不把 D1 carrier 偷换为 typed
  requirement key，也不接受 range/latest/wildcard、v-prefix、uppercase/bare digest 或 alias。
- Binding/Validation：独立 canonical 尾槽固定 count 与每项 id→version→digest，mutation 分别覆盖
  presence、同前缀 count、ID、完整 SemVer（含独立 build identity）、digest 与 declaration order。duplicate
  按 ID 而非完整 triple 拒绝，优先级固定为 invariant duplicate→extension duplicate→initializer
  parameter；item decode 固定 id→version→digest。
- Safety：四个 contextual words 不污染宿主 Lean identifier；escaped structural word、raw escaped ID、
  ordinary wrong structural word 均 fail closed，extension 后接 state/invariant/fn 不被吞噬或混入错误
  table。D2 typed registry、operation/effect rules、requirement inference 与 support resolution 尚未实现，
  因此 `Typed.check`/`Compiler.compile` 对任一非空 extension table 精确 fail closed。
- Review/Commands：adversarial review P0=0/P1=0；`lake build
  Tests.Language.ExtensionRequirements`；`lake build proof_forge_next_tests`；`lake env
  .lake/build/bin/proof-forge-next-tests`；`just dsl-negative`；clean committed `just ci` at
  `5dca8069`；`git diff --check`。
- Results：focused、canonical mutation matrix、20 个双入口 negatives、isolation committed archive、
  118-job clean build、110-job aggregate、186 项 docs mutation、治理/SBOM/runtime closure 与完整
  `just ci` exit 0；development evidence 为 `EV-20260717-0045`。
- Limitations：当前 alpha 只保证 extension 同类 declaration order；没有 typed extension registry、
  registered typed syntax/operation/effect rules、requirement inference、semantic registry digest、support
  resolution、完整 ordered `Source.ProgramV1.items` 或 target materialization。digest continuation 的额外
  indentation 不是当前 EBNF 的独立约束；malformed form 使用 Lean reserved token 时仍可能在 parser
  层返回通用拒绝，stable Diagnostic v1 属于 D1-07。D0 formal milestone 仍为 5/8，D1 formal task
  仍 pending，本结果不是 eligible/hermetic/formal evidence。
- Next：唯一 active development pointer 推进到 D1-PA-12（proof reference carrier、exact
  invariant/qualified theorem binding 与 duplicate/fail-closed boundary）；D1-PA-13 排队为
  entry/view/fn cross-kind callable namespace uniqueness 与 deterministic validation priority。

## 2026-07-17 — D1 proof reference pre-acceptance slice

- Commits：carrier/validation/canonical RED `105a76e2`；Source/Syntax/Typed GREEN `fc89664e`；
  isolation review fix `751844f8`；reserved theorem component RED `2a5d1b1f` 与 FIX `b0c679ef`。
- Spec/Test：`SPEC-LANG-001`、`SPEC-SOURCE-WIRE-001`、`SPEC-SEM-001`、`TST-SRC-004`。本切片
  只追加 D1-PA-12 development evidence，不改变 `TASK-D1-03` 的 pending 状态、依赖、Tests 集合或
  Done 语义。
- Changed：新增 `Source.ProofDecl{invariant,theorem:Array String}`、`Source.Item.proofDecl` 与
  `Source.Program.proofReferences`；Lean command/ParserSession 共享 contextual raw
  `proof ... using ...` parser/decoder、validator 与 quote，并保持同类源码顺序。
- Qualified identity：theorem 从 Lean `Name` 逐 component 提取，经 locked Common QualifiedName
  NFC/identifier/1..256 validation 后额外要求至少两个 components；禁止 dotted-string split、current
  namespace qualification、short-name fallback 或 Environment lookup。decoded component array进入 Source，
  escaped token spelling 不进入 canonical value，whole escaped dotted component按无效 component拒绝；每个
  theorem component 复用普通 DSL identifier 的 reserved predicate，通用 Common QualifiedName 不承载
  语言关键字策略。
- Binding/Validation：独立 canonical 尾槽固定 reference count与每项 invariant→theorem component
  array；mutation覆盖 presence、同前缀 count、invariant、component count/value/order与reference order。
  duplicate按 invariant而非 theorem拒绝；validation固定 extension duplicate→proof duplicate→按 proof
  source order unknown invariant→initializer parameter，允许 exact forward declaration。
- Safety：D1 parser不读取 ambient Lean theorem、同文件 declaration、`.olean`或proof bundle，不构造
  expected theorem type，也不改变业务执行/requirements/semanticHash/target selection。`proof`加入 DSL
  reserved set后，旧 Bool/commitment fixture参数改为语义等价 `witness`；首轮完整 isolation gate还发现
  theorem示例含 legacy `ProofForge.*`文本，`751844f8`改为中性 `Bundle.*`。随后独立审查发现
  `Pkg.«proof»` 可绕过语言保留词；先以 `2a5d1b1f` 证明 RED，再由 `b0c679ef` 因子化共享校验修复。
- Review/Commands：最终 review P0=0/P1=0/P2=0；`lake build Tests.Language.ProofReferences`；`lake build
  proof_forge_next_tests`；`lake env .lake/build/bin/proof-forge-next-tests`；`just dsl-negative`；clean
  committed `just ci` at `b0c679ef`；`git diff --check`。
- Results：focused、canonical mutation matrix、12个双入口 negatives、isolation committed archive、
  120-job clean build、112-job aggregate、186项 docs mutation、治理/SBOM/runtime closure与完整
  `just ci` exit 0；development evidence为 `EV-20260717-0046`。
- Limitations：当前 alpha只保证 proof同类 declaration order且不携带 `SourceOrigin`；没有 invariant
  Bool typing、pure-fn closure、Semantic invariant ordinal、closed expected theorem type、proof bundle
  trust/locked `.olean` closure、signature/axiom/unsafe validation、proof validation record、完整 ordered
  `Source.ProgramV1.items`或target integration。D0 formal milestone仍为5/8，D1 formal task仍pending，
  本结果不是 eligible/hermetic/formal evidence。
- Next：唯一 active development pointer推进到 D1-PA-13（entry/view/fn cross-kind callable namespace
  uniqueness与deterministic validation priority）；D1-PA-14排队为对照 frozen TST-SRC-004的Phase 1
  declaration residual gap audit与下一个 bounded RED slice冻结。

## 2026-07-17 — D1 callable namespace pre-acceptance slice

- Commits：callable namespace 与 priority RED `e8acaffa`；shared validation GREEN `9eec99dd`；
  review coverage hardening `70965df3`。
- Spec/Test：`SPEC-LANG-001`、`TST-SRC-004`。本切片只追加 D1-PA-13 development evidence，
  不改变 `TASK-D1-03` 的 pending 状态、依赖、Tests 集合或 Done 语义。
- Changed：`validateDecodedProgram` 在 same-kind fn duplicate 之后、invariant duplicate 之前，以现有
  `HashSet`-based `hasDuplicate` 对 `entries ++ functions` 做 expected-linear shared callable namespace
  validation。entry/view 同名继续由更早的 duplicate entry slot 拒绝；entry/fn、view/fn 同名统一返回
  `contains duplicate callable declarations`，两条前端共用同一 validator。
- Priority/coverage：RED 固定 entry/fn、view/fn、fn duplicate→callable 与 callable→invariant；独立审查
  后补 entry/view 同名及 entry duplicate→callable 两个 dual-entry vectors。六个 fixtures 均要求 Lean
  command 与 CLI Loader 返回逐字相同首错，且无 `.olean`/CLI output。
- Review/Commands：独立 review 对生产实现给出 P0=0；唯一 P1 为 test/spec priority chain 漂移，已在
  同一 checkpoint 修复；三个 P2 中 stale language disclaimer 与两个缺失 coverage pins 均关闭。
  `lake build proof_forge_next_tests`；`lake env .lake/build/bin/proof-forge-next-tests`；`just dsl-negative`；
  clean committed `just ci` at `70965df3`；`git diff --check`。
- Results：120-job clean build、112-job aggregate、186 项 docs mutation、六个 dual-entry callable
  negatives、治理/SBOM/runtime closure 与完整 `just ci` exit 0；development evidence 为
  `EV-20260717-0047`。
- Limitations：本切片只关闭 Source shared validation 的 callable name uniqueness，不实现 D2 local-call
  resolution/type/effect/return/acyclicity，不建立跨 kind ordered `Program.items`，也不改变 Typed/Semantic
  或 target materialization。D0 formal milestone 仍为 5/8，D1 formal task 仍 pending，本结果不是
  eligible/hermetic/formal evidence。

## 2026-07-17 — D1 Phase 1 declaration residual audit

- Scope：D1-PA-14 对照 frozen `TST-SRC-004`、`SPEC-LANG-001` 与当前 Source/Syntax/Typed/tests/fixtures
  做只读 inventory；不重新打开 D1-PA-01..13，不进入 statement/expression、D2 或 target backend。
- Result：13 种 Phase 1 declaration kind 已有 parser/Source coverage；剩余 declaration-shape gap 全部是
  type grammar：integer widths、Unit/omitted return、Principal、Named、Array、Map、Option、Bytes。
- Decision：最小下一 RED 为 D1-PA-15 closed integer-width family，只覆盖 type spelling、declaration
  carrier、canonical binding、双入口 parity 与 zero requirements；literal bounds、negative literal 与 Int
  arithmetic 明确留在 `TST-SRC-005`/D2。现有 `u64=0`、`bool=1`、`field=2` canonical tags/bytes 必须
  append-only 保持，`Field bn254_fr` 的 two-token same-line guard 不得回归。
- Pointer：D1-PA-14 complete (development audit)；唯一 active development pointer 为 D1-PA-15；
  D1-PA-16 排队为 `Unit` carrier 与 omitted return type materialization。

## 2026-07-18 — D1 closed integer-width declaration pre-acceptance slice

- Commits：integer-width declaration RED `d26eb71f`；target-boundary initializer 修正 `bdbdfbf8`；
  Source/Semantic carrier GREEN `db25328b`。
- Spec/Test：`SPEC-LANG-001`、`TST-SRC-004`。本切片只追加 D1-PA-15 development evidence，
  不改变 `TASK-D1-03` 的 pending 状态、依赖、Tests 集合或 Done 语义。
- Changed：`Source.ValueType` 与 `SemanticIR.ValueType` 追加 `u8/u16/u32/u128/u256`、
  `i8/i16/i32/i64/i128/i256`；`decodeTypeIdentifiers`/`quoteValueType` 只接受对应 exact
  unqualified single-token spelling。既有 `u64/bool/field` canonical tags 保持 `0/1/2`，新增类型
  按声明顺序使用 `3..13`；所有新增整数宽度推导零额外 requirement。
- Binding/negatives：一个 declaration surface 覆盖 state、struct field、enum payload、const、init、
  entry/view/fn parameter 与 result；Lean command 与 ParserSession 产生相同 Source AST/sourceHash。
  UInt64 twin golden `89ce98102d576317548ab26a651ea04a09789f4d15704464434a239eb0865494`
  固定旧 tag，width/sign mutation matrix 固定新类型互不别名。十个 Loader negatives 与四个双入口
  fixtures 覆盖 invalid/escaped/qualified/extra-token spelling，均返回 exact
  `PF-SRC-INVALID: unsupported portable type` 且零输出，`Field bn254_fr` two-token guard 未改变。
- Boundary：`WidthBoundary` 使用 UInt8 state、initializer parameter 与 view result；compiler 只推导
  `persistentState`，证明 width 本身没有新 requirement。EVM、Solana、NEAR、Noir 都在 target-owned
  Plan 建立前以 `planInvariant` 的 `is not UInt64` 诊断拒绝，没有生成 artifact；首轮 review 发现
  Solana/NEAR 会先检查 initializer，`bdbdfbf8` 补齐同类型 initializer 后该 P0 关闭。
- Review/Commands：Pi 最终复核 P0/P1/P2=0；独立 production review P0/P1=0。
  `lake build Tests.Language.IntegerWidthDeclarations proof_forge_next_tests`；
  `lake env .lake/build/bin/proof-forge-next-tests`；`just dsl-negative`；clean committed `just ci`
  at `db25328b`；`git diff --check`。
- Results：122-job clean build、114-job aggregate、186 项 docs mutation、治理/SBOM/runtime closure、
  双入口 DSL negatives 与 toolchain negatives 全部 exit 0；development evidence 为
  `EV-20260718-0001`。
- Limitations：仅为 alpha Source declaration type carrier；没有 width-aware literal typing/bounds、
  负数语义、Int arithmetic、跨 kind ordered `Program.items`、target materialization、eligible host 或
  formal D1 evidence。D0 formal milestone 仍为 5/8，`TASK-D1-03` 仍 pending，本结果不是
  eligible/hermetic/formal evidence。
- Next：D1-PA-16 进入 active，范围为 explicit `Unit` carrier 与 omitted return type 的 parse-time
  materialization；其 RED 必须先固定显式/省略形式的 AST/hash 等价与 fail-closed grammar。后续 slice
  尚未冻结，不由 checkpoint 自动递增。

## 2026-07-18 — D1 Unit return materialization pre-acceptance slice

- Commits：Unit/omitted-return RED `dbaf9a20`；bare-colon parser-boundary test correction `25274210`；
  Source/Semantic/Syntax GREEN `a6dc9223`。
- Spec/Test：`SPEC-LANG-001`、`TST-SRC-004`。本切片只追加 D1-PA-16 development evidence，
  不改变 `TASK-D1-03` 的 pending 状态、依赖、Tests 集合或 Done 语义。
- Changed：`Source.ValueType` 与 `SemanticIR.ValueType` append-only 追加 `unit` canonical tag `14`，
  保持既有 tags `0..13` 不变；decoder 只接受 exact unqualified `Unit`。entry、view、fn 的 optional
  result 在 parse time 直接 materialize 为 `.unit`，`do` 仍 mandatory，`init`、event/error 分流与
  `Field bn254_fr` same-line guard 均未改变。`Unit` 推导零额外 requirement。
- Binding/negatives：declaration surface 覆盖 state、struct field、enum payload、const、init、entry/view/fn
  parameter/result；Lean command 与 ParserSession parity 通过，显式 `: Unit` 与省略形式在相同 program
  identity 下产生相同 AST/sourceHash。UInt64/tag0 twin golden
  `91f17e1b7d027ed05cdea72f5d23d48effb6ed981c651eb7318405d1b761b9a1` 与 Unit/tag14 golden
  `6e745638a42bf2a64c004fd001cf3072abb83d2c70a3b285d24966f98ef3a1c8` 固定 append-only binding。
  四个 dual-entry fixtures 覆盖 invalid/escaped/qualified/extra-token spelling；Loader 单入口另固定 bare
  colon 停在 parser boundary。
- Boundary：stateless Unit parameter/result program 编译为 `requirements == #[]`，四个 Phase 1 target 的
  support resolver 均接受；三个 stateful rows 分别固定 Unit state、result 与 parameter，整体只含
  `persistentState`，随后由 EVM、Solana、NEAR、Noir 各自 target-owned Plan 以 `planInvariant` 拒绝，
  没有生成 artifact。
- Review/Commands：Kimi 的唯一 P1（bare-colon negative）由 `25274210` 关闭；Claude scope audit 与独立
  GREEN review 最终均为 P0/P1/P2=0。`lake build Tests.Language.UnitReturnTypes proof_forge_next_tests`；
  `lake env .lake/build/bin/proof-forge-next-tests`；`just dsl-negative`；clean committed `just ci` at
  `a6dc9223`；`git diff --check`。
- Results：124-job clean build、116-job aggregate、186 项 docs mutation、治理/SBOM/runtime closure、
  双入口 DSL negatives 与 toolchain negatives 全部 exit 0；development evidence 为
  `EV-20260718-0002`。
- Limitations：仅实现 declaration carrier 与 parse-time result materialization；没有无值 `return`、
  `Unit` fallthrough、D2 return-path/type/effect checking、跨 kind ordered `Program.items`、target
  materialization、eligible host 或 formal D1 evidence。D0 formal milestone 仍为 5/8，`TASK-D1-03`
  仍 pending，本结果不是 eligible/hermetic/formal evidence。
- Next：requirement/canonical/RED audits 共同选择 D1-PA-17 exact `Principal` declaration carrier；
  declaration 本身必须推导零 requirement，不得误加只属于未来 runtime context expression 的
  `callerContext`。其 RED 先固定 tag `15`、双前端 parity、fail-closed spellings 与 target Plan boundary；
  D1-PA-18 尚未冻结。

## 2026-07-18 — D1 Principal declaration pre-acceptance slice

- Commits：Principal declaration RED `a69cc49c`；Source/Semantic carrier GREEN `c7aa6746`。
- Spec/Test：`SPEC-LANG-001`、`TST-SRC-004`。本切片只追加 D1-PA-17 development evidence，
  不改变 `TASK-D1-03` 的 pending 状态、依赖、Tests 集合或 Done 语义。
- Changed：`Source.ValueType` 与 `SemanticIR.ValueType` append-only 追加 `principal` canonical tag `15`，
  保持既有 tags `0..14` 不变；decoder 只接受 exact unqualified single-token `Principal`，quote/adapt
  逐类型保真。Principal declaration 推导零 requirement，未新增 `ProgramRequirement`，也不把 type
  name 错误映射为 `callerContext`。
- Binding/negatives：declaration surface 覆盖 state、struct field、enum payload、const、init、entry/view/fn
  parameter/result；Lean command 与 ParserSession 产生相同 Source AST/sourceHash。相同 PrincipalTwin
  identity 的 UInt64/tag0、Unit/tag14 与 Principal/tag15 goldens 分别为
  `a194b458092b540ab8e4de2bb91d8ca32b197968f058c93bb7bbfe934340fbc6`、
  `5770bbff593e607d1eb48567c8d17d973fff62c5f1a6dbb013a0d1aa44d5e793`、
  `e7385343712f257d337e738f575d39c5086be34efe807279d1e52dd1a653ffef`。四个 dual-entry fixtures
  覆盖 invalid/escaped/qualified/extra-token spelling，均 exact fail closed。
- Boundary：stateless Principal parameter/result program 编译为 `requirements == #[]` 并显式断言不含
  `callerContext`；三个 stateful rows 分别固定 Principal state、result 与 parameter，整体只含
  `persistentState`。EVM、Solana、NEAR、Noir 的 support resolver 均接受，随后各自 target-owned Plan
  以 `planInvariant` 拒绝，没有生成 artifact。
- Review/Commands：Kimi RED review P0/P1=0；Pi GREEN review P0/P1/P2=0；Claude canonical recheck
  P0/P1=0。`lake build Tests.Language.PrincipalDeclarations proof_forge_next_tests`；
  `lake env .lake/build/bin/proof-forge-next-tests`；`just dsl-negative`；clean committed `just ci` at
  `c7aa6746`；`git diff --check`。
- Results：126-job clean build、118-job aggregate、186 项 docs mutation、治理/SBOM/runtime closure、
  双入口 DSL negatives 与 toolchain negatives 全部 exit 0；development evidence 为
  `EV-20260718-0003`。
- Limitations：仅实现 declaration type carrier；没有 principal literal、`context.caller`、authority、
  D2 value/type/effect semantics、跨 kind ordered `Program.items`、target materialization、eligible host 或
  formal D1 evidence。D0 formal milestone 仍为 5/8，`TASK-D1-03` 仍 pending，本结果不是
  eligible/hermetic/formal evidence。
- Next：residual audits 将 Option 识别为剩余 type family 中最小的可切片候选，但它是首个 payload-
  carrying recursive type。D1-PA-18 先在 alpha authority 中冻结 exact bounded grammar、canonical
  `tag16 || elementType` payload、transitive element requirements 与 fail-closed exclusions，再提交 RED；
  不把 full Named/Bytes/Array/Map 或 D2 runtime Option semantics 吸收进来。

## 2026-07-18 — D1 bounded Option declaration pre-acceptance slice

- Commits：Option declaration RED `f6b2b2bf`；qualified-option rejection-layer correction
  `06c56f78`；Source/Semantic/Syntax GREEN `9858ede0`。
- Spec/Test：`SPEC-LANG-001`、`TST-SRC-004`。本切片只追加 D1-PA-18 development evidence，
  不改变 `TASK-D1-03` 的 pending 状态、依赖、Tests 集合或 Done 语义。
- Changed：`Source.ValueType` 与 `SemanticIR.ValueType` 追加 recursive `option(element)`；两侧 alpha
  canonical encoder append-only 使用 tag `16` 后立即递归编码 element，保持 tags `0..15` 不变。
  decoder 只接受同一行 `Option` 加已实现的 Bool/closed UInt/Int/Principal/Unit 单 token element；
  quote/adapt 逐层保真，requirements 精确传播 `element.requirements`。
- Binding/negatives：declaration surface 覆盖 state、struct field、enum payload、const、init、entry/view/fn
  parameter/result；Lean command 与 ParserSession 产生相同 Source AST/sourceHash。同一 OptionTwin identity
  的 UInt64/tag0、Option UInt64/tag16+0 与 Option Unit/tag16+14 goldens 分别为
  `8bbe116fabb9ea37ec1c6a12c8283c56e62e6b2476d15b80b1d6bc09d8ff1c1a`、
  `d90a6882abbf68c541eebb8a29a5af5667ed91b0862b385be2e5674ccd2b3318`、
  `37d1b79cbb1e7a184e24dd5898954030b5d503033727ee3965fafe7bb0e3c6e6`。plural/escaped/unknown/
  missing/qualified 形态在 decoder exact fail closed；nested/Field/extra payload 停在 parser boundary。
- Boundary：`Option UInt64` 编译为 `requirements == #[]`，四个 target support resolver 接受；
  `Option Bool` 精确保留 `#[.boolValues]` 并由四 target 在 support resolver fail closed。三个 stateful
  rows 分别固定 Option UInt64 state、result 与 parameter，整体只含 `persistentState`，随后由 EVM、
  Solana、NEAR、Noir 各自 target-owned Plan 以 `planInvariant` 拒绝，没有生成 artifact。
- Review/Commands：Kimi RED review P0/P1=0；Pi GREEN review P0/P1=0，两个 P2 均为已冻结的 parser-
  boundary/recursive-carrier 说明项；Claude 独立复算全部 goldens 精确一致，旧快照提出的 qualified-layer
  P1 已由 `06c56f78` 先行关闭。`lake build Tests.Language.OptionDeclarations`；
  `lake build proof_forge_next_tests`；`lake env .lake/build/bin/proof-forge-next-tests`；
  `just dsl-negative`；clean committed `just ci` at `9858ede0`；`git diff --check`。
- Results：128-job clean build、120-job aggregate、186 项 docs mutation、治理/SBOM/runtime closure、
  双入口 DSL negatives 与 toolchain negatives 全部 exit 0；development evidence 为
  `EV-20260718-0004`。
- Limitations：仅实现 bounded declaration structure；没有 none/some expression、unwrap、runtime
  representation、recursive/D2 legality、Option target ABI/materialization、eligible host 或 formal D1
  evidence。D0 formal milestone 仍为 5/8，`TASK-D1-03` 仍 pending，本结果不是 eligible/hermetic/
  formal evidence。
- Next：四路 residual/canonical/parser/RED audit 选择 D1-PA-19 `Bytes N`。先冻结 exact same-line
  canonical decimal `0..4096`、`bytes(UInt32)` carrier、tag `17` 加 encoder-local `appendNat` payload、
  zero requirements 与 parser/decoder fail-closed 分层，再提交 RED；不吸收 bytes runtime 或 stable wire。

## 2026-07-18 — D1 bounded Bytes declaration pre-acceptance slice

- Commits：Bytes declaration RED `4849ae5b`；current-identity golden correction `119307ea`；
  Source/Semantic/Syntax GREEN `7a93fb07`。
- Spec/Test：`SPEC-LANG-001`、`TST-SRC-004`。本切片只追加 D1-PA-19 development evidence，
  不改变 `TASK-D1-03` 的 pending 状态、依赖、Tests 集合或 Done 语义。
- Changed：`Source.ValueType` 与 `SemanticIR.ValueType` append-only 追加 `bytes(length : UInt32)`；
  两侧 alpha canonical encoder 使用 tag `17` 后接各自既有 `appendNat(length.toNat)`，因此 Source
  payload 为 8-byte big-endian，Semantic payload 为 8-byte little-endian，既有 tags `0..16` 不变。
  decoder 只接受同一行 canonical ASCII decimal `0..4096`，在调用任何 Nat literal convenience API
  前先以 raw `numLitKind` spelling 检查长度、前导零、ASCII digit 与上界；struct field 与普通 type
  共用同一 atom decoder，且移除了 guarded `atoms[0]!` partial indexing。
- Binding/negatives：declaration surface 覆盖 state、struct field、enum payload、const、init、entry/view/fn
  parameter/result；Lean command 与 ParserSession 产生相同 Source AST/sourceHash。相同 BytesTwin identity
  的 UInt64、Bytes 0/1/4096 source rows 分别为 229/245/245/245 bytes，hash 为
  `5087d5f55dff32c65d073fe17f4394df78172e7f077343047cdccfdd40b60838`、
  `f1b674b004bf9ea73e04d8ba259bb15ea6d2e02dffbd2c6b853d408eb31c7f77`、
  `60a764e482c81aa2a30fb38dc9dbfab0c674df9bc9fa3d36b538356229949dcc`、
  `3fe714facd3a9c6da07b5aafad460431f2bf8e6e39abec045a69c481def1dba4`；Semantic UInt64/
  Bytes 0/1/32/4096 rows 为 178/194/194/194/194 bytes，对应 hash `3f94b3895e74c237e17cc734c40c93bd026b92a8202a07bfde76b3985d06d735`、
  `a0d095785a535fc1cf821d0ba106c904dac8aac0eb3ba3f14f458499c405af93`、
  `0f7b37ecc8ab5cb335ff1721abedaa71d7a3d0c0a4110c34a057acc3d808bff3`、
  `0849d407e4d47ca2b066f3d2f73069018bd34c34cd14b6b2dca389cef70499fa`、
  `ddb99aa12fb552185a542c75f72800f98182123c27dd3ac99e10377b0357469c`。
  bare/plural/escaped/qualified/identifier/hex/leading-zero/over-limit 形态双入口 exact fail closed；负号、
  extra payload、`Option Bytes N` 与 split-line 形态停在 parser boundary。
- Boundary：Bytes declaration 推导零 requirement；stateless carrier 通过四 target support resolver，三个
  stateful rows 只推导 `persistentState`，随后 EVM、Solana、NEAR、Noir 各自 target-owned Plan 以既有
  non-UInt64 invariant 拒绝且不生成 artifact。capture-for-fail-closed 使 `UInt64 32` 从 parser rejection
  变为 decoder exact rejection，但没有新增被接受的业务语义；该诊断层变化由 grammar review 固定。
- Review/Commands：Kimi grammar review 与 Claude canonical recheck 均 P0/P1=0；coordinator review 移除
  partial indexing。`lake build Tests.Language.BytesTypes proof_forge_next_tests`；
  `lake env .lake/build/bin/proof-forge-next-tests`；`just dsl-negative`；clean committed `just ci` at
  `7a93fb07`；`git diff --check`。
- Results：130-job clean build、122-job aggregate、186 项 docs mutation、治理/SBOM/runtime closure、
  双入口 DSL negatives 与 target/toolchain negatives 全部 exit 0；development evidence 为
  `EV-20260718-0005`。
- Limitations：仅实现 bounded declaration carrier；没有 bytes literal、index/slice/length op、runtime
  representation、nested aggregate、stable Source/Semantic Type wire、target ABI/materialization、eligible
  host 或 formal D1 evidence。Named/Array/Map source type structure 仍未实现；本结果不把 TST-SRC-004
  development declaration-kind coverage冒充完整 Type wire 或 formal `TASK-D1-03` closure。
- Next：task-authority audit 依据 `TST-SRC-004` 的 declaration-kind 完成面与 `TST-SRC-005` 的独立
  statement/expression 面，选择 D1-PA-20 `let name [ : Type ] := Expr` Source carrier。该切片先固定
  statement tag `3`、optional type marker、双前端 parity 与 Typed exact fail-closed boundary；不吸收
  local binding/type/effect、SemanticIR 或 target semantics。
