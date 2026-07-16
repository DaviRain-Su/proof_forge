---
id: SPEC-SEC-001
title: 安全与隐私规格
status: proposed
owner: security
updated: 2026-07-15
normative: true
---

# 安全与隐私规格

## 资产与攻击者

资产：业务语义、private witness/secret、制品完整性、toolchain/registry 身份、输出目录、
发布签名和用户密钥。攻击者可控制 source、CLI 参数、cwd/env、外部工具输出、RPC 响应、
artifact consumer 输入和部分文件系统；不得假定父目录或 PATH 可信。

## 信任边界

Lean kernel/toolchain 与已校验 V2 source 是最小 TCB；外部 packager、prover、validator、
runtime、RPC、network profile 和父项目均不可信。编译器不执行 source 任意 Lean code、
动态 plugin、build script 或 network fetch。

## 强制控制

- 输入：16 MiB/source、100000 nodes、nesting 256、循环/调用/effect/output limits。
- 进程：tool path 来自 lock-resolved absolute path；清理 env；timeout；stdout/stderr cap；
  不经 shell 拼接参数；验证 exit code、version、hash 和产物。
- 文件：output root containment、open-no-follow、拒绝 symlink/hardlink escape、临时目录
  `0700`、原子 rename、无 world-writable executable search path。
- 网络：check/build/emit 默认 deny；deploy/prove（若 remote）需显式 network policy。
- secret：private key 只能通过 OS secret provider/FD 输入，不能是 CLI、env、manifest、log。
- 隐私：taint/disclosure 检查覆盖 explicit/implicit flow；witness 目录 `0700/0600` 且不进入
  OutputSet；失败清理；core dump 禁用。
- 供应链：exact commit/version、asset checksum、license、SBOM、签名/来源记录。
- 构建：registry 静态、dirty release 禁止、reproducible/clean-room gate required。

development sandbox 使用独立 deny-default stage policies、关闭继承 FD、`/dev/null` stdin、
bounded pipes、固定 timeout 和 current-user `0400` single-link receipts。launcher 在 leader
被 reap 前清理其原 process group，以降低 descendant-held pipe、timeout/output-cap 与
PGID-reuse 风险。

这不是 formal process containment：fork 后的 descendant 可调用 `setsid()` 逃离原 group。
formal runner 必须提供 workload 无法逃逸的 session/job/VM 边界。stage 外的失败 tail 先转成
ASCII representation 再输出，可阻止 ANSI/OSC/control bytes 操纵终端，但不会自动删除
printable secret；正式日志在 retained/private scan/redaction 前不得直接回显。

## ZK 特有控制

Noir Phase 1 禁止 unconstrained functions、foreign/oracle、未批准 Brillig、递归证明和动态
black-box op；出现时 `PF-REQ-UNSUPPORTED`。public input 顺序和 verification key 绑定到
semantic/plan hash；prove 前重算 circuit hash，verify 检查 proof/VK/public-input 三者。
private input 不得出现在 error branch、artifact、diagnostic、telemetry 或 cache key。

## Chain 特有控制

EVM selector/storage collision、delegate/static/value call 模式；Solana account owner/signer/
writable/order/PDA；NEAR predecessor/signer、attached value、Promise callback/receipt commit；
均由 target Plan validator 覆盖。Phase 1 Counter 不开放 arbitrary external call/deploy。

## 安全失败

安全检查失败一律 error，不允许 warning override。资源超限 `PF-RESOURCE-LIMIT`，不可信
工具 `PF-TOOL-UNTRUSTED`，路径 `PF-OUTPUT-PATH`，披露 `PF-VIS-001`。`--force` 只允许
替换输出目录，不绕过任何安全/语义/版本检查。

## Attack Matrix 与验收

必须测试 path traversal/symlink/TOCTOU、argument injection、恶意 executable shadowing、
env poisoning、inherited writable FD/interactive stdin、巨大/二进制/ANSI stderr、
descendant-held pipe、fast leader/PGID reuse、`setsid()` escape、timeout/fork bomb、
policy/receipt replacement、diagnostic printable-secret leak、artifact zip bomb、hash collision
格式、manifest duplicate key、private explicit/implicit leak、malicious proof/VK/public input、
RPC wrong chain/replay、registry/profile spoof、parent cache/import/binary 泄漏、concurrent output、
disk-full rollback、compiler panic。关联 `NFR-003/004/008/009`、`TST-SEC-001`、
`TST-VIS-*`、`TST-ISO-*`；P0/P1 finding 阻断 release。
