---
id: PHASE-6
title: 实现日志
status: draft
owner: engineering
updated: 2026-07-16
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
