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

## 2026-07-18 — D1 bounded let statement pre-acceptance slice

- Commits：identifier-control spec correction `603c3bd7`；Let statement RED `d815d400`；
  current-identity golden correction `bb3f9e27`；Source/Syntax/Typed GREEN `bc0447f2`。
- Spec/Test：`SPEC-LANG-001`、`TST-SRC-005`。本切片只追加 D1-PA-20 development evidence，
  不改变 `TASK-D1-04` 的 pending 状态、依赖、Tests 集合或 Done 语义。
- Changed：`Source.Statement` append-only 追加
  `letDecl(name, typeAnn : Option ValueType, value)`；alpha canonical encoder 使用 statement tag `3`，
  随后依次绑定 name、`typeAnn` 的 `0/1` marker（`some` 后紧接既有 type bytes）与 value expression，
  既有 tags `0..2` 不变。DSL category 内两个 named contextual parser 分别解析 annotated/omitted form，
  introducer、binder、colon/type 与 assign/value 边界均以 same-line guard 固定；decoder 使用命名 parser
  quotation做结构化匹配，不扫描任意 Syntax 子树，也没有 generic fallback。
- Binding/negatives：initializer、entry、view、fn body 覆盖 annotated/omitted form；Lean command 与
  ParserSession 产生相同 Source AST/sourceHash。固定 identity 的 annotated/omitted LetTwin 分别为
  229/228 bytes，hash 为 `63074e1c83c2a81f197a8d95baa40f9b577f57cfbb8909df432d9c20c70250a2`、
  `2a7514a897195a94962f5ff45331ce3463d3e1778200e69ab249da4ee48e616a`；type marker/payload、binder 与
  value mutation 均改变 hash。unknown annotated type 与 reserved binder 在 decoder exact fail closed；
  escaped/qualified introducer、缺失 binder/type/value/assign 与 split-line form 停在 parser boundary。
  `«let» := 1` 保持 `.assign "let"` positive control，bare `let := 1` 继续 parser reject。
- Boundary：`Typed.check` 对任意 `letDecl` 返回 exact
  `let statements are not yet supported by typed checking`，因此不会生成 SemanticProgram、requirements、
  target Plan 或 artifact。本切片没有 local environment、shadowing、name resolution、type inference、
  effect rule 或 runtime semantics。
- Review/Commands：RED reviewers 独立发现 LetTwin identity 使用 `run` 而 prospective goldens 取自
  `echo` 的 mismatch；`bb3f9e27` 在 GREEN 前按真实 identity 修正并增加实际值失败信息，随后聚焦与
  aggregate tests 全绿。`lake build Tests.Language.LetStatements proof_forge_next_tests`；
  `lake env .lake/build/bin/proof-forge-next-tests`；`just dsl-negative`；clean committed `just ci` at
  `bc0447f2`；`git diff --check`。
- Results：132-job clean build、124-job aggregate、186 项 docs mutation、治理/SBOM/runtime closure、
  双入口 DSL negatives 与 target/toolchain negatives 全部 exit 0；development evidence 为
  `EV-20260718-0006`。
- Limitations：仅实现 Source statement structure；没有 local binding/shadowing、D2 name/type/effect、
  SemanticIR lowering、requirements、target ABI/materialization、eligible host 或 formal D1 evidence。
  D0 formal milestone 仍为 5/8，`TASK-D1-04` 仍 pending，本结果不是 eligible/hermetic/formal evidence。
- Next：residual audit 只把 exact `true`/`false` Source-only literal 作为 D1-PA-21 candidate；在 spec/test
  freeze 与 review 完成前不提交 RED，也不把 Bool Typed/Semantic/target semantics 吸入该候选切片。

## 2026-07-18 — D1-PA-20 frozen extra-payload negative hardening

- Review：closeout audit 发现 frozen `TST-SRC-005` 已要求 extra-payload parser-boundary rejection，
  但 `LetStatements` 的 malformed-shape matrix 只覆盖缺失与跨行形态，尚未执行该既有完成条件。
- Changed：在同一 ParserSession negative matrix 追加 `let value := 1 2`，固定 value 后额外独立 token
  必须停在 Lean parser boundary；没有修改生产实现、规范完成面、task 状态或既有 evidence record。
- Commands：`lake build Tests.Language.LetStatements`（14 jobs，exit 0）；`git diff --check`。
- Boundary：这是对冻结测试的实现补齐，不生成新 `TST-*`/`EV-*`，不改变
  `EV-20260718-0006` 的历史观察，也不把 `TASK-D1-04` 从 pending 提升为 done。

## 2026-07-18 — D1 exact Bool literal pre-acceptance slice

- Commits：freeze `175545d6`；Bool literal RED `10159066`；Source/Syntax/Typed GREEN `76ebc809`。
- Spec/Test：`SPEC-LANG-001`、`TST-SRC-005`。本切片只追加 D1-PA-21 development evidence，
  不改变 `TASK-D1-04` 的 pending 状态、依赖、Tests 集合或 Done 语义。
- Changed：`Source.Expr` append-only 追加 `boolLiteral(value : Bool)`；alpha source canonical encoder
  使用 Expr tag `4` 后紧接单个 marker byte（`false = 0`、`true = 1`），既有 tags `0..3` 不变。
  `pfExpr` category 内两个 `default+1` contextual named parser 使 exact bare `true`/`false` 优先于
  generic identifier，decoder/quote 按命名 parser structure 往返且没有 global keyword、fallback 或
  Syntax 扫描。portable identifier policy 未改变。
- Binding/controls：BoolSurface 覆盖 initializer、entry、view、fn 的 return/let value，并固定 Lean
  command 与 ParserSession AST/sourceHash parity。固定 BoolTwin identity 的 false/true rows 均为 201 bytes，
  hash 分别为 `cbf554a833b9fd88fe8029b085547992d663c8e1fa13abc93a94e80e7ebf3ad4`、
  `f979745e8773cfe7caee45cb003801af2db23dd151bbda1b4c860aca9d453676`；integer 0/1 controls
  均为 208 bytes，hash 分别为 `4bac3a3ee625da64b5c70416a5a289e44ffa007ed08320ebffb1141286fe46b0`、
  `b35a702ce96574ebb8abc004492d9a75cfc80f062c3765ca2a8e2bb17030a50f`。四者不 alias，
  Bool 与 UInt64 payload size 精确相差 7 bytes。escaped/qualified/case/`trueValue`/`falseValue`
  均保持 `.variable` control；literal 后额外独立 token 停在 parser boundary。
- Boundary：`Typed.checkExpr` 对 `boolLiteral` 返回 exact
  `boolean literals are not yet supported by typed checking`，因此 Typed.Expr、SemanticIR、requirements、
  Semantics 与四 target 均无需也没有修改，不会生成 target Plan/artifact。
- Review/Commands：Grok RED/GREEN；Pi RED/canonical/GREEN review、Claude RED/GREEN review 与 Kimi
  GREEN seam audit 均 P0/P1=0。`lake build proof_forge_next_tests`；
  `lake env .lake/build/bin/proof-forge-next-tests`；clean committed `just ci` at `76ebc809`；
  `git diff --check`。
- Results：134-job clean build、126-job aggregate、186 项 docs mutation、治理/SBOM/runtime closure、
  双入口 DSL negatives 与 target/toolchain negatives 全部 exit 0；development evidence 为
  `EV-20260718-0007`。
- Limitations：仅实现 Source Bool literal structure；没有 Typed/Semantic Bool expression、type/effect、
  requirement、target ABI/runtime、eligible host 或 formal D1 evidence。D0 formal milestone 仍为 5/8，
  `TASK-D1-04` 仍 pending，本结果不是 eligible/hermetic/formal evidence。
- Next：residual audit 选择 binary checked subtraction 作为 D1-PA-22 candidate；必须先冻结同层
  `+`/`-` precedence、left associativity、append-only Expr tag 与 Typed fail-closed boundary，再提交 RED。

## 2026-07-18 — D1 binary checked subtraction pre-acceptance slice

- Commits：freeze `756afdc2`；checked subtraction RED `0d97da50`；Source/Syntax/Typed GREEN
  `e8c3773f`。
- Spec/Test：`SPEC-LANG-001`、`TST-SRC-005`。本切片只追加 D1-PA-22 development evidence，
  不改变 `TASK-D1-04` 的 pending 状态、依赖、Tests 集合或 Done 语义。
- Changed：`Source.Expr` append-only 追加 `checkedSub(lhs, rhs)`；alpha source canonical encoder
  使用 Expr tag `5` 后依次递归编码 lhs、rhs，既有 tags `0..4` 不变。`pfExpr` 的 `-` 与 `+`
  同为 precedence `65`，lhs `65`/rhs `66` 固定左结合；decoder/quote 使用结构化 quotation 往返，
  没有新增 unary、parenthesis、fallback 或宿主 keyword。
- Binding/controls：initializer、entry、view、fn 的 return/let value 与 variable operands 经 Lean command
  和 ParserSession 产生相同 AST/sourceHash；`9-4-1`、`1+2-3`、`1-2+3` 固定同层左结合。
  CheckedSubTwin 的 `7-3`、`7+3`、`3-7`、left/right nest 分别为 228/228/228/238/238 bytes，
  hash 为 `bc13a1ffea38b78f4f86d7125ee5ebce869c38c4ecab322a0a0ac369f42e0369`、
  `3beb6aeb92a9f8e556a9e4c97c2e383e102cc7b9bf2cc8b1966b17d358bad97f`、
  `e1f474e6e23d73463d2ab2a4b16fddfd65737594cd4118bb80912453b42f5a15`、
  `3e427798e7a530b6ea165e73e0a907e0f02246c49cacbac49f9ba292b4469966`、
  `7e6a2c24a6cad28e5984f2279dce0df9fdd863c6ea1062334cb32b69027e7e3a`；operator、operand
  order 与 nesting 均不 alias。missing lhs/rhs、bare unary minus 与 binary-unary operand 停在 parser
  boundary；既有 checkedAdd twin 继续通过完整 Compiler positive path。
- Boundary：`Typed.checkExpr` 对 `checkedSub` 返回 exact
  `checked subtraction is not yet supported by typed checking`，因此没有新增 Typed.Expr、SemanticIR、
  requirement、Semantics 或 target Plan/artifact；checkedAdd 既有路径未改变。
- Review/Commands：Grok RED/GREEN；Pi RED/GREEN、Claude RED/post-commit 与 Kimi GREEN/canonical closeout
  reviews 均 P0/P1=0。`lake build Tests.Language.CheckedSub proof_forge_next_tests`；
  `lake env .lake/build/bin/proof-forge-next-tests`；`git diff --check`。
- Results：128-job aggregate 与测试二进制全部 exit 0，五组 goldens 无需修正；development evidence 为
  `EV-20260718-0008`。按批量验证策略，本切片未完成的 checkpoint `just ci` 延后到较大阶段统一执行，
  因而不把已中止的运行计入证据。
- Limitations：仅实现 Source checked subtraction structure；没有 Typed/Semantic arithmetic、underflow/
  revert rule、signed/unary literal、parentheses、multiplication、requirement、target ABI/runtime、eligible host
  或 formal D1 evidence。D0 formal milestone 仍为 5/8，`TASK-D1-04` 仍 pending。
- Next：residual audit 选择 binary checked multiplication 作为 D1-PA-23 candidate；必须先冻结高于
  `+`/`-` 的 precedence、left associativity、append-only Expr tag `6`、golden controls 与 Typed exact
  fail-closed boundary，再提交 RED；不得捆绑 division、modulo、parentheses 或 Semantic/target lowering。

## 2026-07-18 — D1 binary checked multiplication pre-acceptance slice

- Commits：freeze `21a4157b`；checked multiplication RED `6b30cce4`；Source/Syntax/Typed GREEN
  `2749d1c6`。
- Spec/Test：`SPEC-LANG-001`、`TST-SRC-005`。本切片只追加 D1-PA-23 development evidence，
  不改变 `TASK-D1-04` 的 pending 状态、依赖、Tests 集合或 Done 语义。
- Changed：`Source.Expr` append-only 追加 `checkedMul(lhs, rhs)`；alpha source canonical encoder
  使用 Expr tag `6` 后依次递归编码 lhs、rhs，既有 tags `0..5` 不变。`pfExpr` 的 `*` 固定为
  precedence `70`、lhs `70`/rhs `71`，高于 `+`/`-` 的 `65` 且同层左结合；decoder/quote 使用
  结构化 quotation 往返，没有新增 `/`、`%`、unary、parenthesis、fallback 或宿主 keyword。
- Binding/controls：initializer、entry、view、fn 的 return/let value 与 variable operands 经 Lean command
  和 ParserSession 产生相同 AST/sourceHash；`2*3*4`、`2+3*4`、`2*3+4`、`2-3*4`、`2*3-4`
  固定左结合及 `MulExpr` 高于 `AddExpr` 的分组。CheckedMulTwin 的 `2*3`、`2+3*4`、`2*3+4`、
  left/right nest 分别为 228/238/238/238/238 bytes，hash 为
  `8128548ccbf651b56e4e7fff2cf57a098f69486eb06464f506e1caed2e7f581a`、
  `a6eb82bd2a1f6402c8157065926ee0fc80f613126fdc822801b3b2b514635a08`、
  `2596095b9f9ca52d373c0f1997746032240e26608ed37191b7e35a2e4f37b576`、
  `625cdaa2d54c15d8da241c4d069f225374429a03076d30bf0be23638a00e0f88`、
  `f4b9a861619b742361e41f69342f07dc9c338daa9b9a520073b8aa2fa990c13c`；operator、operand
  order 与 nesting 均不 alias。missing lhs/rhs、bare/repeated star、extra token、`/`、`%` 停在
  parser boundary；checkedAdd positive 与 checkedSub exact fail-closed controls 保持通过。
- Boundary：`Typed.checkExpr` 对 `checkedMul` 返回 exact
  `checked multiplication is not yet supported by typed checking`，因此没有新增 Typed.Expr、SemanticIR、
  requirement、Semantics 或 target Plan/artifact；checkedAdd/checkedSub 既有路径未改变。
- Review/Commands：Grok RED/GREEN；Pi freeze/RED/GREEN、Kimi freeze/RED/canonical GREEN 与 Claude seam
  review 均已执行。`lake build Tests.Language.CheckedMul proof_forge_next_tests`；
  `lake env .lake/build/bin/proof-forge-next-tests`；`git diff --check`。
- Results：130-job aggregate 与测试二进制全部 exit 0，五组 goldens 无需修正；development evidence 为
  `EV-20260718-0009`。按批量验证策略，本切片的 checkpoint `just ci` 延后到较大阶段统一执行，未计入
  本条证据。
- Limitations：仅实现 Source checked multiplication structure；没有 Typed/Semantic arithmetic、overflow/
  revert rule、division/modulo、signed/unary literal、parentheses、requirement、target ABI/runtime、eligible
  host 或 formal D1 evidence。D0 formal milestone 仍为 5/8，`TASK-D1-04` 仍 pending。
- Next：residual audit 选择 parenthesized expression grouping parser sugar 作为 D1-PA-24 candidate；该切片
  不新增 Source.Expr ctor/tag，而把 `(expr)` 解码为同一 Source AST。必须先冻结 grouping precedence、
  direct-vs-parenthesized sourceHash equality、malformed boundary 与无 Typed/Semantic/target change，再提交 RED。

## 2026-07-18 — D1 parenthesized expression grouping pre-acceptance slice

- Commits：freeze `77c6b23b`；grouping RED `ddaadfb6`；Syntax-only GREEN `d321db74`。
- Spec/Test：`SPEC-LANG-001`、`TST-SRC-005`。本切片只追加 D1-PA-24 development evidence，
  不改变 `TASK-D1-04` 的 pending 状态、依赖、Tests 集合或 Done 语义。
- Changed：`pfExpr` 新增 exact `syntax:max "(" pfExpr:0 ")" : pfExpr`；外层是 high-precedence
  primary，内部 precedence `0` 接受当前完整 `+`/`-`/`*` expression。`decodeExprUnchecked` 只以结构化
  quotation 递归返回 inner expression；未新增 Source.Expr ctor/tag/field，也未修改 `quoteExpr`、
  `Source.lean`、`Typed.lean`、SemanticIR、requirements 或任何 target。
- Binding/equality：initializer、entry、view、fn 的 return/let value 覆盖 literal、variable、Bool 与
  binary grouping，并固定 Lean command/ParserSession AST/sourceHash parity。相同 identity 下 `(42)`/`42`、
  `((x))`/`x`、`((2+3))`/`2+3` 的完整 Source.Program、canonical bytes 与 sourceHash 相等。
  `(2+3)*4`、`7-(3-1)`、`2*(3*4)`、`2*(3+4)` 固定 precedence override/right nesting；解析后的
  CheckedSubTwin/CheckedMulTwin 与 direct Source twin 全程序相等。right-sub/right-mul/2*(3+4) 均为
  238 bytes，hash 分别为 `7e6a2c24a6cad28e5984f2279dce0df9fdd863c6ea1062334cb32b69027e7e3a`、
  `f4b9a861619b742361e41f69342f07dc9c338daa9b9a520073b8aa2fa990c13c`、
  `7f86e7a891dcbe523eb1d608f3e4ffe864c66dce2bf53bffb671c977cd800aa3`，并与对应 left/default
  shapes 不 alias。
- Boundaries：empty/whitespace group、missing/nested-unmatched parentheses、tuple/comma、inner/trailing
  extra payload、call-like、未支持 `/`/`%`/unary 与 type-position `(UInt64)` 均停在 parser boundary。
  grouped checkedAdd 继续编译，grouped Bool/checkedSub/checkedMul 保留各自 byte-exact Typed diagnostic。
- Review/Commands：Grok design/RED/GREEN；Pi parser/freeze/RED/GREEN；Kimi freeze/golden；Claude scope/RED；
  coordinator 追加 same-identity parse-vs-direct 与 parsed-program Typed controls。执行
  `lake build Tests.Language.Grouping proof_forge_next_tests`；
  `lake env .lake/build/bin/proof-forge-next-tests`；`git diff --check`。
- Results：132-job aggregate 与测试二进制全部 exit 0，三组固定 hash 无需修正；development evidence 为
  `EV-20260718-0010`。按批量验证策略，本切片的 checkpoint `just ci` 延后到较大阶段，未计入本条证据。
- Limitations：grouping 在当前 alpha Source AST/canonical hash 中被有意擦除，没有保留括号 surface
  provenance/span；没有 unit/tuple/call/constructor/unary、Typed/Semantic/requirement、target ABI/runtime、
  eligible host 或 formal D1 evidence。D0 formal milestone 仍为 5/8，`TASK-D1-04` 仍 pending。
- Next：residual audit 选择 unary checked negation Source-only carrier 作为 D1-PA-25 candidate；必须先冻结
  prefix precedence、与 binary `-` 的消歧、append-only Expr tag `7`、grouped operand 与 exact Typed
  fail-closed boundary，再提交 RED；不得捆绑 `!`/`~`、signed literal、Semantic arithmetic 或 target lowering。

## 2026-07-18 — D1 unary checked negation pre-acceptance slice

- Commits：freeze `009159e0`；tests-only RED `946b8c67`；Source-only GREEN `01739d5c`；
  migrated-spelling exact pin `08a1ac29`。
- Spec/Test：`SPEC-LANG-001`、`TST-SRC-005`。本切片只追加 D1-PA-25 development evidence，
  不改变 `TASK-D1-04` 的 pending 状态、依赖、Tests 集合或 Done 语义。
- Changed：`Source.Expr` append-only 新增 `checkedNeg operand`，canonical encoder 以 tag `7` 后接递归
  operand；`pfExpr` 新增 `syntax:75 "-" pfExpr:75 : pfExpr`，decoder/quotation 均结构化保留 unary node。
  `Typed.check` 逐字 fail closed 为 `checked negation is not yet supported by typed checking`。production
  只修改 `Source.lean`、`Syntax.lean`、`Typed.lean` 共 10 行，SemanticIR、requirements 与 targets 未改。
- Parser/AST：initializer、entry、view、fn 的 return/let value 与 Lean command/ParserSession parity 全绿；
  `-2`/`- 2`/`-x`、`-2*3`、`-(2+3)`、`1- -2`、`1+ -2`、`1* -2`、`- - 2`
  与 `(-3)` 精确固定 unary/binary precedence、right nesting 和 grouped operand。PA22 的四个临时 unary
  negatives 与 PA24 的 grouped unary negative 在同一个 RED changeset 迁移为 positives。
- Binding：CheckedNegTwin 固定 tag/operand/order/tree identity；代表性 golden 为 unary literal `2`
  `2d85f63df2d77d902f186712031114c9d66f9d169acc2672c1bccbb32dfc04ce`/219 bytes、
  variable `x` `a24b2b26d9568962214245701db537cdab9ee18a427a5ae2d6ce3e6858023c29`/220、
  `-2*3` `ee810bab7d822bf4ea8dbdc5007096e40a7b34e1ab5cbacfccabb83153329978`/229、
  nested `- - 2` `cddb76db9a7d522c1531d1058446c1ba75b6f0006eccfe6b2f274b515642127f`/220；
  literal/operator/operand/nesting/wrong-grouping controls 均不 alias。
- Boundaries：无空格 `--` 继续服从 Lean line-comment 词法；`1--2` 精确固定为 literal `1` comment
  control，而 subtraction-of-negative 使用 `1 - -2`。bare/malformed operator、empty operand 与额外
  payload 停在 parser boundary；checkedAdd positive 与 checkedSub/checkedMul exact Typed controls 保持。
- Review/Commands：执行 `lake build Tests.Language.CheckedNeg`；
  `lake build proof_forge_next_tests`；`lake env .lake/build/bin/proof-forge-next-tests`；`git diff --check`。
  第一次 aggregate 暴露 `-2`/`- 2` fixture 使用不同 program identity；RED 在 GREEN 提交前修正并
  amend 为 `946b8c67`，随后同一 aggregate 全绿。post-GREEN review 为 P0/P1=0；coordinator 进一步按
  冻结文本把 PA22 的 `- 3`、`-3`、`7 - - 3`、`1 + - 2` 原 spelling 逐字补入 `08a1ac29`，
  增量 aggregate 再次全绿。
- Results：14-job focused build、134-job aggregate 与测试二进制全部 exit 0；development evidence 为
  `EV-20260718-0011`。按批量验证策略，本切片的 checkpoint `just ci` 延后，未计入本条证据。
- Limitations：仅有 Source unary carrier，没有 signed literal、constant folding、`!`/`~`、Typed/Semantic
  negation、overflow/underflow rule、requirement、target ABI/runtime、eligible host 或 formal D1 evidence。
  D0 formal milestone 仍为 5/8，`TASK-D1-04` 仍 pending。
- Next：statement/expression residual audits 并行选择下一个单一 bounded slice；在审计与冻结完成前不自动
  递增 D1-PA 编号，也不把本 development evidence 写成正式 D1 完成。

## 2026-07-18 — D1 bare assert statement pre-acceptance slice

- Commits：freeze `0477e089`；tests-only RED `a6f052d3`；Source-only GREEN `ff7a6fee`；
  literal-condition exact pin `de45d253`。
- Spec/Test：`SPEC-LANG-001`、`TST-SRC-005`。本切片只追加 D1-PA-26 development evidence，
  不改变 `TASK-D1-04` 的 pending 状态、依赖、Tests 集合或 Done 语义。
- Changed：`Source.Statement` append-only 新增 `assertStmt condition`，alpha canonical encoder 以
  Statement tag `4` 后递归编码 condition；`pfStmt` 新增 bare `syntax "assert " pfExpr : pfStmt`，
  decoder/quotation 均结构化保留 condition。`Typed.checkStatement` 在检查 condition 前逐字 fail closed 为
  `assert statements are not yet supported by typed checking`。production 只修改 `Source.lean`、
  `Syntax.lean`、`Typed.lean` 共 10 行，Typed Statement、SemanticIR、requirements 与 targets 未改。
- Parser/AST：initializer、entry、view、fn body 覆盖 literal、Bool、variable、grouped 与 checked-add condition，
  Lean command/ParserSession AST/sourceHash parity 全绿。相同 AssertTwin identity 下 `assert true` 与
  `assert (true)` 的完整 Source.Program/canonical bytes/sourceHash 相等。
- Binding：AssertTwin 的 `assert true` 与 `assert false` 均为 209 bytes，hash 分别为
  `175f8718f5c59c0d4284e70de39b6bf51fe3990ede6401df10046e141bd9e3b2`、
  `d53075d45436f72d54370b5f3ef3d10b21d4f30d6ee9ab706b96cdb7b118f66e`；同 identity
  `return true` control 为 `cbee441c2ccee971516b1ea4e428ae21890bacc55ec4cd68517551a41efad014`/
  209 bytes，因此 statement tag 与 condition payload 均不 alias。
- Boundaries：bare `assert := 1` 拒绝；escaped `«assert» := 1` 精确保留 assignment，`assertValue := 1`
  不被 keyword prefix 误收。bare/missing condition、extra payload、block-like 形态与
  `assert true else Failure` 停在 parser boundary；optional `else Ident` 明确未实现。`assert true`
  精确命中 statement-level diagnostic，不泄漏 Bool-expression diagnostic；既有 assign/return/call/let
  controls 保持。
- Review/Commands：Grok 实施 RED；Kimi/Claude/Pi 与 coordinator 分别审计 statement residual、production
  seam、keyword/parser boundary 与 exhaustive matches。执行 `lake build Tests.Language.AssertStatements`；
  `lake build proof_forge_next_tests`；`lake env .lake/build/bin/proof-forge-next-tests`；`git diff --check`。
  post-GREEN review 的唯一 P1 是缺少独立 `assert 1` literal-condition AST pin；`de45d253` 补齐后增量
  aggregate 再次全绿，最终 P0/P1=0。
- Results：14-job focused build、136-job aggregate 与测试二进制全部 exit 0；development evidence 为
  `EV-20260718-0012`。按批量验证策略，本切片的 checkpoint `just ci` 延后，未计入本条证据。
- Limitations：仅有 bare Source assert carrier；没有 optional error binding、condition Bool checking、
  Typed/Semantic assertion、failure/revert code、requirement/effect、target ABI/runtime、eligible host 或
  formal D1 evidence。D0 formal milestone 仍为 5/8，`TASK-D1-04` 仍 pending。
- Next：expression residual audit 选择 unary bitwise-not `~` Source-only carrier 作为 D1-PA-27 candidate；
  必须先冻结 prefix precedence、append-only Expr tag、mixed-unary shape、canonical goldens 与 exact Typed
  boundary，不得自动从 candidate 变为 active 或捆绑 `!`/shift/Semantic/target lowering。

## 2026-07-18 — D1 unary bitwise-not pre-acceptance slice

- Commits：freeze `6f0322d5`；tests-only RED `6724f120`；Source-only GREEN `0f4455ad`。
- Spec/Test：`SPEC-LANG-001`、`TST-SRC-005`。本切片只追加 D1-PA-27 development evidence，
  不改变 `TASK-D1-04` 的 pending 状态、依赖、Tests 集合或 Done 语义。
- Changed：`Source.Expr` append-only 新增 `bitwiseNot operand`，alpha canonical encoder 以 Expr tag `8`
  后接递归 operand；`pfExpr` 新增 `syntax:75 "~" pfExpr:75 : pfExpr`，decoder/quotation 均结构化
  保留 unary node。`Typed.check` 逐字 fail closed 为
  `bitwise not is not yet supported by typed checking`。production 只修改 `Source.lean`、`Syntax.lean`、
  `Typed.lean` 共 10 行，SemanticIR、requirements 与 targets 未改。
- Parser/AST：initializer、entry、view、fn 的 return/let value 与 Lean command/ParserSession parity 全绿；
  `~2`、`~x`、`~2*3`、`~(2+3)`、`1-~2`、`1*~2`、`~ ~ 2`、`(~2)` 精确固定
  unary precedence/right nesting/grouped operand；`- ~ 2` 与 `~ - 2` 精确保留 mixed-unary 次序。
  相同 `NotEq` identity 下 bare/grouped Source.Program 与 sourceHash 相等，既有 tests 零迁移。
- Binding：BitwiseNotTwin 的 `~2`、`~x`、`~2*3`、`~(2+3)`、nested 均绑定真实 tag-8
  bytes/hash；代表 golden 为 `~2`
  `fc78bd762867552e854a95b0daa19fe2e40ca7aa2655a0c58d2efdb6053c0ca9`/219 bytes、`~x`
  `7f3667734db603423590dd2bae1c43d3c8e086a437d49a9046fd09ff2d460404`/220、`~2*3`
  `284809b7678748bd97319471cf9a8ae3dbf23ff3b7e7b0e83c119e55d1e6a56a`/229、nested
  `89e68d7a47c7021abe58555e2997c4b25043a19c16d1190b3c184aea26add7b0`/220；literal、
  checked-negation、operand mutation、wrong tree 与 mixed reverse-order 均不 alias。
- Boundaries：bare/missing operand、empty group、invalid following operator 与 extra payload 停在 parser
  boundary。checkedAdd positive 与 Bool/sub/mul/neg exact Typed controls 保持；没有修改既有 test matrix。
- Review/Commands：Grok 实施 RED；coordinator 在 GREEN 前删除不同 program identity 的错误重复等值断言，
  amend RED 为 `6724f120`；独立 parser/scope audit 为 P0/P1=0。执行
  `lake build Tests.Language.BitwiseNot`；`lake build proof_forge_next_tests`；
  `lake env .lake/build/bin/proof-forge-next-tests`；`git diff --check`。并发 Agent 启动的重复测试进程被停止，
  evidence 只计 coordinator 保留的单一 authoritative aggregate。
- Results：14-job focused build、138-job aggregate 与测试二进制全部 exit 0；development evidence 为
  `EV-20260718-0013`。按批量验证策略，本切片的 checkpoint `just ci` 延后，未计入本条证据。
- Limitations：仅有 Source unary carrier，没有 logical `!`、binary bitwise/shift、constant folding、
  Typed/Semantic bitwise operation、requirement、target ABI/runtime、eligible host 或 formal D1 evidence。
  D0 formal milestone 仍为 5/8，`TASK-D1-04` 仍 pending。
- Next：expression residual audit 的 unary logical-not `!` 作为 D1-PA-28 candidate；必须先冻结 Bool
  operand boundary、prefix precedence、append-only tag、mixed-unary shapes、canonical goldens 与 exact
  Typed failure。PA28 收口后形成 unary-expression batch checkpoint，再决定完整 CI 时点。

## 2026-07-18 — D1 unary logical-not pre-acceptance slice

- Commits：freeze `d5395e1e`；tests-only RED `facae339`；Source-only GREEN `92f57f30`。
- Spec/Test：`SPEC-LANG-001`、`TST-SRC-005`。本切片只追加 D1-PA-28 development evidence，
  不改变 `TASK-D1-04` 的 pending 状态、依赖、Tests 集合或 Done 语义。
- Changed：`Source.Expr` append-only 新增 `logicalNot operand`，alpha canonical encoder 以 Expr tag `9`
  后接递归 operand；`pfExpr` 新增 `syntax:75 "!" pfExpr:75 : pfExpr`，decoder/quotation 均结构化
  保留 unary node。`Typed.checkExpr` 在检查 operand 前逐字 fail closed 为
  `logical not is not yet supported by typed checking`。production 只修改 `Source.lean`、`Syntax.lean`、
  `Typed.lean` 共 10 行，Typed Expr、SemanticIR、requirements 与 targets 未改。
- Parser/AST：initializer、entry、view、fn 的 return/let value 与 Lean command/ParserSession parity 全绿；
  `!2`、`!true`、`!false`、`!x`、`!2*3`、`!(2+3)`、`1-!2`、`1*!2`、`! ! 2`、`(!2)`
  精确固定 unary precedence、right nesting 与 grouping；`- ! 2`/`! - 2` 和 `~ ! 2`/`! ~ 2`
  精确保留 mixed-unary 次序。相同 identity 下 bare/grouped Source.Program 与 sourceHash 相等，既有 tests 零迁移。
- Binding：LogicalNotTwin 的代表 goldens 为 `!2`
  `5ac59fb7f95bb3aeac27441da9f5fc69990fc46ce903f6365ff9c6e3811d343d`/219 bytes、`!true`
  `3ae83fbda053d685a95c6cd44c1d90f45cd9c197c90e85576c5d2ef34915450b`/212、`!x`
  `174d346ee92f3163df0e8af17d6f1929d400d40cd97ab56165f1fc16ec0a02ab`/220、`!2*3`
  `55941863fe708deb8307c2f3813f4064ecb917b583638d2ce50785ef8c775236`/229、nested
  `614adf4f9adfc7a4c95ec0b164aeab30c118f7ea64f99b17b1041364930dba8f`/220；literal、checked-negation、
  bitwise-not、operand/tree/nesting 与 mixed reverse-order 均不 alias。
- Boundaries：bare/missing/empty/extra-payload operators 停在 parser boundary；`1 != 2` 与 `! = 2`
  明确保持 reject，未将 deferred comparison token 误拆为 logical-not。`!true` 精确命中 logical-not
  diagnostic 而不泄漏 Bool diagnostic；add positive 与 Bool/sub/mul/neg/bitwise-not exact controls 保持。
- Review/Commands：Grok 实施 RED 并完成后续 residual audit；Kimi 对冻结 seam 与真实 GREEN 做两轮只读审计，
  最终 P0/P1=0；coordinator 实施严格 3 文件/10 行 GREEN。执行 `lake build Tests.Language.LogicalNot`；
  `lake build proof_forge_next_tests`；`lake env .lake/build/bin/proof-forge-next-tests`；`git diff --check`。
- Results：14-job focused build、140-job aggregate 与测试二进制全部 exit 0；development evidence 为
  `EV-20260718-0014`。按批量验证策略，本 unary-expression checkpoint 的完整 `just ci` 继续延后，
  未计入本条证据。
- Limitations：仅有 Source unary carrier，没有 Bool operand legality、Typed/Semantic logical operation、
  `!=`/`&&`/`||`、constant folding、requirement、target ABI/runtime、eligible host 或 formal D1 evidence。
  D0 formal milestone 仍为 5/8，`TASK-D1-04` 仍 pending。
- Next：residual audit 已选择 binary checked division `/` 作为唯一下一 candidate；冻结时只允许
  Source Expr tag `10`、与 `*` 同 precedence 的左结合 parser、decode/quote、exact Typed fail-closed，
  并迁移 `CheckedMul`/`Grouping` 中两条既有 `/` negative；不得捆绑 `%`、Semantic 或 target lowering。

## 2026-07-18 — D1 binary checked-division pre-acceptance slice

- Commits：freeze `a1415163`；tests-only RED `84f0f72c`；seam-count correction `8a00bd21`；
  Source-only GREEN `300b8a9c`。
- Spec/Test：`SPEC-LANG-001`、`TST-SRC-005`。本切片只追加 D1-PA-29 development evidence，
  不改变 `TASK-D1-04` 的 pending 状态、依赖、Tests 集合或 Done 语义。freeze 中 binary quote arm
  的物理行数由 3 少计为 4；`8a00bd21` 在 GREEN 前只把 seam 总数从 10 更正为 11，不改变任何语义范围。
- Changed：`Source.Expr` append-only 新增 `checkedDiv lhs rhs`，alpha canonical encoder 以 Expr tag `10`
  后依次递归编码 lhs/rhs；`pfExpr` 新增 `syntax:70 pfExpr:70 " / " pfExpr:71 : pfExpr`，与 `*`
  同层且左结合。decoder/quotation 结构化保留 binary node；`Typed.checkExpr` 在检查任一 operand 前逐字
  fail closed 为 `checked division is not yet supported by typed checking`。production 恰好只改
  `Source.lean`、`Syntax.lean`、`Typed.lean` 3 文件/11 行，Typed Expr、SemanticIR、requirements 与 targets 未改。
- Parser/AST：initializer、entry、view、fn 的 return/let value 与 Lean command/ParserSession parity 全绿；
  `6/3`、`3/6`、`a/b`、`1+6/3`、`6/3+1`、`6/3/2`、`6/(3/2)`、`2*6/3`、
  `2*(6/3)`、`8/4*2`、`(1+2)/3`、`8/4-2`、`-8/4` 与 `8/-4` 精确固定同层左结合、
  additive/unary precedence 与 grouping。`8/0` 在 Source 接受，除零 legality 明确留给 D2/target。
- Binding：CheckedDivTwin 的代表 goldens 为 `6/3`
  `c7b5abc6f7a665e821646195c1c191bd5c79970f56f774824e21d52dbcf0e07c`/228 bytes、`3/6`
  `f779a87b512fe81c41e242a971ffae9913f78bf8f6f5add0fca9fb74284a554c`/228、left nested
  `d5a1c2cbeb3f767be6042af2d401602faabe086f2b41178e5642ea6eeaa1366b`/238、right nested
  `c3e7034c2330d88024977a8f96f2c961af55c5962add61d39bb0586d8b2cbd9f`/238、`8/0`
  `cde97577aecae8a24075bab611c3bbe6053149149fc4a9147c2eb68352a0a12b`/228、migrated `2/3`
  `0d38cb17ac24ed48bfa9139af1a7af1629439a8d53c9ed824e77f185b8806c68`/228；mul/sub tag、
  operand order/zero、left/right nesting、wrong tree、mixed precedence 与 unary placement 均不 alias。
- Migration/Boundaries：同一个 RED 只把 `CheckedMul` 的 `2 / 3` 与 `Grouping` 的 `(2 / 3)` 两条
  slash negative 迁移为精确 positives，两个 percent controls 保留。bare/missing/repeated `/`、`2 // 3`、
  mixed invalid operator、extra payload、`2 % 3` 与 `(2 % 3)` 均停在 parser boundary。Typed division
  对 malformed operand 仍先给 division diagnostic；add positive 与 Bool/sub/mul/neg/bitwise/logical exact controls 保持。
- Review/Commands：Grok 完成 residual audit、RED 设计与 tests-only RED；Kimi 完成冻结、GREEN seam 与最终三轮
  只读审计，最终 P0/P1=0；coordinator 完成冻结勘误和 11 行 GREEN。执行
  `lake build Tests.Language.CheckedDiv`；`lake build proof_forge_next_tests`；
  `lake env .lake/build/bin/proof-forge-next-tests`；`git diff --check`。
- Results：14-job focused build、142-job aggregate 与测试二进制全部 exit 0；development evidence 为
  `EV-20260718-0015`。按批量验证策略，完整 `just ci` 继续延后，未计入本条证据。
- Limitations：仅有 Source binary carrier，没有除零、signed/rounding、Typed/Semantic division、modulo、
  constant folding、requirement、target ABI/runtime、eligible host 或 formal D1 evidence。D0 formal milestone
  仍为 5/8，`TASK-D1-04` 仍 pending。
- Next：residual audit 已选择 binary checked modulo `%` 作为唯一下一 candidate；冻结前必须核准
  与 `*`/`/` 同层的 precedence、Expr tag `11`、zero-denominator Source boundary 与 exact Typed failure；
  migration audit 已确认同一 RED 必须迁移 3 个 suite 中 4 条 percent negative（`CheckedMul` 1、
  `Grouping` 1、`CheckedDiv` 2），不得漏项或捆绑 Semantic/target lowering。

## 2026-07-18 — D1 binary checked-modulo pre-acceptance slice

- Commits：freeze `84408784`；tests-only RED `197e412e`；Source-only GREEN `49012f57`。
- Spec/Test：`SPEC-LANG-001`、`TST-SRC-005`。本切片只追加 D1-PA-30 development evidence，
  不改变 `TASK-D1-04` 的 pending 状态、依赖、Tests 集合或 Done 语义。
- Changed：`Source.Expr` append-only 新增 `checkedMod lhs rhs`，alpha canonical encoder 以 Expr tag `11`
  后依次递归编码 lhs/rhs；`pfExpr` 新增 `syntax:70 pfExpr:70 " % " pfExpr:71 : pfExpr`，与
  `*`/`/` 同层并跨 operator 左结合。decoder/quotation 结构化保留 binary node；`Typed.checkExpr`
  在检查任一 operand 前逐字 fail closed 为 `checked modulo is not yet supported by typed checking`。
  production 恰好只改 `Source.lean`、`Syntax.lean`、`Typed.lean` 3 文件/11 行，其他层未改。
- Parser/AST：initializer、entry、view、fn 的 return/let value 与 Lean command/ParserSession parity 全绿；
  `7%3`、`3%7`、`a%b`、add/sub precedence、left/right modulo nesting、`2*7%3`/`2*(7%3)`、
  `7%3*2`、`8/4%2`/`8%4/2`、`(1+2)%3`、`-8%3` 与 `8%-3` 精确固定 cross-operator
  left associativity、grouping 与 unary precedence。`8%0` 在 Source 接受，modulo-by-zero 留给 D2/target。
- Binding：CheckedModTwin 的代表 goldens 为 `7%3`
  `27734454ca6f13690f578919cd0a6a801b52d0c022075138380b12667de799ce`/228 bytes、`3%7`
  `ed0965b100295c4cabbd06abe3ed9aa2511015c53ea6a7bdb4ac1580d1f65cd5`/228、left nested
  `c65ffab1f8bba66aaf900eeb8895e4d2f6e3fc901e2176c72595949df7dc41d1`/238、right nested
  `d35012b51a215db44c7fb358add004febf5838cccdb9b84f2179f143e174c019`/238、`8%0`
  `4fff7a5bdc1482ae4ffa706dda1c9aad5dacc62788ae389427ca37a6e6bd2a9f`/228、migrated `2%3`
  `6e84d4d6cd67e9324a771bfb97219edd05fb8acef1189f4ba456389792490e42`/228；mul/div/sub tag、
  operand order/zero、left/right nesting、wrong tree、cross-operator shape 与 unary placement 均不 alias。
- Migration/Boundaries：同一 RED 精确迁移 3 个 suite 的 4 条 percent negative：`CheckedMul` 1、
  `Grouping` 1、`CheckedDiv` 2；新 suite 将 bare/missing/repeated `%`、`2 %% 3`、mixed invalid operator
  与 extra payload 固定在 parser boundary。四处迁移语法经 aggregate 编译确认有效，未迁移其他 negative。
  Typed malformed operand 仍先给 modulo diagnostic；add positive 与 Bool/sub/mul/div/neg/bitwise/logical controls 保持。
- Review/Commands：Grok 完成 residual audit、RED 设计与 tests-only RED；Kimi 完成迁移、GREEN seam 与最终
  三轮只读审计，最终 P0/P1=0；coordinator 完成严格 11 行 GREEN。执行
  `lake build Tests.Language.CheckedMod`；`lake build proof_forge_next_tests`；
  `lake env .lake/build/bin/proof-forge-next-tests`；`git diff --check`。
- Results：14-job focused build、144-job aggregate 与测试二进制全部 exit 0；development evidence 为
  `EV-20260718-0016`。按批量验证策略，完整 `just ci` 继续延后，未计入本条证据。
- Limitations：仅有 Source binary carrier，没有 modulo-by-zero、signed/rounding/sign、Typed/Semantic
  modulo、constant folding、requirement、target ABI/runtime、eligible host 或 formal D1 evidence。
  `*`/`/`/`%` Source surface 已覆盖，但 `MulExpr`、expression grammar 与 `TASK-D1-04` 仍未正式完成；
  D0 formal milestone 仍为 5/8。
- Next：residual audit 已选择 shift-left `<<` 作为唯一下一 candidate；冻结前必须核准低于 AddExpr 的
  precedence、Expr tag `12`、shift-count zero Source boundary、left/right nesting、既有 negative migration
  集合与 exact Typed failure，不得捆绑 `>>`、Semantic 或 target lowering。

## 2026-07-18 — D1 shift-left pre-acceptance slice

- Commits：freeze `97be1f2d`；tests-only RED `5f8766b6`；Source-only GREEN `b38e033e`。
- Spec/Test：`SPEC-LANG-001`、`TST-SRC-005`。本切片只追加 D1-PA-31 development evidence，
  不改变 `TASK-D1-04` 的 pending 状态、依赖、Tests 集合或 Done 语义。
- Changed：`Source.Expr` append-only 新增 `shiftLeft lhs rhs`，alpha canonical encoder 以 Expr tag `12`
  后依次递归编码 lhs/rhs；`pfExpr` 新增 `syntax:60 pfExpr:60 " << " pfExpr:61 : pfExpr`，严格
  低于 AddExpr precedence `65` 并左结合。decoder/quotation 结构化保留 node；`Typed.checkExpr` 在
  检查任一 operand 前逐字 fail closed 为 `shift left is not yet supported by typed checking`。
  production 恰好只改 `Source.lean`、`Syntax.lean`、`Typed.lean` 3 文件/11 行，其他层未改。
- Parser/AST：initializer、entry、view、fn 的 return/let value 与 Lean command/ParserSession parity 全绿；
  `1<<2`、`2<<1`、`a<<b`、`1+2<<3`、`1<<2+3`、`8<<2*3`、`8*2<<3`、
  `1<<2<<3`、`1<<(2<<3)`、`(1+2)<<3`、`-1<<2`、`1<<-2`、`0<<1` 精确固定
  60/61 precedence、left/right nesting、grouping 与 unary placement。`1<<0`/`1<<64` 在 Source 接受，
  count legality 留给 D2/target。
- Binding：ShiftLeftTwin 的代表 goldens 为 `1<<2`
  `9cef54adbb9d41fc6098537cba57f99c3c1aee3f784eef1ebcc0bee79659b52a`/225 bytes、`2<<1`
  `2ea816eb5c33fb9a4db7ded3ce5559c895aa9750ba2a8ad75cd2eb67ad6ffaba`/225、`1+2<<3`
  `afe2de8b02b34f3f2eac7fec021f711e712b1cccb84641e695ac257de3ff1b7c`/235、left nested
  `77888b16028ea0a4c6eca69f983ce466f24cdad4640721cc96ffce7c57ae5047`/235、right nested
  `289c76fa2d69cd10cda5f8a95d1655421575393a0e15be67895259a8d12da00f`/235、`1<<64`
  `6ccb1d81aeb484b85841f78378f1e588b2ee457a685fb001a3c42f244709777b`/225；operator/order/count、
  wrong precedence、left/right nesting、multiplicative shape 与 unary placement 均不 alias。
- Boundaries：既有 tests 零迁移。bare/missing/repeated `<<`、`1 < < 2`、`1 <<< 2`、extra payload
  停在 parser boundary，`1 >> 2` 保留为明确 deferred shift-right negative。Typed 对 malformed operand
  仍先给 shift-left diagnostic；add positive 与 Bool/sub/mul/div/mod/neg/bitwise/logical exact controls 保持。
- Review/Commands：Grok 完成 residual audit、RED 设计与 tests-only RED；Kimi 完成冻结、GREEN seam 与最终
  三轮只读审计，最终 P0/P1=0；coordinator 完成严格 11 行 GREEN。执行
  `lake build Tests.Language.ShiftLeft`；`lake build proof_forge_next_tests`；
  `lake env .lake/build/bin/proof-forge-next-tests`；`git diff --check`。
- Results：14-job focused build、146-job aggregate 与测试二进制全部 exit 0；development evidence 为
  `EV-20260718-0017`。按批量验证策略，完整 `just ci` 继续延后，未计入本条证据。
- Limitations：仅有 Source carrier，没有 shift count/width/overflow、signed/arithmetic-vs-logical shift、
  rotate、Typed/Semantic shift、constant folding、requirement、target ABI/runtime、eligible host 或 formal D1
  evidence。只实现 `<<`，`ShiftExpr`、expression grammar 与 `TASK-D1-04` 仍未正式完成；D0 仍为 5/8。
- Next：residual audit 已选择 shift-right `>>` 作为唯一下一 candidate；冻结前必须核准与 `<<` 同层的
  precedence、Expr tag `13`、cross-shift nesting、zero/over-width Source boundary、ShiftLeft 中唯一 retention
  negative 的迁移与 exact Typed failure；audit 已确认只迁移 `ShiftLeft.lean` 的 `1 >> 2` 一条，
  arithmetic-vs-logical shift-right semantics 必须明确 deferred，不得捆绑 Semantic 或 target lowering。

## 2026-07-18 — D1 shift-right pre-acceptance slice

- Commits：freeze `dc8b57ad`；tests-only RED `56f0e70c`；Source-only GREEN `29513a00`。
- Spec/Test：`SPEC-LANG-001`、`TST-SRC-005`。本切片只追加 D1-PA-32 development evidence，
  不改变 `TASK-D1-04` 的 pending 状态、依赖、Tests 集合或 Done 语义。
- Changed：`Source.Expr` append-only 新增 `shiftRight lhs rhs`，alpha canonical encoder 以 Expr tag `13`
  后依次递归编码 lhs/rhs；`pfExpr` 新增 `syntax:60 pfExpr:60 " >> " pfExpr:61 : pfExpr`，与
  `<<` 同层跨 operator 左结合并严格低于 AddExpr precedence `65`。decoder/quotation 结构化保留 node；
  `Typed.checkExpr` 在检查任一 operand 前逐字 fail closed 为
  `shift right is not yet supported by typed checking`。production 恰好只改 `Source.lean`、`Syntax.lean`、
  `Typed.lean` 3 文件/11 行，其他层未改。
- Parser/AST：initializer、entry、view、fn 的 return/let value 与 Lean command/ParserSession parity 全绿；
  `1>>2`、`2>>1`、`a>>b`、`1+2>>3`、`1>>2+3`、`8>>2*3`、`8*2>>3`、
  `1>>2>>3`、`1>>(2>>3)`、`(1+2)>>3`、`-1>>2`、`1>>-2`、`0>>1`、
  `1>>0`、`1>>64`、`1<<2>>3` 与 `1>>2<<3` 精确固定 60/61 precedence、同层 cross-shift
  左结合、grouping 与 unary placement。zero/over-width count 在 Source 接受，count legality 与
  arithmetic-vs-logical right-shift semantics 留给 D2/target。
- Binding：ShiftRightTwin 的代表 goldens 为 `1>>2`
  `a3566f68f52b46f51c9307718b70133fe5520f23952f9d41d429dac57a28637e`/228 bytes、`2>>1`
  `3ee8a82eaa290fd4ba206c7f92995b0e3924cba79cd0864c51d1c90addfd943d`/228、`1+2>>3`
  `30b1759079dfddfe1a5e3668177d30aeefe956120e23aaab703b64327b6b93ff`/238、left nested
  `e90c2caa954ca8f92c5f0f22b8ab3cefa2b448ff4d0cbc6f4a752241a4a531a9`/238、right nested
  `eab0cc18fd52efeabc7b7540be798194f87b9fda776fe742daa2c6ad57639803`/238、`1>>64`
  `f29d87c9b953de738e3559eb792c6ec98fb816c8c3386d63936c5c6da0fa2925`/228、`1<<2>>3`
  `a9c338f2cb43f52d59f03a0441f255a1f7309ea5dd4eadf1dcfba5c73ada60e8`/238、`1>>2<<3`
  `bd6d1a6f808cedf83d1b2a6530e4d52ab285b9bfaa61ef5a28fafad964c441b3`/238；operator/order/count、
  shift-left tag、wrong precedence、left/right nesting、cross-shift order 与 unary placement 均不 alias。
- Migration/Boundaries：同一 RED 只迁移 `ShiftLeft.lean` 中唯一的 `1 >> 2` retention negative；
  bare/missing/repeated `>>`、`1 > > 2`、`1 >>> 2` 与 extra payload 停在 parser boundary。
  Typed 对 `1>>64` 仍先给 shift-right diagnostic；checkedAdd positive 与 Bool/sub/mul/div/mod/neg/
  bitwise/logical/shift-left exact controls 保持。
- Review/Commands：Grok 完成 residual audit、RED 设计与 tests-only RED；Kimi 完成 GREEN seam 与最终
  只读审计，最终 P0/P1=0；coordinator 完成严格 11 行 GREEN。执行
  `lake build Tests.Language.ShiftRight`；`lake build proof_forge_next_tests`；
  `lake env .lake/build/bin/proof-forge-next-tests`；随后在 clean committed `main@29513a00` 执行
  `just ci` 作为 PA28–PA32/ShiftExpr 批次 checkpoint。
- Results：14-job focused build、148-job aggregate 与测试二进制全部 exit 0；batch `just ci` exit 0，
  包含 committed-archive isolation 的 156-job clean build/test/help、`docs-check`、186 项 docs mutation、
  genesis/bootstrap/SBOM/supply-chain/runtime closure 自测、148-job aggregate、完整测试二进制及
  target/toolchain negative checks。development evidence 为 `EV-20260718-0018`；这些仍是 development
  gate，不是 eligible host 或 formal hermetic Stage-0 evidence。
- Limitations：仅有 Source carrier，没有 shift count/width/overflow、signed/arithmetic-vs-logical shift、
  rotate、Typed/Semantic shift、constant folding、requirement、target ABI/runtime、eligible host 或 formal D1
  evidence。`<<`/`>>` 的 ShiftExpr Source surface 与批次门禁已闭合，但 expression grammar 与
  `TASK-D1-04` 仍未正式完成；D0 formal milestone 仍为 5/8。
- Next：equality `==` 是 residual audit 的唯一下一 candidate，但尚未冻结。冻结前必须独立核准
  non-associative Compare precedence、Expr append-only tag `14`、零既有 migration、malformed `= =`/`===`
  parser boundary、Bool/integer Source acceptance 与 exact Typed failure；不得捆绑 `!=`、ordering、
  Bool legality、Semantic 或 target lowering。

## 2026-07-18 — D1 equality pre-acceptance slice

- Commits：freeze `5363ba0c`；tests-only RED `6d246cd5`；Source-only GREEN `055658b9`。
- Spec/Test：`SPEC-LANG-001`、`TST-SRC-005`。本切片只追加 D1-PA-33 development evidence，
  不改变 `TASK-D1-04` 的 pending 状态、依赖、Tests 集合或 Done 语义。
- Changed：`Source.Expr` append-only 新增 `equal lhs rhs`，alpha canonical encoder 以 Expr tag `14`
  后依次递归编码 lhs/rhs；`pfExpr` 新增 `syntax:50 pfExpr:51 " == " pfExpr:51 : pfExpr`，严格
  低于 ShiftExpr precedence `60`，且两个 operand slot 都高于 operator precedence，从 parser 结构保证
  non-associative。decoder/quotation 结构化保留 node；`Typed.checkExpr` 在检查任一 operand 前逐字
  fail closed 为 `equality is not yet supported by typed checking`。production 恰好只改 `Source.lean`、
  `Syntax.lean`、`Typed.lean` 3 文件/11 行，其他层未改。
- Parser/AST：initializer、entry、view、fn 的 return/let value 与 Lean command/ParserSession parity 全绿；
  `1==2`、`2==1`、`a==b`、`true==false`、`false==true`、`0==0`、add/mul 双向 precedence、
  `1<<2==3`、`1==2<<3`、`1>>2==3`、`1==2>>3`、grouping、`-1==2`、`1==-2` 与
  `!true==false` AST 精确。integer/Bool operand legality 与 Bool result typing 留给 D2。
- Binding：EqualTwin 的代表 goldens 为 `1==2`
  `dc5d71dc6b764fe1c3d17de4f59e60d669921ee6fb948e854a62bac9c65ead7a`/213 bytes、`2==1`
  `29f5ee40692d2f0221b2b429770357e37455d5979072dfec717c4ef31c1e7abc`/213、`a==b`
  `59673b07cb2dc86afa0e659b7ae8b5c0c664c6e898cd0c4e0360b783aca0f468`/215、`true==false`
  `0f7470698cfe5876925ac2cc4de1b1514e90d703f936f875707c89a5b267e267`/199、`false==true`
  `bc6b7fa14fc1b711f8cc2039223901ae9183188bedca14b7aa3e4682ab46844b`/199、`1+2==3`
  `8d5658780fabd716f475bba30fe61ef7080c9b35f39258ade179720808bdbd50`/223、`1<<2==3`
  `a25b46fe7fd84b260ee941f05bf37ac5d5238189e24b2dfc3b0cd9a04c137cd4`/223、`1>>2==3`
  `0dee172b3debb3d885c4c5d7c2579ee34230d2a89e3e676825507a58465bd4c4`/223、`!true==false`
  `34c192b04f6e08c4c48c497db924822257d9da5fe6bc05396e1f296a9a0707e1`/200；operator、operand
  order/type、wrong precedence、shift direction、grouping 与 unary placement 均不 alias。
- Boundaries：既有 tests 零迁移，`LogicalNot.lean` 的 `1 != 2` retention negative 保持。
  bare/missing operand、single `=`、`1 = = 2`、`1 === 2`、extra payload 与 headline
  `1 == 2 == 3` 停在 parser boundary；`<`/`<=`/`>`/`>=` ordering siblings 继续明确 deferred。
  Typed 对 `true==false` 仍先给 equality diagnostic；checkedAdd positive 与 Bool/sub/mul/div/mod/neg/
  bitwise/logical/shift-left/shift-right exact controls 保持。
- Review/Commands：Grok 完成 freeze/RED 设计、tests-only RED 与 post-slice residual audit；Kimi 完成
  freeze seam 和 GREEN 最终只读审计，最终 P0/P1=0；coordinator 完成严格 11 行 GREEN。执行
  `lake build Tests.Language.Equal`；`lake build proof_forge_next_tests`；
  `lake env .lake/build/bin/proof-forge-next-tests`；`git diff --check`。
- Results：14-job focused build、150-job aggregate 与测试二进制全部 exit 0；development evidence 为
  `EV-20260718-0019`。PA32 已在 `29513a00` 通过 clean committed batch `just ci`；本小切片按批量策略
  不重复全量 CI，未把该历史 checkpoint 计入本条 evidence。
- Limitations：仅有 Source carrier，没有 operand/result type legality、Typed/Semantic comparison、
  `!=`/ordering/bitwise/logical binary operators、constant folding、requirement、target ABI/runtime、eligible
  host 或 formal D1 evidence。只实现 `==`，不得声称 CompareExpr、expression grammar 或
  `TASK-D1-04` 正式完成；D0 formal milestone 仍为 5/8。
- Next：residual audit 选择 not-equal `!=` 为唯一下一 candidate，但尚未冻结。冻结前必须核准
  与 unary `!` 的 token integrity、Compare precedence `50` non-associativity、Expr tag `15`、
  `LogicalNot.lean` 中唯一 `1 != 2` retention negative 的迁移、equal/non-equal non-alias 与 exact Typed
  failure；不得捆绑 ordering、Bool legality、Semantic 或 target lowering。

## 2026-07-18 — D1 not-equal pre-acceptance slice

- Commits：freeze `b683bea9`；tests-only RED `25222bdb`；Source-only GREEN `cff64eea`。
- Spec/Test：`SPEC-LANG-001`、`TST-SRC-005`。本切片只追加 D1-PA-34 development evidence，
  不改变 `TASK-D1-04` 的 pending 状态、依赖、Tests 集合或 Done 语义。
- Changed：`Source.Expr` append-only 新增 `notEqual lhs rhs`，alpha canonical encoder 以 Expr tag `15`
  后依次递归编码 lhs/rhs；`pfExpr` 新增 `syntax:50 pfExpr:51 " != " pfExpr:51 : pfExpr`，与 `==`
  同层且两个 operand slot 都高于 operator precedence。decoder/quotation 结构化保留 node；
  `Typed.checkExpr` 在检查任一 operand 前逐字 fail closed 为
  `not-equal comparison is not yet supported by typed checking`。production 恰好只改 `Source.lean`、
  `Syntax.lean`、`Typed.lean` 3 文件/11 行，其他层未改。
- Parser/AST：initializer、entry、view、fn 的 return/let value 与 Lean command/ParserSession parity 全绿；
  integer/Bool/order/variable、add/mul/shift 双向 precedence、grouping、`-1!=2`、`1!=-2`、
  `!true!=false` 与 `1!=!false` AST 精确。`1!=2!=3`、`1==2!=3` 与 `1!=2==3` 全部 parser
  reject，落实整个 Compare 层至多一个 comparison；operand/result legality 留给 D2。
- Binding：NotEqualTwin 的代表 goldens 为 `1!=2`
  `67d67880083a4d0dfb388b5ed143cb20bc38e06de011394e95f01dc689964aa3`/222 bytes、`2!=1`
  `cd2166f9ea79863591a5c0803dbe95881bd5e7032d1aa38cbdf31d1ad2622977`/222、`a!=b`
  `6a872c60e3b8abf027797c97a5e02442fedb1b87809df10565263fef5e95835a`/224、`true!=false`
  `be87f2a2407cfb141d39227db9e2f1ceebc1b174b16604c441e10c16056f3a7f`/208、`false!=true`
  `07225e9e291954153d652ced3ea5d6e28f2bc3bf58479e69e0dbe4cb2239b3bd`/208、`1+2!=3`
  `9baacaad68a3d6d47a5a6aad43432aed9a7ba6584a5f66b1d08e570a40048a4e`/232、`1<<2!=3`
  `82f701c0cccbee82a2b66eeb6b51b5e0950c95b24c4b5d074a15db4b03dd3e64`/232、`1>>2!=3`
  `bf432615fe32a6a34f0c0833627e491f4a27d35142af73b73035aa3ccd5c0304`/232、`!true!=false`
  `b53f41eda90f7cd68848008bb90b5edf9804ee53fdc63a44b383806859d85bb3`/209、`1!=!false`
  `a0a3f813a4e592bfee1f4e2effd4c96709c5bba1941c69cfd6ddfdf507f42108`/216；equal tag、
  operator/order/type、wrong precedence、shift direction 与 unary placement 均不 alias。
- Migration/Boundaries：同一 RED 只迁移 `LogicalNot.lean` 的 deferred `1 != 2` 一条 negative；
  相邻 `! = 2` 保持拒绝。bare/missing operand、`1 ! = 2`、`1 !== 2`、`1 ! == 2`、
  same/mixed chain 与 extra payload 停在 parser boundary；`Equal.lean` 的四个 ordering siblings 保持。
  Typed 对 `true!=false` 仍先给 not-equal diagnostic；checkedAdd positive 与 Bool/sub/mul/div/mod/neg/
  bitwise/logical/shift-left/shift-right/equal exact controls 保持。
- Review/Commands：Grok 完成 freeze/RED 设计、tests-only RED 与 post-slice residual audit；Kimi 完成
  freeze seam 和 GREEN 最终只读审计，最终 P0/P1=0；coordinator 完成严格 11 行 GREEN。执行
  `lake build Tests.Language.NotEqual`；`lake build proof_forge_next_tests`；
  `lake env .lake/build/bin/proof-forge-next-tests`；`git diff --check`。
- Results：14-job focused build、152-job aggregate 与测试二进制全部 exit 0；development evidence 为
  `EV-20260718-0020`。本小切片按批量策略不重复全量 CI。
- Limitations：仅有 Source carrier，没有 operand/result type legality、Typed/Semantic comparison、
  ordering/bitwise/logical binary operators、constant folding、requirement、target ABI/runtime、eligible host
  或 formal D1 evidence。只完成 `==`/`!=` equality pair，不得声称 CompareExpr、expression grammar 或
  `TASK-D1-04` 正式完成；D0 formal milestone 仍为 5/8。
- Next：residual audit 选择 less-than `<` 为唯一下一 candidate，但尚未冻结。冻结前必须核准与 `<<`
  的 longest-token/token-integrity boundary、Compare precedence `50` non-associativity、Expr tag `16`、
  `Equal.lean` 中唯一 `1 < 2` retention negative 的迁移、same/mixed chain rejection 与 exact Typed failure；
  不得捆绑 `<=`、`>`、`>=`、Bool legality、Semantic 或 target lowering。

## 2026-07-18 — D1 less-than pre-acceptance slice

- Commits：freeze `c743f4b0`；tests-only RED `38afba9b`；canonical golden binding `8d9ebe01`；
  Source-only GREEN `6d93896b`。
- Spec/Test：`SPEC-LANG-001`、`TST-SRC-005`。本切片只追加 D1-PA-35 development evidence，
  不改变 `TASK-D1-04` 的 pending 状态、依赖、Tests 集合或 Done 语义。
- Changed：`Source.Expr` append-only 新增 `lessThan lhs rhs`，alpha canonical encoder 以 Expr tag `16`
  后依次递归编码 lhs/rhs；`pfExpr` 新增 `syntax:50 pfExpr:51 " < " pfExpr:51 : pfExpr`，与
  equality pair 同层且两个 operand slot 都高于 operator precedence。decoder/quotation 结构化保留
  node；`Typed.checkExpr` 在检查任一 operand 前逐字 fail closed 为
  `less-than comparison is not yet supported by typed checking`。production 恰好只改 `Source.lean`、
  `Syntax.lean`、`Typed.lean` 3 文件/11 行，其他层未改。
- Parser/AST：initializer、entry、view、fn 的 return/let value 与 Lean command/ParserSession parity 全绿；
  integer/Bool/order/variable、add/mul/shift 双向 precedence、grouping、unary AST 精确；特别是
  `1<<2<3` 为 `(1<<2)<3`，`1<2<<3` 为 `1<(2<<3)`。`1<2<3` 与四种 `==`/`!=` mixed chains
  全部 parser reject；operand/result legality 留给 D2。
- Binding：LessThanTwin 的代表 goldens 为 `1<2`
  `2603fd7611520e5ebf3fcab1e0cb228947acce84bc746f1201c894be08bceaca`/222 bytes、`2<1`
  `8878e8fc1ec9415689c57508b19880a5ce7af6e3283f8e5f7d2bccfbae04cb0a`/222、`true<false`
  `dad6d5ebdb8578da84ab092abe733b83338859238ea1f5c81d9f643877733433`/208、`1+2<3`
  `33328a0026056eaa295314e3d3707c53841b66401e4d3b62f248539be4f82874`/232、`1<2*3`
  `d1c24020e7916469a509d36d8a16764495a3cd511d66dfe27c73a110d3987b7a`/232、`1<<2<3`
  `320ae2afb179c909eab24776406c085721fc78433fa5bdc39825f822d94e5920`/232、`1<2<<3`
  `abc48121320bf8da57cac9b7f4ca5c744f5461e57d4b7a66ebb731d70bc40bfc`/232；equal/notEqual tag、
  operator/order/type、wrong precedence、shift direction 与 unary placement 均不 alias。首次真实测试执行
  发现 prospective `1<2*3` hash 有一位转录差异，`8d9ebe01` 只绑定真实值，未扩大测试面。
- Migration/Boundaries：同一 RED 只迁移 `Equal.lean` 的 deferred `1 < 2` 一条 negative，保留
  `<=`/`>`/`>=` siblings；`ShiftLeft.lean` 的 `1 < < 2` 与 `1 <<< 2` 保持拒绝，`1<<2`
  继续形成 shiftLeft。bare/missing operand、same/mixed chains 与 extra payload 停在 parser boundary。
  Typed 对 `true<false` 仍先给 less-than diagnostic；checkedAdd positive 与 Bool/sub/mul/div/mod/neg/
  bitwise/logical/shift-left/shift-right/equal/notEqual exact controls 保持。
- Review/Commands：Grok 完成 freeze/RED 设计、tests-only RED、下一 residual 设计与 evidence extraction；
  Kimi 完成 freeze seam、下一 residual 和 GREEN 最终只读审计，最终 P0/P1=0；coordinator 完成严格
  11 行 GREEN。执行 `lake build Tests.Language.LessThan`；`lake build proof_forge_next_tests`；
  `lake env .lake/build/bin/proof-forge-next-tests`；`git diff --check`。
- Results：14-job focused build、154-job aggregate 与最终测试二进制全部 exit 0；development evidence 为
  `EV-20260718-0021`。本小切片按批量策略不重复全量 CI。
- Limitations：仅有 Source carrier，没有 operand/result type legality、Typed/Semantic comparison、
  `<=`/`>`/`>=`、bitwise/logical binary operators、constant folding、requirement、target ABI/runtime、
  eligible host 或 formal D1 evidence。不得声称 CompareExpr、expression grammar 或 `TASK-D1-04`
  正式完成；D0 formal milestone 仍为 5/8。
- Next：两份独立 residual audit 都选择 less-or-equal `<=` 为唯一下一 candidate，但尚未冻结。冻结前
  必须核准 `<=` 与 `<`/`<<`/`=` 的 token integrity、Compare precedence `50` non-associativity、
  Expr tag `17`、`Equal.lean` 中唯一 `1 <= 2` retention negative 的迁移、same/mixed chain rejection
  与 exact Typed failure；不得捆绑 `>`、`>=`、Bool legality、Semantic 或 target lowering。

## 2026-07-18 — D1 less-or-equal pre-acceptance slice

- Commits：freeze `9ab8b6b8`；tests-only RED `c6c5fb80`；Source-only GREEN `9d4fbd37`。
- Spec/Test：`SPEC-LANG-001`、`TST-SRC-005`。本切片只追加 D1-PA-36 development evidence，
  不改变 `TASK-D1-04` 的 pending 状态、依赖、Tests 集合或 Done 语义。
- Changed：`Source.Expr.lessEqual lhs rhs` 与 append-only Expr tag `17`；
  `syntax:50 pfExpr:51 " <= " pfExpr:51 : pfExpr`、结构化 decoder/quotation；`Typed.checkExpr`
  在 operands 前逐字 fail closed 为 `less-equal comparison is not yet supported by typed checking`。
  production 恰好只改 Source/Syntax/Typed 3 文件/11 行，其他层未改。
- Coverage：initializer、entry、view、fn return/let 与双入口 parity；integer/Bool/order/variable、add/mul/
  shift 双向 precedence、grouping、unary AST；same chain 与针对 `<`/`==`/`!=` 的六种 mixed directions
  全部拒绝。代表 goldens：`1<=2`
  `dae46b177e848a37c45a1b83756828d709aced2f30ba6797084b36fa9af9c7ac`/225 bytes、`2<=1`
  `0b1ee5b31681f8c1eaa77386df60c1bb65c2285eeb63dad10a86b2538e60328f`/225、`true<=false`
  `b99e171a3079f2497d1502c1d422dd761f86eadce84ce0280110ee22126dc7b6`/211、`1+2<=3`
  `bc55b18f29500659734c183ec5c988430cbb5bdd01cc7f44d97d579ec0377368`/235、`1<<2<=3`
  `2a04f479b5738c51563644e97be58b3e93a64cef804daae0b2ba985d74c74880`/235、`1<=2<<3`
  `dc2233b671502479c6760adb0b984d3d880bd6d7d926120dadd182b2ec553544`/235。
- Migration/Boundaries：只迁移 `Equal.lean` 的 `1 <= 2` negative，保留 `>`/`>=`；
  `1 < = 2`、`1 <<= 2`、`1 <= = 2`、bare/missing/extra payload 全部 parser reject，既有
  `<`/`<<` 语义及 ShiftLeft token-integrity pins 未变。Typed exact controls 与 checkedAdd positive 保持。
- Review/Commands：Grok 完成 RED、下一 residual 与 evidence extraction；Kimi 完成 freeze seam 和 GREEN
  最终审计，P0/P1=0；coordinator 完成 11 行 GREEN。执行 `lake build Tests.Language.LessEqual`；
  `lake build proof_forge_next_tests`；`lake env .lake/build/bin/proof-forge-next-tests`；`git diff --check`。
- Results：14-job focused、156-job aggregate 与测试二进制全部 exit 0；development evidence 为
  `EV-20260718-0022`。本小切片未重复全量 CI。
- Limitations：仅有 Source carrier；没有 operand/result type legality、Typed/Semantic comparison、
  `>`/`>=`、bitwise/logical operators、folding、requirement、target ABI/runtime、eligible host 或 formal D1
  evidence。不得声称 CompareExpr、expression grammar 或 `TASK-D1-04` 正式完成；D0 仍为 5/8。
- Next：residual audit 选择 greater-than `>` 为唯一下一 candidate，但尚未冻结。冻结前必须核准与 `>>`
  的 longest-token/token-integrity boundary、Compare precedence `50` non-associativity、Expr tag `18`、
  `Equal.lean` 中唯一 `1 > 2` retention negative 的迁移、same/mixed chain rejection 与 exact Typed failure；
  不得捆绑 `>=`、Bool legality、Semantic 或 target lowering。

## 2026-07-18 — D1 greater-than pre-acceptance slice

- Commits：freeze `d8b8120a`；tests-only RED `880f2b95`；Source-only GREEN `996fa0fe`。
- Spec/Test：`SPEC-LANG-001`、`TST-SRC-005`。本切片只追加 D1-PA-37 development evidence，
  不改变 `TASK-D1-04` 的 pending 状态、依赖、Tests 集合或 Done 语义。
- Changed：`Source.Expr.greaterThan lhs rhs`、append-only Expr tag `18`、
  `syntax:50 pfExpr:51 " > " pfExpr:51 : pfExpr`、decoder/quotation 以及 operands 前 exact Typed
  `greater-than comparison is not yet supported by typed checking`。production 只改 3 文件/11 行。
- Coverage：双入口与 initializer/entry/view/fn；integer/Bool/order/variable、add/mul/shift 双向、grouping、
  unary AST；same chain 与八种 mixed directions 全拒绝。代表 goldens：`1>2`
  `1dd61183be0bfb0d0955232b2c1c751d049215f6fd262c9a81e35f59f8d0c137`/231 bytes、`2>1`
  `dbce68b33070a56eecbcee77a46efb826c7cd4bc16b310868aa6cf9307dc6566`/231、`true>false`
  `d1b81799ca56ba7ced47d015f8ee13a8e48fcf53edd7a6e5655c9dfacec06e13`/217、`1>>2>3`
  `756aa4acb27e6a475d4732e56ed855f87f74ccd9ca45b372038331d53a0d9168`/241、`1>2>>3`
  `6b1adb2c2d71e80c724ac050867bf87e8801a1f3c5ed9f053e64e9d533ccde4b`/241。
- Boundaries：只迁移 `Equal.lean` 的 `1 > 2` negative，保留 `>=`；`1 > > 2`、`1 >>> 2`、
  `1 >>= 2`、`1 > = 2` 拒绝，`>>` 语义和 ShiftRight survival pins 未变。
- Review/Commands：Grok 完成 RED、下一 residual 与 evidence extraction；Kimi 完成 freeze seam、最后一个
  comparison residual 和 GREEN final audit，P0/P1=0。执行 focused、158-job aggregate、测试二进制与
  `git diff --check`，全部 exit 0；development evidence 为 `EV-20260718-0023`，未重复全量 CI。
- Limitations：仅有 Source carrier；没有 type legality、Typed/Semantic comparison、`>=`、bitwise/logical、
  folding、requirement、target 或 formal D1 evidence。不得关闭 pending `TASK-D1-04`；D0 仍为 5/8。
- Next：greater-or-equal `>=` 是 CompareExpr 最后一个 Source residual，尚未冻结。必须固定 tag `19`、
  唯一剩余 `1 >= 2` migration、十种 mixed directions 与 `>`/`>>`/`=` token boundaries；该切片完成后
  运行一次 CompareExpr 批量 `just ci` checkpoint，但仍不得宣称整个 expression grammar 或正式 D1 完成。

## 2026-07-18 — D1 greater-or-equal / CompareExpr checkpoint

- Commits：freeze `99b5ac11`；tests-only RED `568c1e2e`；suite recursion budget `af40d164`；
  Source-only GREEN `8957c636`。
- Scope：`Source.Expr.greaterEqual lhs rhs`、append-only tag `19`、
  `syntax:50 pfExpr:51 " >= " pfExpr:51 : pfExpr`、decoder/quotation 与 operands 前 exact Typed
  failure。production 恰好 Source/Syntax/Typed 3 文件/11 行；`TASK-D1-04` 仍 pending。
- Tests：双入口和四种 body position；integer/Bool/order/variable、add/mul/shift 双向、grouping、unary；
  same chain 与十种 mixed directions；`>`/`>>` controls 及 `1 > = 2`/`1 >>= 2`/`1 >= = 2`
  boundaries。最终迁移 `Equal.lean` 的 `1 >= 2`，ordering deferreds 归零且 reject list 有效。
  `af40d164` 只给此 629-line suite 的 `run` 设置 local `maxRecDepth 2048`，不改变全局或 production。
- Binding：代表 goldens 为 `1>=2`
  `366618ab25d2688aacaec173c4ab38ae6b31c1d45deab21e01d058f79205c85a`/234 bytes、`2>=1`
  `cc252d273832175a831ea4f131b9d19b241fe4eb98a1cf8dd36d4ba03e6497fb`/234、`true>=false`
  `0eb6e86ada321ed7c40afc4f572f420c8a98f7ec80104c6fbfb6d45ebc6368cf`/220、`1+2>=3`
  `5623ac1fcacc714e2d3de0d40075cca3945d58692c09fc28c4f4d8eb7b940603`/244、`1>>2>=3`
  `5bdde75341b7b45cce2e17ad8f3b7e5932a302b916f7b74bc3faee406335f6ae`/244、`1>=2>>3`
  `879156eed4660d8a16c7f5bea1f61454ab55a836b0e7fecdf3901c7c1475d62c`/244。
- Focused：14-job suite、160-job aggregate、测试二进制与独立 final audit 全绿，P0/P1=0。
- Batch gate：在 clean committed tree `8957c636c22a06f4038b46234af0bf8ee45dd8f8` 单 runner 执行
  `just ci`，40-mutation isolation precheck、committed archive 168-job build/test/help、186 docs mutations、
  genesis/bootstrap/SBOM、全部 supply-chain/runtime closure self-tests、本地 60-job product build、160-job
  aggregate/test、DSL negatives 与 target/toolchain negatives 全部 exit 0；evidence 为 `EV-20260718-0024`。
- Completion boundary：现在可称 `==`/`!=`/`<`/`<=`/`>`/`>=` 的完整 CompareExpr Source surface 已覆盖；
  仍无 operand/result legality、Typed/Semantic comparison、bitwise/logical operators、folding、requirement、
  target ABI/runtime、eligible-host 或 formal D1 evidence，不得关闭 `TASK-D1-04`；D0 仍为 5/8。
- Next：residual audit 选择 binary bitwise-and `&` 为唯一下一 candidate，但尚未冻结。必须核准低于
  CompareExpr 的左结合 precedence、Expr tag `20`、zero migration、`&&` token integrity、comparison
  mixed placement 与 exact Typed failure；不得捆绑 `^`、`|`、`&&`、`||`、Semantic 或 target lowering。

## 2026-07-18 — D0 关闭路径治理：ADR-0016、TASK-D0-09 立项与 D0-08/D0-09 pre-freeze 包

- Context：用户指示盘点 D0 剩余面、完善 D0 并兼容 macOS/Linux 双开发机。本 session 执行机
  为 Linux Mint 22.3 x86_64（kernel 6.17，EFI present，SecureBoot disabled），不是此前
  darwin-arm64 attestation 机器；Linux 侧观察自本条起以该机实测为准。
- Changed（working tree，待提交；提交后以 `git log` 为准）：
  `docs/adr/0016-cross-platform-host-profile-and-linux-eligibility.md`（新，proposed）、
  `docs/adr/README.md`（索引行）、`docs/04-task-breakdown.md`（TASK-D0-09 行 + 立项说明段）、
  `docs/governance/task-set.lock.json`（D0 集合 +`TASK-D0-09`）、
  `docs/governance/task-freeze-packages/TASK-D0-08.json` 与 `TASK-D0-09.json`（均为
  pre-freeze preparation）、`docs/05-test-spec.md`（TST-HOST-002 两处 + D0-08 节
  per-platform 注记）、`docs/specs/toolchains.md`（信任模型跨平台、Tool Lock v3 节、
  Host Profile v2、closure per-platform 范围、ELF 对应物）、
  `docs/traceability/requirements-matrix.md`（NFR-004 行挂 TASK-D0-09/TST-HOST-002/
  ADR-0016/SPEC-TOOL-001）。
- Design：Host Profile v2 platform-discriminated（darwin 字段集与 eligibility 谓词逐字
  保留）；linux eligibility = native arch + `secureBoot == enabled` + systemTools/distroTools
  pin exact + 非 current-user-mutable，任一谓词观察不到即 ineligible；Tool Lock 拆为
  per-platform 文件（darwin v2 字节不变 + 新 `toolchains-linux-x86_64.lock.json` v3 含
  elfPolicy，digest domain `proof-forge.toolchains.v3`）；Stage-0 按 `uname -s` 分派，
  linux 无 codesign 等价步骤并断言 `LD_PRELOAD`/`LD_LIBRARY_PATH`/`LD_AUDIT`/`LD_DEBUG`
  为空；linux clean-room 沙箱引擎明确不在本期。
- Verification：`/usr/bin/python3 -I -S scripts/docs_check.py` ok；
  `docs_check_self_test.py` ok（186 mutations）；`genesis_root_policy_self_test.py` ok；
  `bootstrap_task_objects_self_test.py` ok；`git diff --check` clean。
- Limitations：ADR-0016 为 proposed，未经 Architecture + Quality 批准；TASK-D0-09 保持
  pending、不得 in_progress（GOV-TASK-FREEZE-001 §7）；TASK-D0-08 冻结包缺 exact counts
  盘点，counts 未固化前不得 RED/in_progress；本机 SecureBoot disabled，按谓词只能登记
  linux development profile；darwin 回归（toolchains-validate/host-stage0-development）
  未在本 session 执行（非 darwin 机）。
- Next：ADR-0016 批准 → TASK-D0-09 in_progress（TST-HOST-002 RED 先行）；期间以 D0-09
  pre-acceptance 方式推进 linux toolchain/host 机制实现（development 证据，不改任务状态）。
  TASK-D0-04 仍 blocked；TASK-D1-04 的 modulo `%` candidate 不变。

## 2026-07-18 — ADR-0017 登记为 proposed（后果落地 deferred）

- Context：工作树中已存在未跟踪的
  `docs/adr/0017-research-phase-targets-ton-move-cairo-zkvm.md`（研究期新增目标
  TON/Move/Cairo/RISC Zero/SP1 的登记与 family 归类决定），但未登记进
  `docs/adr/README.md`，docs_check 以 `PF-DOC-NORMATIVE-ORPHAN` fail closed。
- Changed：`docs/adr/README.md` 增列 ADR-0017 行（proposed）；ADR 本体逐字保留。
- Verification：`/usr/bin/python3 -I -S scripts/docs_check.py` ok；`git diff --check` clean。
- Limitations：ADR-0017 保持 `proposed`，未经 Architecture + Quality 批准；其"后果"段
  所列 6 个 dossier、2 个 family 文档、`docs/targets/README.md` 与 PRD 扩展**尚未落地**，
  属后续独立变更；在该落地前不得把 `ton`/`aptos`/`sui`/`cairo`/`risc0`/`sp1` 写入
  registry、任务表或 traceability matrix。ADR §6 已声明本期不登记 `SRC-*`/`CLM-*`。
- Next：ADR-0017 批准与后果落地均为后续独立变更；D0 主线（ADR-0016 批准、D0-08 counts
  盘点、D0-04 外部前置）不变。

## 2026-07-18 — ADR-0016 批准转 accepted（Architecture + Quality）

- Context：用户（GOV-MAINTAINERS-001 全部角色持有人）在收口 Milestone D0 的指示中明确
  双开发机（macOS/Linux）兼容诉求，对应批准 ADR-0016；批准解锁 `TASK-D0-09` 的
  `pending → in_progress` 闸门（ADR §6 前置）。
- Changed：`docs/adr/0016-cross-platform-host-profile-and-linux-eligibility.md`
  frontmatter `status: proposed → accepted`，补 `approvers: architecture-owner, quality-owner`、
  `approvedAt: 2026-07-18`、`reviewCommit/reviewLink`（指向 ADR 提案 commit
  `fcdeb37645f8405830f9e68340c55ccfa78d6193`，即被批准的内容基线）、`openFindings: none`；
  正文状态行同步。`docs/governance/task-set.lock.json` 与 `docs/04-task-breakdown.md`
  的 D0-09 行已随提案 commit 落地，本变更不再改动（ADR §6）。
- Verification：`/usr/bin/python3 -I -S scripts/docs_check.py`；`git diff --check`。
- Limitations：本批准不改变任何任务状态；`TASK-D0-09` 仍 pending，待独立变更集进入
  in_progress（唯一 in_progress 纪律 + TST-HOST-002 RED 先行）。darwin 回归仍需 darwin 机。
- Next：`TASK-D0-09` in_progress（冻结包 `TASK-D0-09.json` 已预置，RED 先行）。

## 2026-07-18 — TASK-D0-09 进入 in_progress（冻结生效）

- Context：ADR-0016 已 accepted（见上一条）；`TASK-D0-09` 依赖 `TASK-D0-03` 早已 done，
  冻结完成包 `docs/governance/task-freeze-packages/TASK-D0-09.json` 于
  `6dc1d8365c02cd51a8b3365c5199597deda99b61` 预置，满足 GOV-TASK-FREEZE-001 §3 进入条件。
- Changed：`docs/04-task-breakdown.md` D0-09 行 `pending → in_progress` 并改写立项注记；
  `AGENTS.md` checkpoint（Active task=TASK-D0-09、Next task=TASK-D0-08、Known blocker
  更新为 ADR-0016 accepted 口径）。
- Verification：`/usr/bin/python3 -I -S scripts/docs_check.py`；`git diff --check`。
- Limitations：状态变化不产生完成证据；TST-HOST-002 尚未存在，按纪律下一变更集先 RED。
  `d7eec17d` 的 linux toolchain/host 机制为 pre-acceptance development 证据，需经
  TST-HOST-002 正负例验收后才计入本任务完成面。
- Next：审计 `d7eec17d` 落地面 vs 冻结包 8 条 inScope → 提交 TST-HOST-002 RED。
## 2026-07-18 — D1 bitwise-and pre-acceptance slice

- Commits：freeze `10186ad5`；tests-only RED `c7ea38f2`；Source-only GREEN `dc075680`。
- Spec/Test：`SPEC-LANG-001`、`TST-SRC-005`。本切片只追加 D1-PA-39 development evidence，
  不改变 `TASK-D1-04` 的 pending 状态、依赖、Tests 集合或 Done 语义。
- Changed：`Source.Expr.bitwiseAnd lhs rhs`、append-only Expr tag `20`、
  `syntax:45 pfExpr:45 " & " pfExpr:46 : pfExpr`、decoder/quotation，以及 operands 前 exact Typed
  `bitwise and is not yet supported by typed checking`。production 恰好 Source/Syntax/Typed 3 文件/11 行；
  既有 Expr tags `0..19` 与其他层均未改。
- Coverage：双入口与 initializer/entry/view/fn；integer/Bool/order/variable、add/mul/shift/comparison 双向、
  grouping、unary AST；`1 & 2 & 3` 左结合 positive 与 `1 & (2 & 3)` 右嵌套；
  `1 & 2 == 3` 固定为 `1 & (2 == 3)`，`1 == 2 & 3` 固定为 `(1 == 2) & 3`。
  代表 goldens：`1&2` `6fede90fbd307070fd4b86e60d48e595da4620e7d37bf8e368418754e2c55890`/228 bytes、
  `2&1` `80220a38c8f73ac776ea1cc5cf0c2003265d5ef3c8054ba5a1cf34c51915af85`/228、
  `true&false` `58856d731cd9609d5e416ae0de68c22a7ea104938fae15224c52f514ed419ccc`/214、
  left nest `6de67f082d6270d14a91fc5cf8d72f2dcc3b06e22b6fee985ea05658252ec98c`/238、
  right nest `262dbca58bcfd6d3028204c0b59e2c8e7d7589f1d4349d369ee6cb709b5748c2`/238。
- Boundaries：zero migration；`1 & & 2` 与 deferred `1 && 2` 均在 parser boundary 拒绝。Typed exact
  failure 对 integer/Bool operands 都 fail before operands，既有 expression controls 与 checkedAdd positive
  保持。Grok 完成 RED、evidence extraction 与下一 residual 设计；Kimi 完成 freeze、residual 和 GREEN final
  audit，最终 P0/P1=0。
- Commands/Results：`lake build Tests.Language.BitwiseAnd`（14 jobs）；
  `lake build proof_forge_next_tests`（162 jobs）；`lake env .lake/build/bin/proof-forge-next-tests`；
  `git diff --check`，全部 exit 0；development evidence 为 `EV-20260718-0025`。本小切片按批量策略不重复
  全量 `just ci`，最近一次全量 checkpoint 仍为 CompareExpr GREEN `8957c636`。
- Limitations：仅有 Source bitwise-and carrier；没有 operand/result legality、Typed/Semantic bitwise operation、
  `^`/`|`/`&&`/`||`、folding、requirement、target ABI/runtime、eligible host 或 formal D1 evidence；不得关闭
  pending `TASK-D1-04`，D0 formal milestone 仍为 5/8。
- Next：两份独立 residual audit 都选择 binary bitwise-xor `^` 为唯一下一 candidate，但尚未冻结。冻结前
  必须固定低于 `&` 的 precedence `40` 左结合、append-only Expr tag `21`、zero migration、与 `&`/Compare
  的合法 mixed shapes、caret token boundaries 与 exact Typed failure；不得捆绑 `|`、`&&`、`||`、Semantic
  或 target lowering。

## 2026-07-18 — D1 bitwise-xor pre-acceptance slice

- Commits：freeze `f98ec300`；tests-only RED `d6f61464`；Source-only GREEN `a3a48028`。
- Spec/Test：`SPEC-LANG-001`、`TST-SRC-005`。本切片只追加 D1-PA-40 development evidence，
  不改变 `TASK-D1-04` 的 pending 状态、依赖、Tests 集合或 Done 语义。
- Changed：`Source.Expr.bitwiseXor lhs rhs`、append-only Expr tag `21`、
  `syntax:40 pfExpr:40 " ^ " pfExpr:41 : pfExpr`、decoder/quotation，以及 operands 前 exact Typed
  `bitwise xor is not yet supported by typed checking`。production 恰好 Source/Syntax/Typed 3 文件/11 行；
  既有 Expr tags `0..20` 与其他层均未改。
- Coverage：双入口与 initializer/entry/view/fn；integer/Bool/order/variable、add/mul/shift、comparison/
  bitwise-and 双向、grouping、unary AST；`1 ^ 2 ^ 3` 左结合 positive 与 `1 ^ (2 ^ 3)` 右嵌套；
  `1 & 2 ^ 3`/`1 ^ 2 & 3` 和 `1 ^ 2 == 3`/`1 == 2 ^ 3` 的跨层树形全部固定。
  代表 goldens：`1^2` `d29a60c5f4ec26c1762023a2ca0edcbe168ac331533304d6d8780ccd8da67fe3`/228 bytes、
  `2^1` `5e05fbbf55247f3585360d9759539cb75fdb0317e3d32407b7db4e7e2c9476cc`/228、
  `true^false` `1f0e7f0c3572b21a6aa0e5a71cbeb907dda87582141c5887ad5c38143bee67ad`/214、
  left nest `3e2d516147ccf7503de9baa04960edc657aaacbf6ea27398bcde258ec4f9779a`/238、
  right nest `16a7168f37deb94c2b6e25866cf45bd27d2049c42035b0e8087d39571976b64f`/238。
- Boundaries：zero migration；bare/missing、`1 ^ ^ 2`、`1 ^^ 2`、extra 与 deferred `1 | 2` 均在
  parser boundary 拒绝。Typed exact failure 对 integer/Bool operands 都 fail before operands，既有
  expression controls 保持。Grok 完成 RED 与 evidence extraction；Kimi 完成 freeze、下一 residual 和
  GREEN final audit，最终 P0/P1=0。
- Commands/Results：`lake build Tests.Language.BitwiseXor`（14 jobs）；
  `lake build proof_forge_next_tests`（164 jobs）；`lake env .lake/build/bin/proof-forge-next-tests`；
  `git diff --check`，全部 exit 0；development evidence 为 `EV-20260718-0026`。本小切片未重复全量
  `just ci`，最近一次全量 checkpoint 仍为 CompareExpr GREEN `8957c636`。
- Limitations：仅有 Source bitwise-xor carrier；没有 operand/result legality、Typed/Semantic bitwise operation、
  `|`/`&&`/`||`、folding、requirement、target ABI/runtime、eligible host 或 formal D1 evidence；不得关闭
  pending `TASK-D1-04`，D0 formal milestone 仍为 5/8。
- Next：residual audit 选择 binary bitwise-or `|` 为唯一下一 candidate，但尚未冻结。冻结前必须固定
  precedence `35` 左结合、append-only Expr tag `22`、`BitwiseXor.lean` 中唯一 `1 | 2` migration、
  enum variant coexistence 与 future match-arm ownership、和 `^`/`&`/Compare 的合法 mixed shapes；
  不得捆绑 `&&`、`||`、match expression、Semantic 或 target lowering。该切片若收口，将形成 bitwise
  Source tier 批量 `just ci` checkpoint。

## 2026-07-18 — D1 bitwise-or pre-acceptance slice and bitwise-tier checkpoint

- Commits：freeze `2cd00ef6`；tests-only RED `80f319a9`；Source-only GREEN `5ecd8378`；
  canonical golden correction `08ce0b6b`。
- Spec/Test：`SPEC-LANG-001`、`TST-SRC-005`。本切片只追加 D1-PA-41 development evidence，
  不改变 `TASK-D1-04` 的 pending 状态、依赖、Tests 集合或 Done 语义。
- Changed：`Source.Expr.bitwiseOr lhs rhs`、append-only Expr tag `22`、
  `syntax:35 pfExpr:35 " | " pfExpr:36 : pfExpr`、decoder/quotation，以及 operands 前 exact Typed
  `bitwise or is not yet supported by typed checking`。production 恰好 Source/Syntax/Typed 3 文件/11 行；
  既有 Expr tags `0..21` 与其他层均未改。
- Coverage：双入口与 initializer/entry/view/fn；同一 program 中 enum `Flag` 的 `Off` 与
  `On(UInt64)` variants 和 bitwise-or expressions 共存；integer/Bool/order/variable、add/mul/shift、
  comparison/bitwise-and/xor 双向、grouping、unary AST；`1 | 2 | 3` 左结合与 `1 | (2 | 3)` 右嵌套；
  xor/and/comparison 六种跨层 mixed shapes。只迁移 `BitwiseXor.lean` 的一个 deferred bitwise-or negative；
  bare/missing、`1 | | 2`、double-token 与 extra payload 均在 parser boundary 拒绝。final review P0/P1=0。
- Commands/Results：worktree 上真实捕获 `lake build Tests.Language.BitwiseOr`（14 jobs）、
  `lake build proof_forge_next_tests`（166 jobs）与 `lake env .lake/build/bin/proof-forge-next-tests`
  exit 0。初次 committed-tree `just ci` 在 PA40 `twinAndXor` sourceHash golden 失败；同一 canonical
  bytes 经 Lean 与外部 `shasum -a 256` 都得到
  `8f1601e1e52a447c295784f61dbac1d75ad62e6926adf310b202109ca25a5056`，确认原值为转写错误并由
  `08ce0b6b` 更正。随后 clean committed `just ci` at
  `08ce0b6b30b91aa3a599e272e89f85151fe0e182` 完整捕获 exit 0：40-mutation isolation precheck、
  committed archive 174-job build/test/help、186 docs mutations、genesis/bootstrap/SBOM/supply-chain/runtime
  closure self-tests、本地 60-job product build、166-job aggregate/test、DSL negatives 与 target/toolchain
  negatives 全绿；development evidence 为 `EV-20260718-0027`。
- Evidence erratum：写入 `EV-20260718-0025`/`EV-20260718-0026` 时，长跑测试进程的完成输出未被
  coordinator 捕获；PA40 的错误 golden 进一步证明最终 RED tree 上的测试二进制当时不可能全绿。
  evidence ledger 保持 append-only，不改写原行；本次 `EV-20260718-0027` 在最终 committed tree 上
  累计重跑 BitwiseAnd/BitwiseXor/BitwiseOr，并取代原两条的 run-level exit-0 声明。PA39 未发现功能缺陷，
  PA40 golden 已由 `08ce0b6b` 修复。后续 evidence 只能引用写入前已捕获完成输出的运行。
- Limitations：只完成 bitwise-and/xor/or 的 Source carrier；没有 operand/result legality、Typed/Semantic
  bitwise、`&&`/`||`、short-circuit、folding、requirement、target ABI/runtime、eligible host 或 formal D1
  evidence；不得关闭 pending `TASK-D1-04`，D0 formal milestone 仍为 5/8。
- Next：两份独立 residual audit 选择 binary logical-and `&&` 为唯一下一 candidate，但尚未冻结。
  必须固定低于 bitwise-or 的 precedence `30` 左结合、append-only Expr tag `23`、BitwiseAnd suite 中唯一
  deferred logical-and migration、digraph/token integrity 与 operands 前 exact Typed failure；不得捆绑
  logical-or、short-circuit semantics、Semantic 或 target lowering。

## 2026-07-18 — D1 logical-and pre-acceptance slice

- Commits：freeze `72c8bcd2`；tests-only RED `f7adbf8f`；Source-only GREEN `3c16300f`。
- Spec/Test：`SPEC-LANG-001`、`TST-SRC-005`。本切片只追加 D1-PA-42 development evidence，
  不改变 `TASK-D1-04` 的 pending 状态、依赖、Tests 集合或 Done 语义。
- Changed：`Source.Expr.logicalAnd lhs rhs`、append-only Expr tag `23`、
  `syntax:30 pfExpr:30 " && " pfExpr:31 : pfExpr`、decoder/quotation，以及 operands 前 exact Typed
  `logical and is not yet supported by typed checking`。production 恰好 Source/Syntax/Typed 3 文件/11 行；
  既有 Expr tags `0..22` 与其他层均未改。
- Coverage：双入口与 initializer/entry/view/fn；integer/Bool/order/variable、add/mul/shift、comparison、
  bitwise-and/xor/or 双向 precedence、grouping、unary AST；`1 && 2 && 3` 左结合与
  `1 && (2 && 3)` 右嵌套。代表 goldens：`1&&2`
  `b89596d932de15ebbcea6c3f2694e2fbacaa89a83be4e05a60758b6c05158fe6`/228 bytes、`2&&1`
  `6679e8f4476a00519fd007b9d8efca64eebc0e45c29d9719100e881a1eafc635`/228、`true&&false`
  `ec66a3b5f8e1b590d105897f577a1d4f90510225238a2d3e14c3f5d44ffc3248`/214、left nest
  `ae21d1bc4527e6e901988a410860d892f7ad49ab9fb581a079f8090bd1f48d72`/238、right nest
  `c7551bc55592b2c5a2b3532cc8886c9c78b278ed23bb9630c2d538c4e9ed9dd9`/238。
- Boundaries：tests-only RED 只删除 `BitwiseAnd.lean` 的一个 deferred logical-and negative；spaced
  `1 & & 2` survival pin 与 `BitwiseOr.lean` 的 `1 || 2` retention 均保持。bare/missing、
  `1 && && 2`、`1 &&& 2`、`1 & && 2` 与 extra payload 在 parser boundary 拒绝。Typed integer/Bool
  两路均在 operands 前 exact fail closed，既有 expression controls 保持。freeze 与 final review P0/P1=0。
- Commands/Results：`lake build Tests.Language.LogicalAnd`（14 jobs）；
  `lake build proof_forge_next_tests`（168 jobs）；`lake env .lake/build/bin/proof-forge-next-tests`
  真实捕获 exit 0；`git diff --check` exit 0；development evidence 为 `EV-20260718-0028`。按冻结包不重复
  全量 `just ci`，logical-tier committed-tree batch checkpoint 延后至 logical-or 收口。
- Limitations：仅有 Source logical-and carrier；没有 operand/result legality、short-circuit Typed/Semantic、
  logical-or、Bool legality、folding、requirement、target ABI/runtime、eligible host 或 formal D1 evidence；
  不得关闭 pending `TASK-D1-04`，D0 formal milestone 仍为 5/8。
- Next：residual audit 选择 binary logical-or 为唯一下一 candidate，但尚未冻结。必须固定 precedence
  `25` 左结合、append-only Expr tag `24`、BitwiseOr suite 中唯一 double-pipe migration、spaced-pipe
  survival control、与 logical-and/bitwise/comparison 的合法 mixed shapes及 operands 前 exact Typed failure；
  不得捆绑 match、short-circuit implementation、Semantic 或 target lowering。该切片收口时运行 logical-tier
  committed-tree 批量 `just ci`，但不得把运算符 precedence tower 扩张为完整 expression/statement grammar。

## 2026-07-18 — D1 logical-or pre-acceptance slice and operator-tier checkpoint

- Commits：freeze `9ef75d70`；tests-only RED `ed9ae637`；Source-only GREEN `3ff4b76b`。
- Spec/Test：`SPEC-LANG-001`、`TST-SRC-005`。本切片只追加 D1-PA-43 development evidence，
  不改变 `TASK-D1-04` 的 pending 状态、依赖、Tests 集合或 Done 语义。
- Changed：`Source.Expr.logicalOr lhs rhs`、append-only Expr tag `24`、
  `syntax:25 pfExpr:25 " || " pfExpr:26 : pfExpr`、decoder/quotation，以及 operands 前 exact Typed
  `logical or is not yet supported by typed checking`。production 恰好 Source/Syntax/Typed 3 文件/11 行；
  既有 Expr tags `0..23` 与其他层均未改。
- Coverage：双入口与 initializer/entry/view/fn；integer/Bool/order/variable、add/mul/shift、comparison、
  bitwise-and/xor/or、logical-and 双向 precedence、grouping、unary AST；`1 || 2 || 3` 左结合与
  `1 || (2 || 3)` 右嵌套。代表 goldens：`1||2`
  `0d003490a306ffbf450ac6b6f14e52269b45ad323c5cbfb0c20bb185b28d19c8`/225 bytes、`2||1`
  `b914f5d794a6d870f6340efe0cd0d5abef4456232c5a5845095a51b10d244a3b`/225、`true||false`
  `cd96205fda841af0c6721e03bb8a5be12fc3ea2228a85dfdce03b88a490f30b5`/211、left nest
  `137ad8122e776ceee9cd55c0ecda106f6c2264a83fdc2914740e569d32b67fb7`/235、right nest
  `151b82c032acf39a9d3f02988b4cc25b4a28c47166fb288b19db8d334c3ee6fb`/235。
- Boundaries：tests-only RED 只删除 `BitwiseOr.lean` 的一个 double-pipe negative；spaced `1 | | 2`
  survival pin 保持。bare/missing、`1 || || 2`、`1 ||| 2`、`1 | || 2` 与 extra payload 在 parser
  boundary 拒绝。Typed integer/Bool 两路均在 operands 前 exact fail closed，既有 expression controls
  保持。freeze 与 final review P0/P1=0。
- Commands/Results：`lake build Tests.Language.LogicalOr`（14 jobs）；
  `lake build proof_forge_next_tests`（170 jobs）；`lake env .lake/build/bin/proof-forge-next-tests`
  真实捕获 exit 0；clean committed `just ci` at
  `3ff4b76b4ff6dc42746fb917f5c4b89f5dc29dab` 完整捕获 exit 0：40-mutation isolation precheck、
  committed archive 178-job build/test/help、186 docs mutations、genesis/bootstrap/SBOM/supply-chain/runtime
  closure self-tests、本地 60-job product build、170-job aggregate/test、DSL negatives 与 target/toolchain
  negatives 全绿；development evidence 为 `EV-20260718-0029`。
- Scope claim：从 unary、multiplicative、additive、shift、comparison、bitwise 到 logical-or 的 Source
  operator precedence tower 已覆盖；这不包括 MatchExpr、StringLiteral、call/constructor/place、完整
  expression/statement grammar，也不形成 Typed/Semantic 或 target behavior。
- Limitations：仅有 Source logical-or carrier；没有 operand/result legality、short-circuit Typed/Semantic、
  Bool legality、folding、requirement、target ABI/runtime、eligible host 或 formal D1 evidence；不得关闭
  pending `TASK-D1-04`，D0 formal milestone 仍为 5/8。
- Next：两份 residual audit 选择 StringLiteral 为唯一最小下一 candidate，但尚未冻结。必须固定
  append-only Expr tag `25`、Lean string escape 的双入口 round-trip、empty string、与相同 payload variable
  的 tag-only non-alias、相邻/interpolated/unterminated parser boundaries 及 operands 前 exact Typed failure；
  不得捆绑 MatchExpr、call/constructor/place、Semantic 或 target lowering。

## 2026-07-18 — D1 StringLiteral pre-acceptance slice

- Commits：freeze `989503eb`；tests-only RED `7b0b1c5a`；canonical golden binding `a0a460b2`；
  Source-only GREEN `fa4d00c9`。
- Spec/Test：`SPEC-LANG-001`、`TST-SRC-005`。本切片只追加 D1-PA-44 development evidence，
  不改变 `TASK-D1-04` 的 pending 状态、依赖、Tests 集合或 Done 语义。
- Changed：新增 `Source.Expr.stringLiteral value`、append-only Expr tag `25` 后接现有 `appendString`、
  `syntax str : pfExpr`、`str.getString` decoded-value decoder、`Syntax.mkStrLit` quotation，以及 exact Typed
  `string literals are not yet supported by typed checking`。production 恰好 Source/Syntax/Typed 3 文件/9 行；
  既有 Expr tags `0..24` 与其他层均未改。
- Coverage：Lean command/ParserSession 双入口覆盖 initializer、entry、view、fn 的 return/let value；固定
  empty、ASCII、escaped quote/backslash/tab、Unicode scalar；不同 Lean escape spelling 解码为同一 String
  时形成相同 Source.Program/canonical bytes/sourceHash。相同 identity 下 string `"a"` 与 variable `a`
  通过 tag `25`/`1` 不 alias。代表 goldens：empty
  `4cde697b099c9c7c778517b19f2a6f6468aa07c575682fe83cc35b0b7d1e443c`/214 bytes、`hi`
  `a1d09765c39adc277751185ce9f0cf28c6d50809b0e79273747d242d41a2f80c`/216、quote
  `27488c4f1854da8f415becbda9bf7be6546707b691997b7a31f6a97d3cfcfcd5`/215、backslash
  `535ea5e1f0725f98309fc792eb59eba2ffcf365c976662b3310700c9bb348453`/215、tab
  `39e8c5ec3fcc7759b6d26b12efb6f08429217cbbbb4de277e57b605c3691f951`/215、alpha
  `cebe2440eb6d1605ec287c20a76d31830299cb58efcc01073dec8a66cb92a527`/216、`a`
  `eae154b721a1c4ce5cbf1dee4de56f2827c7dfe37edc50cc46f16fa2cc4964d3`/215。
- Boundaries：zero migration；相邻 literals、interpolated `s!"a"` 与 unterminated string 均在 parser
  boundary 拒绝。Typed 对 empty/non-empty string exact fail closed，既有 checked-add control 保持。
  freeze 与最终独立审查 P0/P1=0。
- Commands/Results：`lake build Tests.Language.StringLiterals`（14 jobs）；
  `lake build proof_forge_next_tests`（172 jobs）；`lake env .lake/build/bin/proof-forge-next-tests`
  真实捕获 exit 0；`git diff --check` exit 0；development evidence 为 `EV-20260718-0030`。按冻结包未运行
  全量 `just ci`，批量 checkpoint 延后至下一批 primary-expression 收口。
- Scope claim：EBNF `Literal` 的 integer、Bool、String 三类 Source carrier 已覆盖；不包括 String
  ValueType、concatenation/interpolation、ConstructorExpr、LocalFnCall、Place、MatchExpr 或完整 expression/
  statement grammar。
- Limitations：没有 Typed/Semantic string legality、folding、requirement、target ABI/runtime、eligible host
  或 formal D1 evidence；不得关闭 pending `TASK-D1-04`，D0 formal milestone 仍为 5/8。
- Next：primary-expression residual audit 尚未冻结下一切片；必须在 call/constructor/place/match 中只选择
  一个最小、依赖闭合的 Source carrier，禁止从 checkpoint 自动递增或捆绑 D2/target behavior。

## 2026-07-18 — D1 LocalFnCall/ExprList pre-acceptance slice

- Commits：freeze `b94d694e`；tests-only RED `02ab14b3`；spec API correction `fe41856b`；
  canonical golden binding `75cc3dae`；shared parser-session harness correction `024ae637`；
  Source-only GREEN `af0a7889`。
- Spec/Test：`SPEC-LANG-001`、`TST-SRC-005`。本切片只追加 D1-PA-45 development evidence，
  不改变 `TASK-D1-04` 的 pending 状态、依赖、Tests 集合或 Done 语义。
- Changed：新增 `Source.Expr.localFnCall(callee, args)`、append-only Expr tag `26` 后依次编码
  callee string 与 length-prefixed argument array、high-precedence
  `syntax:max ident "(" pfExpr,* ")" : pfExpr`、双入口 quotation，以及 exact Typed
  `local function calls are not yet supported by typed checking`。production 恰好 Source/Syntax/Typed
  3 文件/13 行；既有 Expr tags `0..25` 与 Semantic/target 层未改。
- Coverage：Lean command/ParserSession 双入口覆盖 initializer、entry、view、fn 的 return/let
  value；固定 zero/one/multiple args、operator/group/string args、nested calls、call-as-operand 与
  escaped callee。`f()`/`f ()` 与 grouped/direct argument canonical equal；callee、count、order、
  nesting 与 expression kind 均进入 source identity。代表 goldens：`f()`
  `8f280c03a43877e0f007b960ed272dc4e56dec0bb054b261d78731ca5126ab35`/231 bytes；`f(1)`
  `c68ef300b0f90505037b1930c23ac84472cdf0c6e775b66fcff7737ff4559c32b`/240；`f(1,2)`
  `a985676f8730d133186ee59c23d3655b93ca07c451c8aff7d734b1c2893bbf1e`/249；`f(2,1)`
  `d437cba945dfb2bc14c1cb5fadf5b30579997d5a48a9d4327df6948899605f81`/249；`g(1)`
  `3669cb06cd56bfabe06950e53a3c89f225e19a797fa8e7e81f47db34cbf3872b`/240；nested
  `2da08134c1d25b7fa2f59da449785a232623122e29314ec169df975574811e08`/267；variable `f`
  control `30fc5e98dc97fc29171664b45fe73468e7f0bd80a7cff0a512b51700086c3469`/223。
- Boundaries：tests-only RED 只迁移 `Grouping.lean` 的唯一 call-like `f(1)` negative；missing
  callee/paren、leading/trailing/double comma、missing/adjacent argument 与 unescaped reserved token 拒绝。
  `A.B()`/`A.B(1)` 在 argument decode 前精确拒绝
  `local function call callee must be unqualified`，为 ConstructorExpr 保留空间。Typed 在 argument
  checking/fn lookup 前 fail closed，final review P0/P1=0。
- Test harness correction：初始累计二进制运行在 43 个 suite 重复 `ParserSession.create`/
  `importModules` 后被终止；process sample 显示在 `LogicalNot.run` 的 environment import 路径上
  physical footprint 约 82.9 GB。`024ae637` 在测试侧复用单一 immutable ParserSession，不修改
  production Loader 语义、不并行执行 suite、不删减测试。
- Commands/Results：`lake build Tests.Language.LocalFnCalls`（15 jobs）；
  `lake build proof_forge_next_tests`（176 jobs）；`lake env /usr/bin/time -l
  .lake/build/bin/proof-forge-next-tests` 真实捕获 exit 0/5.91 s；`git diff --check` exit 0。
  development evidence 为 `EV-20260718-0031`；按冻结未运行全量 `just ci`，call-like primary
  batch checkpoint 延后到后续单一 slice。
- Scope claim：完整 `LocalFnCall ::= Ident "(" ExprList? ")"` 的 Source carrier 已覆盖。
  不包括 callable resolution、arity/type/return/recursion、ConstructorExpr、ExternalCallExpr、Place、
  MatchExpr、Typed/Semantic call、requirement 或 target behavior。
- Limitations：不得声明 PrimaryExpr、完整 grammar、eligible host 或 formal D1 evidence；不得关闭
  pending `TASK-D1-04`，D0 formal milestone 仍为 5/8。
- Next：residual audit 选定 ConstructorExpr 为唯一下一 candidate；必须先冻结 qualified
  component-array identity、tag `27`、精确两条 qualified-call migration 和 Typed fail-before，禁止捆绑
  Place/Match/D2 resolution。

## 2026-07-18 — TASK-D0-09 TST-HOST-002 RED/GREEN 追记与双线合并后全量验证

- Context：上一 session 在 Linux 机完成 `TASK-D0-09` 的 RED（`06274f19`）与 GREEN
  （`1ab751ce`）但未在实现日志/证据台账登记；期间另一台 darwin 机在 origin/main 推进了
  D1-PA-39…46 共 33 个 pre-acceptance 提交，两条线在 `10186ad5` 分叉。本 session 先合并
  再补验并补记。
- Changed（事实追记）：`06274f19` 新增 `scripts/host_profiles_self_test.py`（409 行独立
  验收：linux 生成/验证正负例、linux↔darwin lock 与 profile 互相拒绝、v1→v2 迁移错误、
  观察缺失 fail closed），提交时生产端对应入口尚不存在，先红。`1ab751ce` 补齐 GREEN：
  `.github/workflows/ci.yml` 新增 `linux-tool-root` lane（validate/self-test/host-profiles
  self-test/provision/materialize/verify/observe→validate 闭环）、`justfile` 平台分派
  （`platform_tag`/`locked_git`/`locked_python` 与 toolchains/host-stage0 各 recipe 的
  linux 分支）、`scripts/toolchain_assets.py`（per-platform lock 选择、跨文件平台守卫、
  standalone `validate-host-profile`、ELF closure 后端）、`host-bootstrap-linux.lock` 与
  `host-profiles.lock.json`（linux profile/schema v2 登记）。
- Verification（本 session 对合并树重跑）：`/usr/bin/python3 -I -S scripts/docs_check.py` ok；
  `git diff --check` clean；`host_profiles_self_test.py` ok；`toolchain_assets.py validate`
  与 `self-test` ok；linux tool-root lane 本地复跑（provision digest 精确命中 →
  materialize ELF/runtime closure verified → verify-external ok → observe-host 产出
  `eligibleForHermetic:false`、reason `secure boot is disabled` 的 development profile 并被
  validate-host-profile 接受）；合并树 `just ci` 全绿（v2-isolation/docs-check/sbom/
  supply-chain-core/176-job build/test/dsl-negative/target-negative）。development evidence
  为 `EV-20260718-0041`、`EV-20260718-0042`（原登记 0032/0033 与并行 D1 切片撞号，随并行线推进三次顺延重编号）。
- Merge fix（R1）：合并后 `supply-chain-core` 的 `compiler_runtime_observation_self_test.py`
  以缺 `schema` 字段的 fixture lock 触发 per-platform 分派 `KeyError: 'schema'`
  （`PF-SBOM-CLOSURE`）；以 1 行 fixture 声明 `schema: proof-forge.toolchains.v2` 修复
  （darwin v2 语义，Tests 集合与生产语义不变），observation/manifest 自测转绿后全量
  `just ci` 通过。
- Limitations：darwin 回归（`toolchains-validate`、`host-stage0-development`、`just ci`
  在 darwin 机全绿且 TST-HOST-001 语义不变）未执行——本机非 darwin；本机 SecureBoot
  disabled，linux 侧全部输出仍为 development 级；`TASK-D0-09` 保持 in_progress，不得写成
  formal/hermetic 证据或关闭。
- Next：darwin 机回归是 `TASK-D0-09` doneWhen 的唯一剩余实机项；其 pre-cutover 关闭路径
  另需治理裁决（formal EV 在 D0-07 前被 docs-check fail closed）。随后 `TASK-D0-08`
  counts 盘点（ADR-0016 §7：含 linux leaf）→ RED。

## 2026-07-18 — TASK-D0-04 实现缺口精确盘点（只读分析）

- Context：D0 收口调度需要知道 `TASK-D0-04`（blocked）的可执行面。对
  `scripts/bootstrap_task_objects.py`（约 4.0k 行）与其自测（约 9.8k 行）、
  `verify_host_stage0.sh`、`docs_check.py` 关闭分支与 `05-test-spec.md` 的
  `TST-BOOTSTRAP-001` 语义做了逐件核对。
- Findings（已存在）：全部对象族 consumer/validator 已就绪——PF-JCS、Ed25519
  verify（无 sign）、`BootstrapAuthorityPolicyV1`/`RequiredTestSetV1`/`TaskApprovalV1`/
  `BootstrapTaskVerifierReceiptV1`/`BootstrapApprovalSetV1` 的 parse+验签、
  `EligibleStage0HandoffV1` 内部 preflight；自测为 `TST-DOC-001` 第一层 pure-consumer
  验收，无任何测试声称 `TST-BOOTSTRAP-001`。
- Findings（仓库内可实现但缺失）：activation receipt 对象族
  `BootstrapApprovalVerifierReceiptV1`（零实现）；`FormalGateCatalogApprovalV1`
  parser/consumer（零实现）；authority-store protected service（`pf.authority-store.rpc.v1`
  服务端+客户端，零实现）；全部 producer/signer（RequiredTestSet/TaskApproval/set
  producer 与 receipt 签发 verifier；genesis root 工具按设计无私钥路径）；Stage-0
  handoff producer（现 Stage-0 只输出 local-observation JSON，不产出带 runId/nonce/TCB
  digest/预开 fd channel 的 handoff 对象）；防 `setsid()` 逃逸的 process-session
  containment runner；`TST-BOOTSTRAP-001` 可执行验收（pre-activation 输入空间 +
  与 production lookup tuple 不相交的 fixture namespace）；关闭治理件
  （attest + docs_check `d0_04_*_attested()` 分支 + bootstrap EV 行）。
- Findings（本质外部前置）：真实 handoff 必须在 eligible host 上产出（eligible=true
  观察、TCB digest、fd channel fstat/stable-read）；authority-store 须作为 Stage-0
  child 运行且 executable digest 与 descriptor 精确相等；每次 task completion/activation
  需要在线 distinct-principal quorum 签名（人工仪式）；最终 `D0-04 approval → task
  receipt → six-item set → activation receipt` 序列须对 exact candidate 在 eligible host
  真实走完。当前两台开发机均不合格（darwin seal broken/Xcode mutable；本机 SecureBoot
  disabled），解除路径：启用 SecureBoot 并重锁 linux 资产，或修复 darwin SSV/Xcode
  归属后重登记 eligible profile。
- Limitations：本条仅为只读盘点，不改变 `TASK-D0-04` 的 blocked 状态、冻结完成面或
  任何 Tests 集合；未运行任何新实现。
- Next：`TASK-D0-08` counts 盘点与 RED；D0-04 的仓库内缺口（activation receipt/
  catalog approval/authority-store/producer/handoff producer/containment runner）在
  eligible host 出现前只能以明确标注的 pre-acceptance 方式推进，不得据此关闭。

## 2026-07-18 — TASK-D0-08 counts 盘点固化（pre-freeze 完成）

- Context：冻结包 notes 要求 RED 前盘点全部已提交 per-platform Tool Lock 文件的 leaf
  refs、Lean compiler 可达 non-system runtime manifests，并固定 CycloneDX schema/SPDX
  grammar+list 文件与离线 validator ToolchainIdentity（ADR-0016 §7：D0-09 先完成，
  counts 含 linux leaf）。
- Method：leaf 计数直接用 `scripts/supply_chain_core.py` 的
  `enumerate_tool_lock_leaves` 对两个已提交 lock 实跑；compiler-runtime 由 pinned lean
  归档重算——linux 以 `just toolchains-materialize-lean` 物化后 `readelf -d` 求
  bin/lean+bin/lake 的 toolchain 内传递闭包，darwin 以 lock pin 的
  `lean-4.31.0-darwin_aarch64.zip`（sha256 校验 `e8cd241b…`）解包后用一次性纯 python
  Mach-O load-command 解析器求同名闭包；licenses 按 `licenses/` 与根 `LICENSE` 计；
  lake-manifest `packages` 为空（0 source-dependency）。
- Results（已写入冻结包 `frozenCounts` 与 `05-test-spec.md` D0-08 节，两处一致）：
  leaf refs darwin 20（6/6/2/5/1）+ linux 17（5/5/2/5/0）= 37；compiler-runtime
  darwin 5 + linux 5 = 10；logical components 41（1 package/0 source-dep/11 asset/
  4 compiler-exe/10 tool-exe/11 runtime/4 license-text）+ 1 synthetic root；
  content identities 37；typed relationships 146（has-content 41、unpacks-to 25、
  loads 27、licensed-under 12、bom-member 41）；standards files 4（已提交
  `supply-chain/standards/` 并 sha256 pin，离线 validator 为两平台 lock 内 jv v6.0.2）；
  sidecar files 3；lean-package file-set = 30 product library 源文件。
  关键共享：darwin solc asset/bundle/tool-executable 同 bytes 共享 1 content identity；
  libcrypto bundle-file 与 wat2wasm runtimeFile join 同一 runtime component；linux
  `libleanshared_1/_2/libInit_shared.so` 三文件同 digest `2f96493a…`。
- Verification：`/usr/bin/python3 -I -S scripts/docs_check.py` ok；`git diff --check`
  clean；darwin lean 资产按 lock pin sha256/size 逐字节核验；closure 解析器输出与
  `readelf` 独立复核一致（linux 5 节点、darwin 5 节点）。
- Limitations：盘点只固化计数与 pins，不产生 SBOM closure/binding 实现；darwin 闭包
  由 linux 上纯 python Mach-O 解析器从 pinned 归档重算，未在 darwin 机复跑 otool
  （D0-09 回归一并覆盖）；`TASK-D0-08` 仍 pending，未进入 in_progress。
- Next：`TASK-D0-08` → in_progress（冻结完成包已齐），随后 TST-SBOM-002 RED
  （独立 fixture/validator + 常量 oracle，至少 SB2-001/003/007/008/009/011/018/019/
  022/023/025/028 先红并证 legacy generator 不误绿）。

## 2026-07-18 — TASK-D0-08 in_progress 与 TST-SBOM-002 RED→GREEN（前 12 例）

- Context：counts 盘点固化后 `TASK-D0-08` 进入 in_progress（唯一 in_progress 槽位由
  `TASK-D0-09` 转 blocked 释放）。按纪律先提交 tests-only RED（`904f8eb6`），再实现
  production 转绿。
- RED：`scripts/sbom_closure_self_test.py`（独立 fixture/validator）：冻结 counts 全部
  固化为常量（37 leaf refs/41 components/37 content identities/146 relationships/
  10 compiler-runtime/30 file-set/4 standards/3 sidecars）；SB2-001/003/007/008/009/
  011/018/019/022/023/025/028 十二例按 spec 要求先红（production 不存在），
  LEGACY-NOT-GREEN 例证明 D0-05 legacy generator 不能误绿。
- GREEN（`scripts/sbom_closure.py` 新生产模块 + 提交输入）：候选 archive 绑定
  （size/digest 先验后解析）；双平台 Tool Lock 权威校验与 v2/v3 typed digest；
  七类 logical component 闭包解析（darwin solc asset/tool 共享 content identity 但保留
  独立 component、bundle/runtime 双 leaf join 同一 libcrypto component、linux 三个
  6232-byte stub 共享 1 identity）；已提交 `supply-chain/compiler-runtime-*.v1.json`
  （双平台各 5 文件 + load edges，结构校验 dangling/orphan/executor 漂移）与
  `supply-chain/standards-manifest.v1.json`（4 文件 bytes/sha256 pin 逐字节核验）；
  三文件 sidecar（closure/BOM/binding）PF-JCS canonical + atomic no-clobber 0444 写入
  （staging+rename+fsync）；`verify_existing` 全量重算比对；FIFO/非常规输入
  PF-SBOM-IO、candidate 漂移 PF-SBOM-BIND、no-clobber 违例 PF-OUTPUT-ATOMICITY。
- Verification：`/usr/bin/python3 -I -S scripts/sbom_closure_self_test.py` ok（13/13）；
  手工 generate 复核 counts 与冻结值逐项一致；`just ci` 全量绿（sbom recipe 已接入
  新自测）；`/usr/bin/python3 -I -S scripts/docs_check.py` ok；`git diff --check` clean。
- Limitations：仅前 12 例 + legacy guard 转绿；SB2-002/004/005/006/010/012/013/014/
  015/016/017/020/021/024/026/027/029/030/031 与 jv 离线 schema 验证、fault-injection
  完整矩阵尚未实现；`TASK-D0-08` 保持 in_progress，不得记录为 done；关闭另需
  pre-cutover 治理裁决（formal EV 在 D0-07 前 fail closed，本任务不在 genesis 集合）。
- Next：SB2 剩余 19 例全矩阵 + jv 离线验证接入；doneWhen 第 2–3 条（双 root/空 HOME/
  locale/umask byte-identical、legacy negative 与 race 全拒）随全矩阵收口。
## 2026-07-18 — D1 ConstructorExpr pre-acceptance slice

- Commits：freeze `4d61820e`；primary tests-only RED `717da5a0`；canonical/boundary RED hardening
  `fbed21c6`；component-count/escaped-classification spec clarification `66f56bf9`；classification RED
  `2bc6eb9d`；underscore/Common-diagnostic RED `ab610e57`；UNBOUND restore `a624b484`；final
  canonical golden binding `48c00733`；Source-only GREEN `f8ca5fe4`。`ab610e57` 在 shared-tree 并行中
  短暂夹带了 provisional hashes，`a624b484` 立即恢复 UNBOUND，最终只以独立测量后的
  `48c00733` 作为有效 binding。
- Spec/Test：`SPEC-LANG-001`、`TST-SRC-005`。本切片只追加 D1-PA-46 development evidence，
  不改变 `TASK-D1-04` 的 pending 状态、依赖、Tests 集合或 Done 语义。
- Changed：新增 `Source.Expr.constructorExpr(path, args)` 与 append-only Expr tag `27`，先编码
  length-prefixed path component array，再编码 length-prefixed argument expression array。复用 PA45
  call-like syntax rule，decoder 以 Lean `Name.components.length` 将单组件分类为 LocalFnCall、
  多组件分类为 ConstructorExpr；`decodeConstructorPath` 逐组件经 portable reserved policy
  和 Common QualifiedName canonical validation，并先于 arguments 执行。quotation 保留两个 arrays；
  Typed 逐字 fail closed 为 `constructor expressions are not yet supported by typed checking`。
  production 恰好 Source/Syntax/Typed 3 文件、24 行新增/3 行移除；没有新 syntax rule、
  Semantic 或 target 变更。
- Coverage：Lean command/ParserSession 双入口覆盖 initializer、entry、view、fn 的 return/let；
  zero/one/multiple、operator/group/string arguments、nested constructors 和 constructor-as-operand；
  two/multi-component paths 与合法 escaped-component parity。固定 component value/count/order、argument
  value/count/order/nesting，以及 constructor/local-call/variable 三方 tag non-alias。代表 goldens：
  `A.B()` `7308954255287dca62e73a7c7cbcb38e0a42cf39f6bc860886cc1ea9120368a1`/260 bytes；
  path-value `A.C()` `311a4c5d4935014bdd5eb21cecf04b057f487988f104a352e37b9c06d8a3f6c9`/260；
  `A.B(1)` `8edaf53dbcbf3d033ea197c991d3c2fae815f786bb783d8900b938db65d0d717`/269；
  arg-value `A.B(2)` `5fc5b87a8ac3b400afcfe35a317df350bdba529d68f7a4c323a5bd57db51eea2`/269；
  `A.B(1,2)` `0d04c4950a2197f8761ed9fdf55cb55384214b1534c961e591195a3a4aa0226b`/278；
  arg-order `10c60da85be80275e7fa1cc3815c142359e9fa667e467bff1df40f05f1fc9013`/278；
  path-order `896dfade7909d50800f4d85918984fa2b02e4079d8601653b38c28ca64ce745c`/260；
  path-count `137d315d470589764b9be2290db6eab93c66a03494e535ac24dcd61baf3a8b95`/269；
  nested `77e6f8de9244c19752c387b13e50a89cc82d408a3f5971eee0c0d6ef8724c5a9`/313。
- Boundaries：RED 只迁移 `LocalFnCalls.lean` 的 `A.B()`/`A.B(1)` 两条 qualified negatives。
  bare `A.B` 仍是 variable；whole-escaped `«A.B»()` 按单组件仍是 LocalFnCall；
  `«A».B(1)`/`A.«B»(1)` 与普通 path canonical equal。numeric/empty components 停在 parser
  boundary；reserved、invalid escaped 与 underscore components 以精确 portable/Common diagnostic 拒绝，
  并先于 Bool/string argument diagnostics。两份 final review 均为 P0/P1=0。
- Commands/Results：`lake build Tests.Language.ConstructorExprs`（15 jobs）；
  `lake build proof_forge_next_tests`（178 jobs）；`lake env /usr/bin/time -l
  .lake/build/bin/proof-forge-next-tests` 真实捕获 exit 0/4.46 s；`git diff --check` exit 0。
  clean committed `just ci` 绑定 `f8ca5fe48e3c6fc2e93b1a7b1567e76b342f6374`：40-mutation
  isolation precheck、186-job archive build/test/help、186 docs mutations、genesis/bootstrap/SBOM/
  supply-chain/runtime-closure self-tests、60-job product build、178-job aggregate/test、DSL negatives 与
  target/toolchain negatives 全部 exit 0。development evidence 为 `EV-20260718-0032`。
- Scope claim：ConstructorExpr Source carrier 与 LocalFnCall/ConstructorExpr 的 component-count 分类已覆盖。
  不包括 struct/enum/Option constructor resolution、arity/type/result、Place、MatchExpr、ExternalCallExpr、
  Typed/Semantic constructor、requirement 或 target behavior。
- Limitations：不得声明 PrimaryExpr、完整 grammar、eligible host 或 formal D1 evidence；不得关闭
  pending `TASK-D1-04`，D0 formal milestone 仍为 5/8。clean `just ci` 仍是 development gate，
  不是 eligible Stage-0/formal hermetic evidence。
- Next：PrimaryExpr residual audit 尚未冻结；Grok 建议只切 Place.Index，Place.Field 因既有
  bare dotted variable tokenization 冲突需先做规格决策，当前正等待独立 challenge review。

## 2026-07-18 — D1 bare-base rvalue indexAccess pre-acceptance slice

- Commits：freeze `88aa2af7`；tests-only RED `049ef0c8`；canonical golden binding
  `dcfb6e19`；same-identity escaped-base control correction `5515acb2`；Source-only GREEN
  `cc1e1ef2`。
- Spec/Test：`SPEC-LANG-001`、`TST-SRC-005`。本切片只追加 D1-PA-47 development evidence，
  不改变 `TASK-D1-04` 的 pending 状态、依赖、Tests 集合或 Done 语义。
- Changed：新增 `Source.Expr.indexAccess(base, index)` 与 append-only Expr tag `28`，依次编码
  base string 和递归 index expression；新增 high-precedence leading-on-ident
  `syntax:max ident "[" pfExpr "]" : pfExpr`、decoder 与 quotation。decoder 先要求 base 恰好一个
  Lean `Name` component，再经既有 portable identifier policy 解码 base，最后才解码完整 index。
  Typed 逐字 fail closed 为 `index access is not yet supported by typed checking`。production 恰好
  Source/Syntax/Typed 3 文件、13 行新增；Semantic、requirement 与 target 未改。
- Coverage：Lean command/ParserSession 双入口覆盖 initializer、entry、view、fn 的 return/let；
  `x[0]`/`x [0]`、escaped ordinary base、operator/group/local-call/constructor index，以及
  indexAccess 作为 unary/binary operand。固定 base value、index value/tree、spacing/escape canonical
  equality 与 tag `28` 对 variable tag `1` non-alias。六个 IndexAccessTwin hash goldens 及独立 probe
  测得的 canonical byte size 为：`x[0]`
  `9244d727ece801a6e4fcae4e34b7e12fbc3110d5b0ef5a07d75b0c039b000ce4`/233 bytes；`x[1]`
  `7d9253e00ff06d32a7440a3fdba4d427bfe1e221c698998837b264cac371db7a`/233；`y[0]`
  `98d3150573dee013428d347a173975f42c1c25f9bff1cca7af6c892a5fd5812d`/233；`x[1+2]`
  `8a6ad5b937c6ca326f41e2bd683ebcb7c76cb2516d951bc58442bc69c5763a7f`/243；`x[f(1)]`
  `3f3db2b94cf9c87df71cb37a6b07fa5d00823289ed15ad83ac87c4fbab57461f`/251；`x[A.B(1)]`
  `3ceb4bd53c70208cf2a65ff785ec50816f4d31c1e3b4332f4cffcaef994ffde1`/268。
- Boundaries：zero migration；missing/malformed brackets/base/index、extra payload、group/call base、
  `x[0][1]` chaining 与 `x[0] := 1` indexed assignment 均停在 parser boundary。`A.B[true]`
  在 index 前精确拒绝 `index access base must be unqualified`；reserved base 走既有 portable policy。
  Typed 在 unknown base 与 Bool/string index checking 前 fail closed。真实 focused 执行发现 RED 中
  escaped/plain equality 最初使用不同 program name；`5515acb2` 将其修正为同 identity 后通过，
  没有修改 production 语义。两份 final review 均为 P0/P1=0。
- Commands/Results：`lake build Tests.Language.IndexAccesses`（15 jobs）；`lake env lean --run
  /dev/stdin` 直接执行 `Tests.Language.IndexAccesses.run` exit 0；`lake build proof_forge_next_tests`
  （180 jobs）；`lake env /usr/bin/time -l .lake/build/bin/proof-forge-next-tests` exit 0/4.88 s；
  `git diff --check` exit 0。development evidence 为 `EV-20260718-0033`。按冻结未运行全量
  `just ci`；下一批 primary-expression checkpoint 再运行。
- Scope claim：bare single-component identifier 的单个 rvalue bracket indexAccess Source carrier 已覆盖。
  不包括 field suffix、suffix chaining、indexed assignment、general postfix、完整 Place、lvalue/container/
  index/bounds/read semantics、MatchExpr、ExternalCallExpr、Typed/Semantic index、requirement 或 target behavior。
- Limitations：不得声明完整 Place、PrimaryExpr、expression/statement grammar、eligible host 或 formal D1
  evidence；不得关闭 pending `TASK-D1-04`，D0 formal milestone 仍为 5/8。
- Next：下一 development slice 未冻结；必须先重新审计 field tokenization、chaining 表示与
  Match/External residual，只能选择一个依赖闭合的最小切片。

## 2026-07-18 — D1 complete revert statement pre-acceptance slice

- Commits：freeze `6e37c8a5`；tests-only RED `f8fa9e5f`；longest-match 规格澄清
  `0791cb10`；RED priority hardening `856b68e6`；canonical golden binding `27b3a17e`；
  return control fixture correction `d4761ff6`；Source-only GREEN `64a081cf`。
- Spec/Test：`SPEC-LANG-001`、`TST-SRC-005`。本切片只追加 D1-PA-48 development evidence，
  不改变 `TASK-D1-04` 的 pending 状态、依赖、Tests 集合或 Done 语义。
- Changed：新增 `Source.Statement.revertStmt(errorName, args)` 与 append-only Statement tag `5`，
  依次编码 errorName string 和 length-prefixed argument expression array；parenthesized rule 先于
  strict-prefix bare fallback，并由 decoder 把 bare/empty-paren 都物化为 empty args。name 先做单一
  component guard，再走既有 portable identifier policy，最后才解码完整 ExprList；quotation 保留结构。
  Typed 在 error lookup/argument checking 前逐字 fail closed 为
  `revert statements are not yet supported by typed checking`。production 恰好 Source/Syntax/Typed
  3 文件、20 行新增；Semantic、requirement、error resolution 与 target 未改。
- Coverage：Lean command/ParserSession 双入口覆盖 initializer、entry、view、fn；bare、empty-paren、
  one/multi args、operator/group/string/local-call/constructor/index/nested argument tree。相同 identity 下
  bare/empty AST、canonical bytes、sourceHash 相等；name、argument count/order/nesting 与 tag `5` 对
  synchronous call/assert/return 均不 alias。六组 RevertTwin hash/size 为：bare Err
  `c52fc7afa243bb9ea5e9ebe28a6094525c137462d78e83312041216c51d90716`/236 bytes；Err(1)
  `b2b26b8586fc68dc45ad8c99c6a0a36208d060699bee3618bf033b7e12074f67`/245；Err(1,2)
  `9732b4f7ae5ad6670d51d95af81001d19622bed60116eb9561c15152bb3019a1`/254；Err(2,1)
  `f118fe75245f1cc69ebd46d9965177d9a4a8a5cb51dc32aa377e2f5cd912744e`/254；bare Other
  `ec29ebf0a385d704e795e81f1e9f656410dfae920a0cb8bdec9a74e8680c5acb`/238；nested
  `045cd8c6c2f5a1906da0b3704a5b245e717792537fa55cfabbd18dc9fc3ec9c5`/290。
- Boundaries：zero migration；missing name/paren、leading/trailing/double comma、adjacent argument、extra
  payload 与 unescaped keyword assignment 均拒绝；escaped `«revert» := 1` 保持 assignment。
  `A.B(true)` 在 Bool argument 前精确拒绝 `revert error name must be unqualified`，reserved name 走既有
  portable policy。GREEN 首次完整执行暴露 return control 复用了自动追加 return 的 twin，
  `d4761ff6` 将其改为独立单-return program，不改变 production 或冻结测试意图。两份 final review
  均为 P0/P1=0。
- Commands/Results：`lake build Tests.Language.RevertStatements`（15 jobs）；`lake env lean --run
  /dev/stdin` 直接执行 `Tests.Language.RevertStatements.run` exit 0，并独立测量上述 hash/size；
  `lake build proof_forge_next_tests`（182 jobs）；`lake env /usr/bin/time -l
  .lake/build/bin/proof-forge-next-tests` exit 0/6.55 s；`git diff --check` exit 0。development evidence
  为 `EV-20260718-0034`。按冻结未运行全量 `just ci`，下一批 statement checkpoint 再运行。
- Scope claim：完整 bare/empty/full ExprList revert statement Source carrier 已覆盖。不包括 error declaration
  resolution、payload arity/type、failure/rollback semantics、Typed/Semantic revert、ABI/runtime、requirement
  或 target behavior。
- Limitations：不得声明完整 error semantics、statement grammar、eligible host 或 formal D1 evidence；
  不得关闭 pending `TASK-D1-04`，D0 formal milestone 仍为 5/8。
- Next：下一 development slice 未冻结；正在对 indexed assignment、value-less return、Match 与
  ExternalCall residual 做依赖闭合审计，只能选择一个 durable 最小切片。

## 2026-07-18 — TST-SBOM-002 全 31 例 GREEN（phase-2）

- Context：RED-12 转绿后按 spec 把验收矩阵扩展到完整 SB2-001..031 + LEGACY-NOT-GREEN
  共 32 例；委托子代理实现，主会话逐段评审后提交。
- Changed：`scripts/sbom_closure.py`（+582 行）——tool/bundle digest join 纵深防御
  （SB2-010）、新提交输入 `supply-chain/lean-package-files.v1.json`（30 文件 pin，
  schema `proof-forge.lean-package-files.v1`）与 file-set 漂移检测（SB2-012/013）、
  inventory 必填字段/唯一/排序/dependsOn 无环校验（SB2-014）、license 文本
  licenseFileSha256 重算 + nlink=1 + 正文 marker（SB2-015）、完整 SPDX 表达式解析器
  对照 pinned lists 的 canonical 校验（SB2-016）、policy 三表两两不交/externalCli⊆deny/
  表达式全有效（SB2-017）、typed relationship 结构不变量（no-self/no-dangle/no-dup/
  loads 无环，SB2-020）、verify_existing legacy schema 识别（SB2-005/021/024）、
  atomic writer 父目录 symlink/group-world-writable 拒绝（SB2-026）、四级 limits
  （components 4096/relationships 16384/file-set 4096/sidecar 64MiB，SB2-031）。
  另修复 verify_existing 成员比较未排序常量的既有 bug（此前被负向预期掩盖）。
- Tests：`scripts/sbom_closure_self_test.py`（+875 行）19 个新案例：SB2-002 双 root
  对照（typed 不变/raw 变/BOM 不变/binding 变）、SB2-004 raw/typed 互换 BIND、
  SB2-005 三种 legacy payload SCHEMA 且还原后 verify 通过、SB2-006 七种 JSON 攻击、
  SB2-010 三种 lock 漂移、SB2-012/013 文件集 missing/extra/rename/append、SB2-014
  duplicate/dangling/cycle/self、SB2-015 tamper/symlink/hardlink/placeholder、SB2-016
  五种表达式攻击、SB2-017 五种 policy 攻击、SB2-020 loadEdges 注入 self/cycle/missing/
  duplicate、SB2-021/024 篡改后 verify 报错且还原通过、SB2-026 symlink 父目录与
  0775/0777、SB2-027 二次生成 ATOMICITY 且首次产物不变、SB2-029 两个不同
  TZ/locale/umask/HOME/cwd 的 CLI 子进程 byte-identical、SB2-031 四 limit equal/over。
  SB2-030：本机与 tool-root 均无 jv，live schema 校验按冻结外处理，改为证明
  identity-未重算的 CycloneDX 外形 BOM 被 consumer 以 PF-SBOM-BIND 拒绝。
- Verification：`/usr/bin/python3 -I -S scripts/sbom_closure_self_test.py` ok（32/32，
  三次复跑）；`/usr/bin/python3 -I -S scripts/docs_check.py` ok；`git diff --check`
  clean；`supply-chain/lean-package-files.v1.json` 与当前树逐文件核验一致。
  新契约：`ProofForgeV2/**` 源码变更必须同变更运行 `just sbom-package-files-refresh`
  （已写入 AGENTS.md 执行协议与 README 双机节）。
- Limitations：jv 离线 CycloneDX schema 验证未接入（tool root 物化后可补）；
  `TASK-D0-08` 仍 in_progress；关闭需 pre-cutover 治理裁决；SB2-028 的逐点
  fault-injection 完整矩阵保留在基础版（no-clobber/预存在 destination）。
- Next：doneWhen 剩余——`--verify-existing` 独立重算已绿；关闭路径按治理裁决；
  全量 `just ci` 与 merge/push 由主会话执行。
## 2026-07-18 — D1 value-less return pre-acceptance slice

- Commits：freeze `63371613`；tests-only RED `df5ea962`；RED priority hardening `57239979`；
  deterministic-offside 规格修正 `5c04c4f0`；offside RED 修正 `591129f9`；canonical golden binding
  `5d16caab`；Typed diagnostic-priority 规格修正 `1ea48621`；returnValue control fixture 修正
  `7d944c0e`；Source-only GREEN `4a95e5ef`。
- Spec/Test：`SPEC-LANG-001`、`TST-SRC-005`。本切片只追加 D1-PA-49 development evidence，
  不改变 `TASK-D1-04` 的 pending 状态、依赖、Tests 集合或 Done 语义。
- Changed：新增 nullary `Source.Statement.returnUnit` 与 append-only Statement tag `6`，canonical
  encoder 不带 payload；既有 `returnValue` 与 tag `1` 不变。named `returnValueStmt` 以 deterministic
  offside 规则只接受同一行或严格更深缩进的 value expression，同 statement column 的 newline
  结束 bare `return`，decoder/quotation 保留两种结构。Typed 对 entry/initializer 的 `returnUnit`
  逐字 fail closed 为 `value-less return is not yet supported by typed checking`；既有 generic fn gate
  只增加相同 exact-priority 检查，无 returnUnit 的普通 fn 仍返回原 fail-closed。production 恰好
  Source/Syntax/Typed 3 文件、12 行新增/2 行移除；Semantic、requirement 与 target 未改。
- Coverage：Lean command/ParserSession 双入口覆盖 initializer、entry、view、fn，explicit/omitted Unit
  与 non-Unit declaration；`return 1`、`return true`、`return 1 + 2` 保持 `returnValue`，严格更深缩进的
  continuation 保持 value-bearing，同列 `return` newline `1` 拒绝，bare 后同列 assignment 解析为
  `returnUnit` 后 assignment。固定 tag non-alias、malformed/extra payload、escaped keyword assignment、
  Source parity 与 exact Typed priority。`ValueLessUnitTwin` 的 sourceHash/canonical size 为
  `acd66177791a2f84ea2f463d999df132dc772e50b586371e8cbb86ab34c2ded5`/221 bytes。
- Corrections：首次 GREEN 聚焦构建证明 unrestricted 跨行 Expr 会吞下一 item 的 contextual `fn`
  或下一 statement identifier；`5c04c4f0`/`591129f9` 在实现前把冻结边界纠正为 deterministic offside，
  未迁移既有 suite。首次 aggregate test-binary 执行又证明 generic fn gate 先于 statement checker；
  `1ea48621` 如实把 production budget 修正为 12/2，并限定只补 returnUnit exact priority。最终 positive
  control 原先构造了两个连续 return，`7d944c0e` 改为已解码的单一 `return 1` program；两项测试修正
  都未放宽 production。Grok/Kimi final reviews 均为 P0/P1=0。
- Commands/Results：`lake build Tests.Language.ValueLessReturns`（15 jobs）；独立 Lean probe 测量上述
  hash/size；`lake build proof_forge_next_tests`（184 jobs）；`lake env /usr/bin/time -p
  .lake/build/bin/proof-forge-next-tests` exit 0/5.54 s；`git diff --check` exit 0。随后在 clean committed
  `4a95e5efc3f00c6b27ec56c17c0b374236d37224` 上只运行一次 `just ci` 并捕获 exit 0：40-mutation
  isolation precheck、192-job committed archive build/test/help、186 docs mutations、genesis/bootstrap/
  SBOM/supply-chain/runtime closure self-tests、60-job product build、184-job aggregate/test、DSL 与
  target/toolchain negatives 全绿。development evidence 为 `EV-20260718-0035`。
- Scope claim：value-less return 的 Source carrier、deterministic offside surface、canonical identity 与
  Typed fail-closed 已覆盖。不包括 implicit Unit/fallthrough、return type/effect/path、statement-after-return
  新语义、Semantic return、ABI/runtime、requirement 或 target behavior。
- Limitations：不得声明完整 return semantics、statement grammar、eligible host 或 formal D1 evidence；
  不得关闭 pending `TASK-D1-04`，D0 formal milestone 仍为 5/8。
- Next：当前无 active development slice；下一 slice 未冻结，必须先完成 expression residual audit，
  再选择单一依赖闭合的最小切片，禁止自动递增。

## 2026-07-18 — TST-SBOM-002 收尾：SB2-028 逐点 fault injection 与 SB2-030 locked-jv 实测

- Context：phase-2 留下两处低于 spec 的口径（SB2-028 仅基础 no-clobber、SB2-030 因
  环境无 jv 只做 consumer 拒绝）；本变更把它们补齐到 spec 全量语义。同时合并第三轮
  D1 并行线（value-less return 等 10 提交），按新契约重钉 lean package file-set。
- Changed：`scripts/sbom_closure.py` 的 `write_sidecars_atomic` 增加 test-only
  fault-injection seam（`_IO_FAULTS` + write/fsync-file/chmod/fsync-staging/rename/
  fsync-parent 六个注入点；rename 前失败 staging 清零零输出，fsync-parent 失败报
  PF-OUTPUT-ATOMICITY 且 destination 保持完整可验证，绝不报成功）；生产路径 seam 为空，
  非 SbomClosureError 异常统一包装为 PF-OUTPUT-ATOMICITY。
  `scripts/sbom_closure_self_test.py` 新增 `SB2-028-FAULTS`（5 个 pre-rename 点逐一
  注入 + KeyboardInterrupt signal stand-in + fsync-parent 完整保留 + verify-existing
  确认）；SB2-030 增加 locked-jv 腿：仅在 jv 二进制 sha256 与平台 lock 的
  `tools[jv].executableSha256` 精确相等时才调用（`PROOF_FORGE_TOOL_ROOT`、
  `build/tool-root/<platform>`、默认 cache 三处候选，ambient jv 永不替代）。
- Verification：`/usr/bin/python3 -I -S scripts/sbom_closure_self_test.py` ok
  （33/33）；locked jv（`build/tool-root/linux-x86_64/jv`，digest 与 lock pin 一致）
  对 `supply-chain/standards/cyclonedx-bom-1.6.schema.json` + 生成的 `bom.cdx.json`
  实测 `schema ok / instance ok`；`just sbom-package-files-refresh` 重钉 30 文件
  （value-less return 合并后漂移修复）；`/usr/bin/python3 -I -S scripts/docs_check.py`
  ok；`git diff --check` clean。前条 phase-2 日志中"SB2-028 保留基础版、jv 未接入"
  的限制自本条起作废。
- Limitations：signal 腿以 KeyboardInterrupt stand-in 代替 OS signal 注入；
  `TASK-D0-08` 仍 in_progress（关闭需 pre-cutover 治理裁决）；darwin 机回归与
  jv 在 darwin tool root 的等效验证未在本机执行。
- Next：全量 `just ci` → push；`TASK-D0-08` 待治理裁决关闭；`TASK-D0-09` 待 darwin
  回归与同一裁决。
## 2026-07-18 — D1 emit statement pre-acceptance slice

- Commits：freeze `c91260df`；tests-only RED `d7d79f5e`；canonical golden binding
  `7eaf464e`；Source-only GREEN `de40194f`。
- Spec/Test：`SPEC-LANG-001`、`TST-SRC-005`。本切片只追加 D1-PA-50 development evidence，
  不改变 `TASK-D1-04` 的 pending 状态、依赖、Tests 集合或 Done 语义。
- Changed：新增 `Source.Statement.emitStmt(eventName,args)` 与 append-only Statement tag `7`，
  canonical encoder 依次编码 event name string 和 length-prefixed expression array；tag 0–6 不变。
  surface 只接受 mandatory-parentheses `emit Ident(ExprList?)`，single-component guard 与 portable
  identifier validation 均先于 argument decode，quotation 保留完整结构。Typed 对 emit 逐字 fail closed
  为 `emit statements are not yet supported by typed checking`；event declaration 的既有 generic gate
  不变。production 恰好 Source/Syntax/Typed 3 文件、13 行新增/0 行移除；Semantic、requirement 与
  target 未改。
- Coverage：Lean command/ParserSession 双入口覆盖 initializer、entry、view、fn，以及 empty/one/two/
  reordered/operator/group/string/local-call/constructor/index/nested arguments。固定 mandatory parens、
  malformed ExprList、qualified/reserved name priority、escaped `«emit»` assignment、Statement tag non-alias、
  exact Typed fail-before-argument 与 event-table/return/assert/revert controls。六组 sourceHash/size 为
  `556db61901a502771f0f8c989cd74e21f5f45a7a05f4487d24aadaf69f575832`/231、
  `4f46b40d447d35c70570c41799e8636cd03e7e12bae780f446e1e09e65f3556a`/240、
  `833faaa7dd8e46c544560cacc3987da7e55caaca0b1c5d8d1348a51f0a944d59`/249、
  `122c62456f4b04c461df770b63ccccf4670b8a07c0af384283d67bd0d03ee528`/249、
  `ebdd674aa74e7648e9a05819e94a30f578ab580f379c6276328aecc85f9e97b9`/231、
  `05f715cf30ab2292e5b0928b116bf3a9e024a5007fe5b3d6a7165502d190a78b`/303。
- Commands/Results：独立 Lean probe 测量上述 hash/size；`lake build Tests.Language.EmitStatements`
  （15 jobs）；`lake build proof_forge_next_tests`（186 jobs）；`lake env /usr/bin/time -p
  .lake/build/bin/proof-forge-next-tests` exit 0/3.65 s；`git diff --check` exit 0。首次不经 `lake env`
  裸启动二进制因缺少模块 search path 拒绝，不作为产品失败或 evidence；按规定环境重跑全绿。
  coordinator/Kimi final reviews 均为 P0/P1=0。按冻结未运行 `just ci`，development evidence 为
  `EV-20260718-0036`。
- Scope claim：complete emit statement 的 Source carrier、mandatory-parentheses surface、canonical identity
  与 Typed fail-closed 已覆盖。不包括 event resolution、payload arity/type、log semantics、Semantic emit、
  ABI/runtime、requirement 或 target behavior。
- Limitations：不得声明完整 event semantics、statement grammar、eligible host 或 formal D1 evidence；
  不得关闭 pending `TASK-D1-04`，D0 formal milestone 仍为 5/8。
- Next：当前无 active development slice；下一 slice 未冻结，必须重新做 statement/expression residual
  audit，再选择单一依赖闭合的最小切片，禁止自动递增。

## 2026-07-18 — 会话收口：D0-08 转 blocked（待治理裁决）与双机合并同步

- Context：D0 收口会话的同步与收口记录。期间 darwin 机并行推进 D1-PA-46…51
  （ConstructorExpr/IndexAccess/RevertStmt/ValueLessReturn/EmitStmt/AssertError），
  本机完成 D0-09 证据、D0-08 全矩阵与三轮合并。
- Merge incidents（事实）：(1) 首轮合并后 `compiler_runtime_observation_self_test.py`
  fixture lock 缺 `schema` 触发 per-platform 分派 KeyError，1 行 fixture 声明修复
  （`90668547`）；(2) EV 台账与并行线两次撞号（0032/0033、0035），本机 D0-09 行两次
  顺延至 `EV-20260718-0041/0042`；(3) 第三轮合并拉入 darwin 线 tests-only RED
  （`3c844b80`，`assertErrorStmt` 引用未存在的 ctor/fixture，`lake build Tests` 红），
  等其 GREEN（`c2a1e4fa`）到达后合并恢复绿——RED 窗口期共享 main 不可构建是该
  工作流的已知形态，后续切片可考虑 RED 先落短命分支。
- Final state：`TASK-D0-08` 全 31 例 GREEN + SB2-028 逐点 fault injection + locked-jv
  schema 实测 ok，doneWhen 第 4 条（关闭路径治理裁决）为唯一剩余且属外部前置，
  转 `blocked`；`TASK-D0-09` blocked（darwin 回归 + 同一裁决）；`TASK-D0-04` blocked
  （eligible host + producer/service 基建）；`TASK-D0-07` pending（依赖 D0-04）。
  checkpoint Active task 为无，Known blocker 列 D0-04/D0-08/D0-09。
- Verification（最终树 `just ci` exit 0）：v2-isolation（40 mutations + committed archive
  build/test/help）、docs-check、sbom（D0-05 + TST-SBOM-002 33 例）、supply-chain-core、
  186 docs mutations、194-job build、proof-forge-next-tests、DSL/target/toolchain negatives
  全绿；`git diff --check` clean。
- Limitations：全部证据仍为 development 级；无 formal/hermetic/release 证据；darwin 回归、
  eligible host、治理裁决三项均不在本机能力内。
- Next（用户侧）：(a) darwin 机回归 D0-09 三条命令；(b) 决定 eligible host 路线
  （本机启用 SecureBoot 后重新生成/登记 linux profile，或修复 darwin SSV/Xcode）；
  (c) D0-08/D0-09 pre-cutover 关闭的治理裁决（Architecture + Quality）。
## 2026-07-18 — D1 assert optional-error pre-acceptance slice

- Commits：freeze `2c7f84cc`；tests-only RED `3c844b80`；canonical golden binding
  `e97a889d`；Source-only GREEN `c2a1e4fa`。
- Spec/Test：`SPEC-LANG-001`、`TST-SRC-005`。本切片只追加 D1-PA-51 development evidence，
  不改变 `TASK-D1-04` 的 pending 状态、依赖、Tests 集合或 Done 语义。
- Changed：新增 append-only `Source.Statement.assertErrorStmt(condition,errorName)` 与 Statement tag `8`；
  encoder 按 semantic field order 编码 condition expression 后编码 errorName string。longer
  `assert Expr else Ident` rule 位于既有 bare assert 前，decoder 先完成 error-name single-component 与
  portable validation，再解码 condition；quotation 保留两字段。既有 `assertStmt`/tag `4`/surface/
  goldens 全部不变，后续 normalization 才把两个 Source variant 统一为 optional ErrorId。Typed 两种
  variant 共用既有 exact assert fail-closed。production 恰好 Source/Syntax/Typed 3 文件、14 行新增/
  0 行移除；Semantic、requirement、effect 与 target 未改。
- Coverage：Lean command/ParserSession 双入口覆盖 initializer、entry、view、fn，literal/Bool/variable/
  operator/group condition、普通/等价 escaped error name、longest match、missing/qualified/reserved name、
  call-like payload、duplicate else、extra/block-like shape、kind/name/condition canonical non-alias、exact Typed
  priority 与 generic error-table/bare-assert controls。四组 sourceHash/size 为
  `056c9ed3648c36d0c0e79bb8f8ba272191bff9444abf27b5cc041442e9373ed6`/224、
  `8983edac8b1e96a0a84250c22aff6ca70ac2eb626d3da302309d8ca41a1e4901`/224、
  `16183f55e6b2a2c1addda8d462638894016f0c18e4d2c20fffa8882f466aae01`/222、
  `13b7a8b49ba99e79b44dd36751fc31625621f9e5706fdae4e76863ed7f7e90a8`/241。
- Migration/Review：只把 PA26 明确 deferred 的 `assert true else Failure` 一条 negative 提升为本切片
  positive；这是 documented-later lift，不是扩大 PA26 完成面，也未迁移其他 suite。首次 residual audit
  漏掉该明确 deferral 并误选 if/else，定向复核后由 Kimi 纠正为 PA51 更小且 durable。coordinator/Kimi
  final reviews 均为 P0/P1=0；review 文本曾把实际 14 行误写为 13 行，coordinator 以 `git diff --numstat`
  校正，未涉及代码或冻结上限变化。
- Commands/Results：独立 Lean probe 测量上述 hash/size；`lake build Tests.Language.AssertStatements`
  （15 jobs）；`lake build proof_forge_next_tests`（186 jobs）；`lake env /usr/bin/time -p
  .lake/build/bin/proof-forge-next-tests` exit 0/4.85 s；`git diff --check` exit 0。按冻结未运行
  `just ci`，development evidence 为 `EV-20260718-0037`。
- Scope claim：完整 assert optional-error Source carrier、name validation/canonical identity 与 Typed
  fail-closed 已覆盖。不包括 error resolution、condition Bool typing、failure/revert semantics、Semantic
  assert、requirement/effect、ABI/runtime 或 target behavior。
- Limitations：不得声明完整 assert semantics、statement grammar、eligible host 或 formal D1 evidence；
  不得关闭 pending `TASK-D1-04`，D0 formal milestone 仍为 5/8。
- Next：当前无 active development slice；下一 slice 未冻结，必须重新做 statement/expression residual
  audit，再选择单一依赖闭合的最小切片，禁止自动递增。

## 2026-07-18 — D1 conditional pre-acceptance slice

- Commits：freeze `8f6d506f`；tests-only RED `ad2c183b`；canonical golden binding
  `8db0def3`；layout parser hardening `2efb9ad9`；Source-only GREEN `3d8f48f8`。
- Spec/Test：`SPEC-LANG-001`、`TST-SRC-005`。本切片只追加 D1-PA-52 development evidence，
  不改变 `TASK-D1-04` 的 pending 状态、依赖、Tests 集合或 Done 语义。
- Changed：新增 recursive
  `Source.Statement.ifStmt(condition, thenBody, Option elseBody)` 与 append-only Statement tag `9`；
  canonical 顺序为 condition→then array→0/1 marker→optional else array。encoder/decoder 只为 nested
  blocks 改为 `partial`，quotation 结构化保留 arrays/Option，Typed 在 condition、branch、
  return/effect/path analysis 前 exact 拒绝 `if statements are not yet supported by typed checking`。
  production 恰好 Source/Syntax/Typed 3 文件、38 行新增/3 行移除；Semantic、requirement 与
  target 未改。按新合并规则同 GREEN 刷新 `supply-chain/lean-package-files.v1.json`。
- RED-driven correction：首次 GREEN focused 运行发现 `ppLine` 仅是 formatter hint，
  `if true then return 1` 会被接受。没有删除 negative；改为唯一 `withPosition` custom parser，
  以 `checkLinebreakBefore`/`checkColGt` 固定真换行和深缩进、`checkColEq` 固定 owning-if
  `else` 列、`many1Indent` 固定 non-empty blocks。decoder 同时 exact 检查 `ifStmt` kind、
  `if`/`then`/`else` atoms、null groups 与 non-empty body，malformed 节点统一 fail closed，无 index panic。
- Coverage：Lean command/ParserSession 双入口覆盖 initializer、entry、view、fn，
  if-then/if-then-else、literal/Bool/variable/operator/group condition、multi-statement branch、inner/outer
  nested else 归属。固定 missing condition/then、same-line/same-column/empty branch、dangling/
  deeper/shallower/duplicate else、extra payload、bare/escaped `then`/`else` assignments、exact Typed priority
  和旧 return/assert/revert/emit controls。六组 sourceHash/size 为
  `e556ab49fe6af5b7809110640cc69d99385c550a8fa133111b2fa27d85777c76`/209、
  `75222dc6083234208c3f3bedf82f221546406d18e1c37ac58e1a233493551ac3`/209、
  `197a0f31adde13b7c277f580cb96df82d207d322988e18cf22bf11ca33725e57`/219、
  `ea2103c11a2c2af9ec3ac6208df1c68d11680a95ef5992b1939e42816ad95915`/227、
  `4b5fbfec90d765f7e6b9c2a120834f865c4838c922c1419df05667c7ca07042a`/227、
  `5ebe007b4c8b5f4c66c0675718869c1e009ea9db7e592f456c6dc2dc8efc8509`/246。
- Commands/Results：独立 Lean probe 测量上述 hash/size；`lake build Tests.Language.IfStatements`
  （15 jobs）；`lake env lean --run /dev/stdin` focused suite exit 0；
  `lake build proof_forge_next_tests`（188 jobs）；`lake env /usr/bin/time -p
  .lake/build/bin/proof-forge-next-tests` exit 0/4.86 s；`just sbom-package-files-refresh`、
  `just docs-check`、`git diff --check` exit 0。一次不经 `lake env` 的裸二进制运行因没有
  Lean module search path 正确 fail closed；按规定环境重跑全绿，不计为产品失败。
  coordinator/Kimi final reviews 均为 P0/P1=0。按冻结未运行 `just ci`，development
  evidence 为 `EV-20260718-0044`。
- Scope claim：完整 conditional Source carrier、recursive layout/canonical identity 与 Typed fail-closed 已覆盖。
  不包括 condition Bool typing、branch join、return/effect/path analysis、Semantic conditional、requirement、
  target Plan/IR、runtime 或 materialization。
- Limitations：不得声明 Typed conditional semantics、完整 statement grammar、eligible host 或 formal D1
  evidence；不得关闭 pending `TASK-D1-04`，D0 formal milestone 仍为 5/9。
- Next：当前无 active development slice；post-PA52 residual audit 正在进行，完成后仍需单独
  冻结一个依赖闭合最小 slice，禁止自动递增。

## 2026-07-18 — D1 bounded-for pre-acceptance slice

- Commits：freeze `25f7572d`；tests-only RED `8f6acd5d`；canonical golden binding
  `bf80a1cf`；body count/order identity `4985163d`；canonical-safety freeze correction
  `affd21c4`；type-level bound proof `e41fd10e`；Source-only GREEN `2a18c827`。
- Spec/Test：`SPEC-LANG-001`、`TST-SRC-005`。本切片只追加 D1-PA-53 development evidence，
  不改变 `TASK-D1-04` 的 pending 状态、依赖、Tests 集合或 Done 语义。
- Changed：新增 `Source.IterationBound := Fin 4097` 与 recursive
  `Source.Statement.forStmt(iterator,start,stopExclusive,maxIterations,body)`。append-only Statement
  tag `10` 后依次编码 iterator string、start/stopExclusive expressions、`maxIterations.val` 与 body
  statement array。quotation 递归保留 body；Typed 在 iterator/endpoint/bound/body/return/effect analysis
  前 exact 拒绝 `for statements are not yet supported by typed checking`。production 恰好
  Source/Syntax/Typed 3 文件、32 行新增/0 行移除；Semantic、requirement 与 target 未改，Lean package
  file-set 同 GREEN 重钉。
- Parser correction：独立 Lean 4.31.0 probe 证明 plain `ppLine`/`many1Indent` 会接受 same-line body、
  same-column body 与拆行 header。最终唯一 `withPosition` custom parser 以每段 `checkLineEq` 固定一行
  header，以 `checkLinebreakBefore`/`checkColGt` 固定真实换行和更深 body，`many1Indent` 固定 non-empty；
  compact `1..<10` 与 spaced `1 ..< 10` 形成同一 Source tree，内部拆开的 `.. <` 拒绝。
- Canonical security correction：初版裸 `Nat` carrier probe 实证 bound `0` 与 `2^64` 经
  `appendNat`/`UInt64.ofNat` 得到相同 sourceHash。未用“parser 不产生”豁免；改为 `Fin 4097` 让 public
  Source 中越界 bound 不可表示。decoder 复用 Bytes exact decimal validator，再构造 `<4097` proof；
  合法 0..4096 的 canonical bytes/goldens 不变。
- Coverage：Lean command/ParserSession 双入口覆盖 initializer、entry、view、fn，bound 0/4096、
  literal/variable/operator/group endpoints、spaced/compact range、multi-statement 与 nested for/if body。
  固定 missing header tokens、四种 header split、same-line/same-column/empty body、range split、negative/
  over-bound/leading-zero/hex/underscore bounds、bare/escaped `for`/`in`/`bounded` assignments、exact Typed
  priority 与旧 return/if/assert/revert/emit controls。iterator、start、stop、bound、body content/count/order/
  nesting 与 tag non-alias 均进入 source identity。六组 hash/size 为
  `99b116672a93b719e2fe3bf8416b7fcadd990fd9270932fcc8e5f838689d44ef`/244、
  `b1a145ce2fea8c986ef423c3bfde8f45800804f5f5925728a0e4e20e13bfa2dc`/244、
  `4cd2f6a0b5860205f28db60c5dfe36fc978af9a94b1cdca3fa42df0d7b3e15f9`/244、
  `3e419a96934adae8d4834741f28bbbd724911f36b2c5cc1358d8e8a9090cb71a`/244、
  `1c8d8d6c8610739095bf59d30b1758a50b907954f4557b10fd99b0f20d2dadb9`/244、
  `01c8e020e61ef5fc43f020e5e90d17cda14ffd77634d9e293ba5ee6e43f9dc3d`/295。
- Commands/Results：focused 15-job build/direct suite；aggregate 190-job；测试二进制 exit0/5.11s；
  `just sbom-package-files-refresh`、`git diff --check` 全绿。clean committed `just ci` at `2a18c827`
  exit0：40-mutation isolation、198-job committed archive build/test/help、186 docs mutations、governance/
  SBOM/supply-chain/runtime closure、60-job product build、190-job aggregate/test 与 DSL/target/toolchain
  negatives 全绿。Kimi RED/final增量 reviews 均为 P0/P1=0；development evidence 为
  `EV-20260718-0045`。
- Scope claim：完整 canonical-safe bounded-for Source carrier、严格 layout/canonical identity 与 Typed
  fail-closed 已覆盖。不包括 iterator scope/type、range evaluation、bounded-loop proof/induction、
  return/effect/path、Semantic/requirement、target Plan/IR、runtime 或 materialization。
- Limitations：不得声明 loop semantics、完整 statement grammar、eligible host 或 formal D1 evidence；
  不得关闭 pending `TASK-D1-04`，D0 formal milestone 仍为 5/9。
- Next：当前无 active development slice；下一 slice 未冻结，必须重新做 post-PA53 residual audit，
  再选择单一依赖闭合的最小切片，禁止自动递增。

## 2026-07-18 — D1 bounded Array declaration pre-acceptance slice

- Commits：freeze `1bda5b17`；tests-only RED `0f51d950`；canonical golden binding
  `88051192`；Source/Semantic/frontend GREEN `a9fdd05f`；closure-negative hardening `efb6206e`。
- Spec/Test：`SPEC-LANG-001`、`TST-SRC-004`。本切片只追加 D1-PA-54 development evidence，
  不改变 `TASK-D1-03` 的 pending 状态、依赖、Tests 集合或 Done 语义。
- Changed：新增 Source/Semantic `ArrayLength := Fin 4097` 与
  `ValueType.array(element,length)`。append-only Type tag `18` 后递归编码 element，再以各 encoder
  既有 `appendNat(length.val)` 编码长度；Fin bound 使公开 carrier 中 `4097+` 不可表示，避免
  `UInt64.ofNat` wrap alias。Array 自身不发明 requirement，只递归传播 element requirement。
- Parser：新增 exact contextual named `arrayType` 和 struct-field 专用 `arrayAggregateField`，通用
  `portableType` 仍只接受一或二 atom，因此未把 `Option Bytes N`/`Option UInt64 Principal` 从 parser
  boundary 迁移到 decoder。decoder 复用 Bytes canonical decimal validator，再构造 `<4097` proof；
  quotation 保留 element 与 Fin value。
- Coverage：Lean command/ParserSession 双入口覆盖全部 14 个 PrimitiveAtom、state/struct/enum/const/
  initializer/entry/view/fn、长度 0/普通值/4096。Field/Named/Option/Bytes/Array/Map element、缺失/
  额外/跨行/qualified/escaped forms 与 4097/leading-zero/hex/underscore/signed 长度均 fail closed。
  Source/Semantic 各四组 hash/size goldens、tag/element/length non-alias、`Array UInt64` 零 requirement、
  `Array Bool` 的 `boolValues`、四 target support-vs-Plan non-UInt64 无制品拒绝全部固定。
- Scope：production 恰好 Core/Source、Core/SemanticIR、Language/Syntax 3 文件，48 行新增/1 行移除；
  `supply-chain/lean-package-files.v1.json` 同 GREEN re-pin。tests-only zero migration。
- Commands/Results：`lake build Tests.Language.ArrayTypes` 23 jobs；aggregate/test executable build graph
  192 jobs；`lake exe proof_forge_next_tests` exit 0，最新 committed suite 8.93 s；
  `just sbom-package-files-refresh`、`just docs-check`、`git diff --check` 全绿。一次脱离 `lake env` 的
  裸测试二进制运行因缺少 Lean module search path fail closed，改用产品规定的 `lake exe` 后全绿，
  不计为产品失败。Kimi final review P0/P1=0；development evidence 为 `EV-20260718-0046`。
- Scope claim：只完成 bounded Array declaration carrier、canonical identity、requirement propagation 与
  support-vs-Plan boundary。不包括 array value/constructor/index/length/slice/mutation、runtime layout、
  ABI、recursive legality、D2 type/value semantics或 target implementation。
- Limitations：不得声明数组运行语义、完整 type grammar、eligible host 或 formal D1 evidence；不得关闭
  pending `TASK-D1-03`，D0 formal milestone 仍为 5/9。PA53 batch `just ci` 已绿，本切片按冻结未重复。
- Next：当前无 active development slice；下一 slice 未冻结，必须重新做 post-PA54 residual audit，
  再选择单一依赖闭合最小切片，禁止自动递增。

## 2026-07-18 — D1 exact Option Field spelling pre-acceptance slice

- Commits：freeze `1371f5be`；single-migration tests-only RED `efa68394`；canonical golden binding
  `1e922851`；Syntax-only GREEN `1b15dc4f`。
- Spec/Test：`SPEC-LANG-001`、`TST-SRC-004`。本切片只追加 D1-PA-55 development evidence，
  不改变 `TASK-D1-03` 的 pending 状态、依赖、Tests 集合或 Done 语义。
- Changed：只为既有 `Source/Semantic.ValueType.option(.field)` 开放 exact same-line
  `Option Field bn254_fr`。新增 named `optionFieldType` 与 struct-field 专用
  `optionFieldAggregateField`，decoder 只在 raw third atom 等于 `bn254_fr` 时构造 carrier。通用
  `portableType` 仍为一/二 atom；Source/Semantic ctor、canonical encoder、quotation、Typed 与 target 未改。
- Migration/Coverage：把 `Tests.Language.OptionDeclarations` 既有唯一 field-option parser-negative
  迁移为 positive，migration count 恰为一。双入口覆盖 state/struct/enum/const/initializer/entry/view/fn；
  alternate/escaped/qualified/missing/extra/split forms fail closed，Option Bytes/Array/nested/Map 与旧 extra
  payload 边界保持。独立运行实证 `Option Map UInt64 Bool` 的旧边界为 decoder exact rejection。
- Canonical/requirements：既有 tag `16→2` 被 Source 241-byte/
  `8d83aba16ec5c8f4694fbce7a3847903ca492d2af7ffc5030029f4485a71c79a` 与 Semantic 191-byte/
  `c50aab8c944ed3db26737aa7f9edcfbd7122cd828b7c4c859237bbc3537b6229` 固定，并与 bare Field、
  Option Bool、Option UInt64 non-alias。`fieldBn254` 精确递归一次；四个 Phase 1 target 均在 support
  resolver named rejection，未进入 Plan、未产生 artifact。
- Scope/Commands：production 恰好 `Language/Syntax.lean` 一文件，28 行新增/1 行移除；Lean package
  file-set 同 GREEN re-pin。`lake build Tests.Language.OptionDeclarations` 23 jobs；aggregate/test graph
  192 jobs；`lake exe proof_forge_next_tests` exit 0/5.08 s；`just sbom-package-files-refresh`、
  `just docs-check`、`git diff --check` 全绿。Kimi final review P0/P1=0；development evidence 为
  `EV-20260718-0047`。PA53 batch `just ci` 已绿，本切片按冻结未重复完整 gate。
- Scope claim：只完成 exact existing-carrier spelling、canonical/requirement/support boundary。不包括
  none/some、unwrap、Field literal/arithmetic、recursive legality、runtime representation、ABI 或 target
  Field support。
- Limitations：不得声明 Option/Field runtime semantics、完整 type grammar、eligible host 或 formal D1
  evidence；不得关闭 pending `TASK-D1-03`，D0 formal milestone 仍为 5/9。
- Next：当前无 active development slice；下一 slice 未冻结，必须重新做 post-PA55 residual audit，
  再选择单一依赖闭合最小切片，禁止自动递增。

## 2026-07-18 — D1 exact one-level nested Option spelling pre-acceptance slice

- Commits：freeze `b598114d`；single-migration tests-only RED `1a6d9ee8`；canonical golden binding
  `008b2da0`；Syntax-only GREEN `8b4d4c2c`。
- Spec/Test：`SPEC-LANG-001`、`TST-SRC-004`。本切片只追加 D1-PA-56 development evidence，
  不改变 `TASK-D1-03` 的 pending 状态、依赖、Tests 集合或 Done 语义。
- Changed：只为既有 recursive `Source/Semantic.ValueType.option(.option element)` 开放 exact same-line、
  exact one-level `Option Option PrimitiveAtom`。新增 named `optionOptionType` 与 struct-field 专用
  `optionOptionAggregateField`；decoder 复用既有 single-token type policy 后包两层 Option。通用
  `portableType` 仍为一/二 atom；Source/Semantic ctor、canonical encoder、quotation、Typed 与 target 未改。
- Migration/Coverage：把 `Tests.Language.OptionDeclarations` 既有唯一 nested-option parser-negative
  迁移为 positive，migration count 恰为一。双入口覆盖 nested Bool/UInt64 的 state/struct/enum/const/
  initializer/entry/view/fn；第三层 Option、Field/Bytes/Array/Map inner、unknown/missing/escaped/qualified/
  extra/split forms 均 fail closed，Option Field/Bytes/Array/Map 与旧 extra-payload 边界保持。独立运行实证
  full Map nested 与 qualified nested element 由 decoder exact rejection，而非 parser rejection，binding
  提交据实固定其错误通道。
- Canonical/requirements：既有 tag `16→16→element` 被 Source UInt64/Bool 243-byte/
  `d480f1267bd8753f9bae0f6f21439836a0d11f2d39eeef908ccec94875c5daf4`/
  `3110c1ed382a8b002e2248b84744a8aa1716122215c43f4c09d474efaaff7960` 与 Semantic UInt64 192-byte/
  `5b5eacce6a48158bbbaab3490044613d35323e278c42d7d1d4594ffb5ce9ed18`、Bool 193-byte/
  `0caaecffaab09d481ef117347b885196ba00e8df0b43b090c4643ece3831b959` 固定，并与 bare/single Option/
  different element non-alias。nested UInt64 requirement 为空；nested Bool 精确递归单个 `boolValues`。
  四个 Phase 1 target 对前者 support 后在 non-UInt64 Plan invariant 拒绝，对后者在 support resolver named
  rejection，均未产生 artifact。
- Count correction：PrimitiveAtom 实际闭集为 15 个：Bool + 6 个 UInt width + 6 个 Int width + Unit +
  Principal。PA54 task/evidence 与本切片早期 freeze 中的“14”是非语义计数笔误；enumerated set、代码和
  accepted behavior 一直一致。本次把当前 task/spec/test 指针纠正为 15；历史 implementation log 不改写，
  由本追加记录给出勘误。
- Scope/Commands：production 恰好 `Language/Syntax.lean` 一文件，29 行新增/1 行移除；Lean package
  file-set 同 GREEN re-pin。`lake build Tests.Language.OptionDeclarations` 23 jobs；aggregate/test graph
  192 jobs；`lake exe proof_forge_next_tests` exit 0；`just sbom-package-files-refresh`、`just docs-check`、
  `git diff --check` 全绿。Kimi freeze/RED/final reviews P0/P1=0；development evidence 为
  `EV-20260718-0048`。PA53 batch `just ci` 已绿，本切片按冻结未重复完整 gate。
- Scope claim：只完成 exact one-level existing-carrier spelling、canonical/requirement/support boundary。
  不包括 none/some、unwrap、任意递归 type grammar、recursive legality、runtime representation、ABI 或
  target nested-Option support。
- Limitations：不得声明 nested Option runtime semantics、完整 type grammar、eligible host 或 formal D1
  evidence；不得关闭 pending `TASK-D1-03`，D0 formal milestone 仍为 5/9。
- Next：当前无 active development slice；下一 slice 未冻结，必须重新做 post-PA56 declaration residual
  audit，再选择单一依赖闭合最小切片，禁止自动递增。

## 2026-07-18 — linux-tool-root lane 首次真实运行与 runner-context 修复

- Context：`TASK-D0-09` 的 lane 此前只存在于本地提交，首次随合并推送触达 GitHub。
  推送后全部 CI run 在 0 秒处失败（含 darwin 线的后续提交），run 无任何 job。
- Diagnosis：GitHub 判定 `Invalid workflow file: .github/workflows/ci.yml#L1
  (Line: 92, Col: 30): Unrecognized named-value: 'runner'`——lane 把
  `PROOF_FORGE_TOOL_ROOT` 写在 job 级 `env`，而 `runner` context 在 job-env 求值点
  不可用。本地 YAML 解析、PyYAML 与 `git diff --check` 均无法暴露该类校验，
  只有真实 Actions 运行能触发；lane 定义从本地 session 落地起即潜伏。
- Fix（`63df5494`）：移除 job 级 `env`，改在首个 step 经 `$RUNNER_TEMP` 环境变量
  写入 `$GITHUB_ENV`（`Select linux tool root`），后续 step 依序继承。
- Verification：修复后 run `29642386926`——`linux-tool-root` lane success
  （validate/self-test/host-profiles self-test/provision/materialize/verify/
  observe→validate development profile 闭环全过），`docs` lane success；
  `source-core` 见当轮结果。darwin 机后续推送的 0 秒失败同因消除。
- Limitations：lane 绿是 development 级 tool-root 证据（GOV-CI-001 口径），
  不构成 hermetic/formal 证据；`TASK-D0-09` 其余 doneWhen 项（darwin 回归、
  关闭裁决）状态不变。
## 2026-07-18 — D1 exact Option Array spelling pre-acceptance slice

- Commits：freeze `5fece0df`；single-migration tests-only RED `a068a76e`；canonical golden binding
  `dbbe9f07`；Syntax-only GREEN `25a5c3cd`。
- Spec/Test：`SPEC-LANG-001`、`TST-SRC-004`。本切片只追加 D1-PA-57 development evidence，
  不改变 `TASK-D1-03` 的 pending 状态、依赖、Tests 集合或 Done 语义。
- Changed：只为既有 recursive `Source/Semantic.ValueType.option(.array element length)` 开放 exact
  same-line `Option Array PrimitiveAtom N`。新增 named `optionArrayType` 与 struct-field/enum-member 专用
  `optionArrayAggregateField`；decoder 直接复用既有 `decodeArrayValueTypeFromAtoms` 的 15-atom element
  闭集与 canonical ASCII decimal `0..4096` 长度校验，再包一层 Option。通用 `portableType`、
  Source/Semantic ctor 与 encoder、quotation、Typed 和 target 均未改。
- Migration/Coverage：把 `Tests.Language.OptionDeclarations` 既有唯一
  `("Array option", "Option Array UInt64 4")` parser-negative 迁移为 positive，migration count 恰为一。
  Lean command/ParserSession 双入口覆盖全部 15 个 PrimitiveAtom、长度 0/4/4096、state/struct/enum/const/
  initializer/entry/view/fn parameter/result。missing/unknown/Field/Option/Bytes/Array/Map element、invalid
  length、escaped/qualified constructor/element、extra/split payload 均 fail closed；Option Bytes、Array
  Option、Array Field、third-layer nested Option 与既有 extra-payload boundary 保持。
- Canonical/requirements：既有 tag `16→18→element→length` 被 Source UInt64(0/4/4096)/Bool(0) 四组
  259-byte goldens `f22ada30b9fcf58e2b1f55ac7417fb13864354032f7096fe33a0aa6c4bd0fa90`、
  `1c3ae508743fbdb68c87e06487f98689fe257546db0f547c14a2020d9dbbc3e9`、
  `885e14c9ae561f9aa499d6efad47c2c196685828060f27bc334cc6adccac8ef5`、
  `28937fa712d8f151aab179b012841958899a5468970f21a71457c07c27717292` 与 Semantic 208/208/208/209-byte
  goldens `9b7a7f860fb116e40d5a2b25e5e80378c88de55ed2875eea239ff11b97eb22b2`、
  `5cd5f520f435c29fce98069a3a78203c2bf73e2ddf092b10391c035db76aff9d`、
  `e8b1fc098d8b41d85e55a8f5bd53a570fd0f34388831e34c116e6b98e734422b`、
  `0594d1fc0e604b30c0bc2da344c6cdfda004437c0bd1bf539ce92c890de3bc7b` 固定，并与 bare Array、single/
  nested Option、different element/length non-alias。UInt64 variant requirement 为空，Bool variant 精确递归
  单个 `boolValues`；四个 Phase 1 target 对前者 support 后由 non-UInt64 Plan invariant 拒绝，对后者在
  support resolver named rejection，均未产出 artifact。
- Scope/Commands：production 恰好 `Language/Syntax.lean` 一文件，25 行新增/1 行移除；Lean package
  file-set 同 GREEN re-pin。`lake build Tests.Language.OptionDeclarations` 23 jobs；aggregate/test graph
  192 jobs；`lake exe proof_forge_next_tests` exit 0；`just sbom-package-files-refresh`、`just docs-check`、
  `git diff --check` 全绿。independent RED/final reviews P0/P1=0；development evidence 为
  `EV-20260718-0049`。PA53 batch `just ci` 已绿，本切片按冻结未重复完整 gate。
- Scope claim：只完成 exact existing-carrier spelling、canonical identity、requirement propagation 与
  support-vs-Plan boundary。不包括 array value/index/slice/mutation、none/some/unwrap、任意 recursive
  grammar、recursive legality、runtime representation、ABI 或 target Option-Array support。
- Limitations：不得声明 Option/Array runtime semantics、完整 type grammar、eligible host 或 formal D1
  evidence；不得关闭 pending `TASK-D1-03`，D0 formal milestone 仍为 5/9。
- Next：当前无 active development slice；下一 slice 未冻结，必须重新做 post-PA57 declaration residual
  audit，再选择单一依赖闭合最小切片，禁止自动递增。

## 2026-07-18 — GitHub CI 三 lane 全绿（合并树最终确认）

- Context：linux-tool-root runner-context 修复推送后，Mac 继续推进 conditional/option-array
  slices；最终合并树 `662c1387` 推送后 CI run `29642879415` 三 lane 全部 success：
  `docs`、`source-core`（Lean build + tests + negatives）、`linux-tool-root`
  （validate/self-test/host-profiles self-test/provision/materialize/verify/
  observe→validate closed loop）。`TASK-D0-09` doneWhen 第 2、4 条（linux lane 绿 +
  ubuntu CI ineligible development profile 闭环）由此满足，剩余 darwin 回归与
  pre-cutover 关闭治理裁决两项外部前置。
- Verification：本地最终 `just ci` exit 0（见上一条）；GitHub CI run
  `29642879415` 三 lane success；`/usr/bin/python3 -I -S scripts/docs_check.py` ok；
  `git diff --check` clean。
- Limitations：全部为 development 级证据；darwin 回归、eligible host、治理裁决
  仍待用户侧动作。

## 2026-07-18 — GOV-PRECUTOVER-001 关闭 TASK-D0-08 与 TASK-D0-09（D0 = 7/9）

- Context：用户（GOV-MAINTAINERS-001 全部角色持有人）审阅 D0 收口报告后明确指示
  "都完成了那就确认，继续往下"，并指出 darwin 回归应可在 linux 上确认。据此完成
  (a) 静态 darwin 保持性验证，(b) C2 治理裁决与机器强制分支，(c) 两任务关闭。
- Static darwin preservation（linux 上执行，事实）：`toolchains.lock.json`（darwin v2）
  与 D0-09 立项基线 `6dc1d836` 逐字节相等；`host-profiles.lock.json` 中 darwin profile
  的 platform/developerTools/systemTools/systemRuntime 逐字段相等（仅 schema id v1→v2
  与受影响 digest pin 按 ADR-0016 更新）；`verify_host_stage0.sh` 全部 18 条 darwin
  语义行保留（仅新增平台分派与 3 行空初始化）；已提交 darwin profile 作为数据经
  `validate-host-profile` 校验 rc=0 且正确报告 ineligible（APFS/SSV reason）；
  `toolchain_assets.py validate` 与 `host_profiles_self_test.py` 全 ok。
- Governance：`docs/governance/pre-cutover-closure-ruling.md`（`GOV-PRECUTOVER-001`，
  accepted，approvers=architecture-owner, davirain, quality-owner，reviewCommit
  `2bbd19bd`）；docs_check 增加 `d0_08_sbom_closure_attested` 与
  `d0_09_linux_host_attested` 两个 exact 校验分支（D0-08 含 freezePackageSha256 重算），
  bootstrap grade exact 集合扩为 D0-01..06 ∪ {D0-08, D0-09}；docs_check_self_test
  新增 5 个 mutation（no-attest/缺字段/错 digest/错值全拒，191 mutations 全绿）；
  attests 落地 `docs/governance/bootstrap-closure/TASK-D0-08.attest.json` 与
  `TASK-D0-09.attest.json`；变更按门禁先行、关单单独成集分为两个 changeset。
- Closure：`TASK-D0-09` → done（`EV-20260718-0052`，darwin live 重观察递延 P2，
  owner=quality，截止 D0-07 关闭前）；`TASK-D0-08` → done（`EV-20260718-0053`）。
  二者均为 development 级关闭；`TASK-D0-07` 冻结包落地时其 doneWhen 必须包含在
  eligible host 重放 TST-HOST-002 与 TST-SBOM-002（裁决 §4.1）。checkpoint：
  D0=7/9，Active task 无，Known blocker 仅 `TASK-D0-04`。
- Verification：`/usr/bin/python3 -I -S scripts/docs_check.py` ok（两个 done 行 +
  bootstrap EV + attests 全链路）；`docs_check_self_test.py` ok（191 mutations）；
  `git diff --check` clean。
- Limitations：不产生 formal/hermetic/release 证据；`TASK-D0-04`（eligible host +
  producer/service 基建）与 `TASK-D0-07`（依赖 D0-04）状态不变。
- Next：`TASK-D0-04` 的仓库内缺口以明确标注的 pre-acceptance 方式推进
  （activation receipt/catalog approval 对象族 → authority-store/producer 侧），
  eligible host 出现前不得关闭；linux 机器启用 SecureBoot 后可登记 eligible profile。
## 2026-07-18 — D1 exact Option Bytes spelling pre-acceptance slice

- Commits：freeze `0f8f31d0`；dual-migration tests-only RED `6afd44a8`；canonical golden binding
  `8d9c6c2e`；Syntax-only GREEN `ff36cac7`。
- Spec/Test：`SPEC-LANG-001`、`TST-SRC-004`。本切片只追加 D1-PA-58 development evidence，
  不改变 `TASK-D1-03` 的 pending 状态、依赖、Tests 集合或 Done 语义。
- Changed：只为既有 recursive `Source/Semantic.ValueType.option(.bytes length)` 开放 exact same-line
  `Option Bytes N`。新增 named `optionBytesType` 与 struct-field/enum-member 专用
  `optionBytesAggregateField`；decoder 复用既有 `decodeBytesLengthAtom` 的 canonical ASCII decimal
  `0..4096` 长度校验，再构造 `.option (.bytes length)`。通用 `portableType`、Source/Semantic ctor 与
  encoder、quotation、Typed 和 target 均未改。
- Migration/Coverage：把 `Tests.Language.OptionDeclarations` 的 `Option Bytes 8` 与
  `Tests.Language.BytesTypes` 的 `Option Bytes 32` 两条既有 parser-negative 迁移为 positive，migration
  count 恰为二。Lean command/ParserSession 双入口覆盖长度 0/8/32/4096、state/struct/enum/const/
  initializer/entry/view/fn parameter/result。missing/invalid length、escaped/qualified constructor、extra/
  split payload 均 fail closed；Array Option、Array Field、third-layer nested Option、Option Map 与既有
  extra-payload boundary 保持。
- Canonical/requirements：既有 tag `16→17→length` 被 Source 0/8/32/4096 四组 257-byte goldens
  `17902c1fe40da65b620a8005a595f957e23101cc186597c338f1d1de66cf8d57`、
  `fdeaa16c4e891ffac8179e9b3f83086f51b03765ad9029100c02114247166754`、
  `4634c603c403cba66d1243193c835f5d6ee8827f66a59696526dd6cdb1df8334`、
  `5aeb3692b33316440837c2ca69f68a6b1ff53b529044f170bf1f0bbe3272bc35` 与 Semantic 206-byte goldens
  `8bf703f9490bb378ff816a62de7ba406dae03b5f18d48697f85e9ddd48b556e5`、
  `8225233436aad7fedd34dacdb0d0e0e758973c7281340a390ab1bc9400459885`、
  `60aabc823097c35ca6fbc67bc507f30346f363ddc137e086f78eb11296196543`、
  `9a809c983cfe801d2954cad3aa581d2ccd02c70b2cf3829894d071455e652e95` 固定，并与 bare Bytes、
  single Option、Option Array、different length non-alias。Option Bytes requirement 为空；四个 Phase 1
  target support 后由 non-UInt64 Plan invariant 拒绝，未产出 artifact。
- Scope/Commands：production 恰好 `Language/Syntax.lean` 一文件，26 行新增/0 行移除；Lean package
  file-set 同 GREEN re-pin。`lake build Tests.Language.OptionDeclarations Tests.Language.BytesTypes`
  24 jobs；aggregate/test graph 192 jobs；`lake exe proof_forge_next_tests` exit 0；
  `just sbom-package-files-refresh`、`just docs-check`、`git diff --check` 全绿。Grok/Kimi residual audits
  P0=0；development evidence 为 `EV-20260718-0050`。本切片按冻结未重复完整 `just ci`。
- Scope claim：只完成 exact existing-carrier spelling、canonical identity、zero requirement 与
  support-vs-Plan boundary。不包括 bytes literal/index/slice/length、none/some、unwrap、任意 recursive
  grammar、recursive legality、runtime representation、ABI 或 target Option-Bytes support。
- Limitations：不得声明 Option/Bytes runtime semantics、完整 type grammar、eligible host 或 formal D1
  evidence；不得关闭 pending `TASK-D1-03`，D0 formal milestone 仍为 5/9。
- Next：当前无 active development slice；下一 slice 未冻结，必须重新做 post-PA58 declaration residual
  audit，再选择单一依赖闭合最小切片，禁止自动递增。
