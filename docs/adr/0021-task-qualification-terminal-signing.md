---
id: ADR-0021
title: Task qualification protected acceptance 的一次性终结签名
status: in_review
owner: architecture
updated: 2026-07-24
normative: true
---

# ADR-0021：Task qualification protected acceptance 的一次性终结签名

## 背景

accepted `SPEC-TASKQUAL-001` §8.4 同时规定：

1. production protected consumer 的唯一入口恰为七个 required positional 参数；
2. 五个继承 channel 中只有 `authorityStoreFd` 是 authenticated service channel；
3. `pf.taskqual.authority-store.rpc.v1` 只允许 lookup；
4. 运行后生成的 `ProtectedTaskQualificationAcceptanceV1` 必须由 current
   Architecture + Quality + Security 三个 distinct principals 对独立 acceptance domain 会签。

最终 acceptance statement 只有在 trusted clock、current revocation head、safe-open archive/Git、
live session、profile/pin、provenance bundle 和 pure verifier 全部验证完成后才能确定。当前七参数
入口、closed provenance roles 与 lookup-only store 均没有 signer capability；public policy 也不能推导
Ed25519 private signature。handoff signature、store service signature 与 acceptance signature覆盖不同
wire、message domain和授权语义，不能复制或复用。

因此当前 accepted contract 不可实现。现有 `ProtectedAdapterInput.signing_seeds` 是规范外 caller
注入，只能用于 synthetic test，不能形成 `production-candidate-bound` authority。

## 决定摘要

1. production protected API 保持七参数不变，adapter 永远不接触 role private key。
2. `pf.taskqual.authority-store.rpc.v1` 保持 lookup-only；production 改为 major-versioned
   `pf.taskqual.authority-store.rpc.v2`。
3. v2 只在同一 authenticated session 的 exact lookup closure 后增加一次 terminal
   `sign-acceptance`；它不是任意 message/digest signer。
4. signed handoff 是三个 authority roles 对 exact task/operation/run/nonce/head/profile/adapter 的
   one-shot delegation；final role signatures 是该 delegation 下 pinned adapter 成功结论的机器签发，
   不冒充三次 post-result 人工 review。
5. 新 service/custody/durable nonce capability 相对原冻结包属于扩面；D0-10 只能经本文的正式
   Freeze Exception 路径重冻结后承载。在 exception accepted 前保持 `blocked`。
6. activation后的真实Linux probe证明首次accepted capability checkpoint不可达：普通non-root static exec在
   `CapInh/CapAmb=0`时清空`CapPrm/CapEff`，只持有`CAP_SYS_PTRACE`又不能执行需effective
   `CAP_SETPCAP`的`PR_CAPBSET_DROP`。本纠错在同一v2 surface内固定`CAP_SETPCAP+CAP_SYS_PTRACE`
   ambient exec bridge，并在service第一段受信代码内先清bounding/ambient/inheritable/SETPCAP，再允许
   post-exec service读取已打开seed FD、接收packet或检查peer；supervisor在durable `active`后、exec前的既有
   seed读取顺序保持不变。
7. corrected RED后的GREEN审计又确认：既有profile同时签入`artifact:ContentRefV1`与
   `payloadSha256`，却没有为raw executable/closure/build-policy/tool/probe/scanner bytes定义ContentRef owner；
   仅验证plain hash不能证明独立ref。本文在不改变七参数API、profile/frame wire、TST ID或Exception surface的
   前提下，增加taskqualification-owned raw payload schema及closed role→owner registry；unknown schema、
   fixture schema与跨role owner masquerade全部fail closed。

## 1. 唯一 protected API

production API 仍且只能是：

```text
protect_taskqualification_v1(operationBytes, handoffBytes,
  authorityPolicyFd, authorityStoreFd, candidateArchiveFd,
  provenanceBundleFd, trustedClockFd)
```

七个参数均 required positional-only；禁止 path、environment、kwargs、default、typed shortcut、
signing seed、private-key bytes、HSM handle 或 signer callback。继承 FD 集合仍恰为 `0,1,2` 加后五个
FD；五个 channel 的 distinct/read-only/stable-fstat/safe-open规则不变。唯一C3变化是
`authorityStoreFd`在v2必须为connected Linux `AF_UNIX/SOCK_SEQPACKET`，v1继续为原`SOCK_STREAM`；两者
不得协商或互读。

## 2. v2 service descriptor

v1 descriptor/frame/client 继续只表达 historical lookup-only 协议。§8.4 production 只接受以下 v2
closed descriptor；字段恰含且 record 顺序如下：

```text
TaskQualificationAuthorityStoreServiceV2 {
  schema: "proof-forge.task-qualification-authority-store-service.v2",
  id, version: "2.0.0",
  namespace: "task-qualification-production-v1",
  protocol: "pf.taskqual.authority-store.rpc.v2",
  servicePublicKey,
  verifier: VerifierIdentityV1,
  supervisor: VerifierIdentityV1,
  isolationPolicy: ContentRefV1,
  signingKeyIds: [keyId],
  custodyKind: "one-time-seed-fd-v1",
  adapterUid, adapterGid, serviceUid, serviceGid,
  userNamespace: LinuxNamespaceIdentityV2,
  seedRoot: LinuxDirectoryIdentityV2,
  peerInspectionProfile: "linux-pidfd-proc-cross-uid-v1",
  maximumFrameBytes: 4194304,
  maximumTerminalAcceptances: 1
}
```

descriptor id固定`task-qualification-store-service-<runId>`，其中runId exact等于signed handoff。nested types
恰为`LinuxNamespaceIdentityV2{device,inode}`与`LinuxDirectoryIdentityV2{device,inode}`；四个值均为PF-JCS
safe integer且由ceremony对`/proc/self/ns/user`与pre-opened seedRootFd的stable fstat取得。

`isolationPolicy`只允许以下closed wire；全部record field order恰为所列顺序：

```text
LinuxIdMapEntryV2 { insideId, outsideId, length: 1 }
LinuxMountEntryV2 {
  target: string, source: LinuxDirectoryIdentityV2,
  readOnly, noSuid, noDev, noExec
}
TaskQualificationFixedFdRoleV2 { process, stage, role, fd, closeOnExec }
TaskQualificationSeccompArgRuleV2 { index, operation, value, mask }
TaskQualificationSeccompSyscallRuleV2 {
  syscall, action: "allow", arguments: [TaskQualificationSeccompArgRuleV2]
}
TaskQualificationSeccompPolicyV2 {
  stage, auditArch: "AUDIT_ARCH_X86_64", defaultAction: "kill-process",
  noNewPrivs, rules: [TaskQualificationSeccompSyscallRuleV2]
}
TaskQualificationStoreIsolationPolicyV2 {
  schema: "proof-forge.task-qualification-store-isolation-policy.v2",
  id, version: "2.0.0", namespace: "task-qualification-production-v1",
  taskId, operation, runId, nonce,
  userNamespace: LinuxNamespaceIdentityV2,
  parentPidNamespace: LinuxNamespaceIdentityV2,
  adapterPidNamespace: LinuxNamespaceIdentityV2,
  serviceMountNamespace: LinuxNamespaceIdentityV2,
  adapterMountNamespace: LinuxNamespaceIdentityV2,
  uidMap: [LinuxIdMapEntryV2], gidMap: [LinuxIdMapEntryV2],
  adapterUid, adapterGid, serviceUid, serviceGid,
  serviceProcRoot: LinuxDirectoryIdentityV2,
  durableStateRoot: LinuxDirectoryIdentityV2,
  seedRoot: LinuxDirectoryIdentityV2,
  serviceMounts: [LinuxMountEntryV2], adapterMounts: [LinuxMountEntryV2],
  fdRoles: [TaskQualificationFixedFdRoleV2],
  socketDomain: "AF_UNIX", socketType: "SOCK_SEQPACKET",
  socketCreation: "socketpair", socketSendFlags: "MSG_NOSIGNAL",
  passCredentials: true, requestedSocketBufferBytes: 4194304,
  minimumEffectiveSocketBufferBytes: 8388608,
  preSeedCapabilities, custodyCapabilities, adapterCapabilities,
  finalServiceCapabilities,
  serviceExecutableFd, serviceArgv, serviceEnvironment,
  execOperation: "execveat-at-empty-path", staticElfRequired: true,
  seccompPolicies: [TaskQualificationSeccompPolicyV2],
  maximumFrameBytes: 4194304, maximumTerminalAcceptances: 1
}
```

policy id固定`task-qualification-store-isolation-<runId>`；tuple逐字段exact handoff，namespace/UID/GID/seedRoot
逐字段exact descriptor。所有namespace/directory/FD/capability整数为PF-JCS safe integer。uidMap/gidMap各按
insideId升序唯一且恰含adapter/service两个length-1 entry，outsideId是四个distinct host subordinate IDs；
`fdRoles`按process、stage、role ASCII升序唯一，exact覆盖adapter七参数及§7 pre/post/steady service sets，FD为
非负safe integer且同process/stage内唯一；`closeOnExec`是boolean并须与每个transition前后`F_GETFD` exact。mount entries按target UTF-8 byte升序唯一；target必须是NFC UTF-8
canonical absolute path，encoded length `1..4096`，每个非空component length `1..255`且不得为`.`/`..`、空
component、NUL或trailing slash；source由ceremony stable fstat。除pinned executable/runtime closure所需mount外
均readonly，adapter set不得含seed/durable/service proc root，service set不得含candidate-writable mount。

capability arrays按numeric capability升序唯一且不由实现推断“需要”：preSeedCapabilities固定为
`[6,7,8,19,21]`（Linux `CAP_SETGID,CAP_SETUID,CAP_SETPCAP,CAP_SYS_PTRACE,CAP_SYS_ADMIN`），
custodyCapabilities固定为`[8,19]`（`CAP_SETPCAP,CAP_SYS_PTRACE`），adapterCapabilities与
finalServiceCapabilities固定为空。共同U建立前的host mapping authority属于candidate-external ceremony，
不得增加到上述U内arrays。`custodyCapabilities`只表示static exec前后不可分割的短暂transition closure，
不是steady service authority；capability五组exact checkpoints固定为：

| checkpoint | CapBnd | CapPrm | CapEff | CapInh | CapAmb |
|---|---|---|---|---|---|
| 紧邻static `execveat`前 | `[8,19]` | `[8,19]` | `[8,19]` | `[8,19]` | `[8,19]` |
| static exec后第一条service transition逻辑入口 | `[8,19]` | `[8,19]` | `[8,19]` | `[8,19]` | `[8,19]` |
| transition完成、任何post-exec service seed-FD读取/packet/peer inspection前 | `[]` | `[19]` | `[19]` | `[]` | `[]` |
| terminal role signing前 | `[]` | `[]` | `[]` | `[]` | `[]` |

任一checkpoint extra/missing bit均拒绝；特别禁止把`CAP_SETPCAP`带入steady service，或在bounding set清零前
先删除其effective bit。serviceArgv恰为`["proof-forge-taskqualification-store-v2"]`，
serviceEnvironment恰为空array。seccompPolicies按stage恰为`adapter`、`custody-pre-exec`、`service-final`；rules
按syscall number、arguments升序唯一，argument index `0..5`，operation只允许`eq|masked-eq`，value/mask为
unsigned 64-bit lowercase 16-hex。三个rules arrays本身就是candidate-external Architecture+Quality+Security
签入handoff/descriptor的**完整**stage allowlist；实现不得补默认runtime syscall、删rule或自行判断“等价”。未列
syscall由defaultAction拒绝，因此两个consumer只需exact解析并加载同一table，不存在隐式allowlist。
除此exact policy authority外仍有不可放宽的hard constraints：adapter和service tables不得含
`fork|vfork|clone|clone3|dup|dup2|dup3|pidfd_getfd|sendmsg|sendmmsg|execve`；adapter与service-final也不得含
`execveat`；custody-pre-exec的`execveat`必须是唯一exec rule且只对serviceExecutableFd/`AT_EMPTY_PATH`
放行scalar args；`custody-pre-exec`必须且只可为post-exec capability收敛额外允许两次
`prctl(PR_CAPBSET_DROP,19|8,0,0,0)`（19先于8）、一次
`prctl(PR_CAP_AMBIENT,PR_CAP_AMBIENT_CLEAR_ALL,0,0,0)`、一次`capset`及叠加final filter所需的exact
`seccomp` scalar rule；因为BPF不能解引用`capset`指针，pinned static code与每步后的五组kernel state exact
recheck共同构成authority。`service-final`只可保留terminal all-zero drop所需的`capset`，不得保留上述
bounding/ambient `prctl`。proc/durable `openat` rules只能用policy fixed dirfd和本ADR scalar flags，禁止
`open|openat2|creat`及AT_FDCWD；任何filtered stage不得允许
`setuid|setgid|setreuid|setregid|setresuid|setresgid|setfsuid|setfsgid|setgroups`，任何stage不得允许
`ptrace|process_vm_writev|mount|umount2|pivot_root|chroot|setns|unshare`，setup动作必须在
filter加载前完成。加载者按policy auditArch把syscall名解析到唯一number；unknown syscall/argument、duplicate、
违反hard constraint或实际加载bytes与canonical table不一致均拒绝。policy canonical full digest domain固定
`pf.taskqual.store-isolation-policy.v2`；`store-isolation-policy` provenance bytes必须exact解析并重算该ref，
禁止opaque JSON/hash-only policy。

`servicePublicKey` 是32-byte Ed25519 lowercase hex；`signingKeyIds` 按 keyId ASCII严格升序唯一，
恰为三个 key，分别映射 current activated `BootstrapAuthorityPolicyV1` 中 Architecture、Quality、
Security fixed rule 的三个 distinct principals。service key/keyId不得等于或复用任一 role key。
四个UID/GID均为safe integer `1..2^31-1`且不是Linux overflow ID 65534；它们定义为descriptor.
userNamespace所指同一个ceremony user namespace中、service `SCM_CREDENTIALS` receiver view看到的kernel
IDs。adapter/service都必须映射这四个ID，`adapterUid != serviceUid`、`adapterGid != serviceGid`，且不得有
共同supplementary group；unmapped/overflow值拒绝。它们是candidate-external host profile values并由signed
descriptor/handoff钉住。ContentRef full digest domain固定为`pf.taskqual.authority-store-service.v2`。

handoff `authorityStoreService` 必须指向该v2 descriptor；descriptor exact bytes/ref、service verifier、
supervisor identity、isolation policy、service peer与current store lookup结果逐字段相等。v2 protected
provenance bundle在historical v1 exact roles外增加且只增加
`trusted-clock-{executable,closure,build-policy}`、`store-supervisor-{executable,closure,build-policy}`与
`store-isolation-policy`七个role；adapter和ceremony
分别safe-open/recompute这些payload，supervisor必须从对应identity启动，isolation policy bytes必须exact
描述本ADR的UID/GID mapping、namespace、capability drop、seccomp、socket buffer与FD roles。supervisor三件套
与isolation policy四个refs逐字段join descriptor；trusted-clock三件套逐字段join handoff/lookup/clock observation；
两组refs都不得由candidate或CLI选择。v1 schema/protocol/version、unknown custody、不同
frame bound或`maximumTerminalAcceptances != 1`均在任何role curve work前拒绝。

### 2.1 Raw payload `ContentRef` owner 与 closed dispatch

本协议新增且只新增一个taskqualification-owned raw immutable payload identity：

```text
TaskQualificationArtifactPayloadRefV1 = ContentRefV1 where
  schema = "proof-forge.task-qualification-artifact-payload.v1"
```

令`id`使用SPEC-COMMON-001 profile-id grammar，`version`是canonical SemVer，`payloadBytes`为
`1..67108864` exact bytes；其digest唯一为：

```text
SHA-256(
  ASCII("pf.taskqual.artifact-payload.v1") || NUL ||
  UTF8(id) || NUL || UTF8(version) || NUL || payloadBytes
)
```

raw bytes不要求UTF-8/PF-JCS且不做canonicalization。该ref不是wrapper object、bundle member或plain checksum；
同payload不同id必须产生不同digest。profile的`payloadSha256`仍独立等于`SHA-256(payloadBytes)`，两者都必须
重算并逐字相等，禁止用其中一个填另一个、只验证一个或接受caller-supplied digest callback。

production profile artifact的role→owner dispatch固定为：

| logical role | 唯一允许的artifact schema/owner |
|---|---|
| `resolved-tool/*`,`resolved-tool-closure/*`,`resolved-probe/*`,`sandbox-policy/*`,`verifier-executable/*`,`verifier-closure/*`,`verifier-build-policy/*`,`private-scan-scanner/*` | `proof-forge.task-qualification-artifact-payload.v1` / 本节raw公式 |
| `private-scan-policy/*` | `proof-forge.private-scan-policy.v1` / accepted `scripts/private_scan.py::private_scan_policy_ref` |
| `authority-store-service/*` | `proof-forge.authority-store-service.v1` / accepted `scripts/authority_store.py::descriptor_content_ref` |
| `host-observation/*` | `proof-forge.host-observation.v1` / accepted `scripts/stage0_handoff.py` raw-byte ref规则 |
| `host-profile/*` | `proof-forge.host-profile.v1` / accepted `scripts/stage0_handoff.py` raw-byte ref规则 |
| 六个`bootstrap-verifier-*`/`protected-consumer-*` top-level roles | `proof-forge.task-qualification-artifact-payload.v1` / 本节raw公式 |

protected-only identity payload同样closed：`authority-store-*`、`adapter-*`、`snapshot-parser-*`、
`trusted-clock-*`及`store-supervisor-*`的executable/closure/build-policy三件套只能使用本节raw schema；
`authority-store-service-descriptor`只能使用本文v2 descriptor schema/domain；`store-isolation-policy`只能使用
本文isolation-policy schema/domain。每个三件套逐字段exact join其已验
`VerifierIdentityV1{executable,closure,buildPolicy}`；payload必须分别重算ref，禁止只验plain SHA或借用
host/private-scan/legacy descriptor schema。本owner修订不改变SPEC-TASKQUAL-001既有alias规则；D0 approval
`protectedConsumer == handoff.adapter`所要求的`protected-consumer-*`↔对应`adapter-*`三对跨carrier
ref/bytes exact equality继续合法且必须验证。production任一
`proof-forge.task-qualification-fixture-resolved-blob.v1`、unknown schema、known schema用在错误role、owner parser
拒绝、id/version/digest漂移均在pure verifier/terminal request前拒绝。

trusted-clock三件套因此作为v2 protected provenance exact roles加入，但不是profile artifacts或pure bundle
members。它们只证明handoff/lookup/clock observation共同pin住的clock service identity payload；
`trustedClockFd`中的signed observation、trusted instant equality及A+Q+S签名规则不变。此次修订发生在首个
production profile/pin/service/isolation/acceptance之前，不改变既有schema bytes；任何按未定义owner构造的
草稿profile/pin必须删除，关联nonce永久spent，不存在implicit migration、fallback或same-ref alias。

## 3. framing、公共标量与签名

每个`SOCK_SEQPACKET` packet固定承载恰一个`u32be(payloadLength) || canonical PF-JCS payload`；payload
length `1..4194304`，packet size必须exact为`4+payloadLength`。supervisor在任何packet前把两端
`SO_SNDBUF/SO_RCVBUF` request均设为4194304并要求Linux returned effective values均至少8388608；不足即
拒绝。sender只能用一次`send(..., MSG_NOSIGNAL)`发送完整packet，禁止`sendmsg/sendmmsg`及任何ancillary
data；receiver只能用一次`recvmsg`及4194308-byte data buffer与exact ancillary buffer取得完整packet，拒绝
`MSG_TRUNC|MSG_CTRUNC`、split frame、一个packet内两个frame及packet/u32 length mismatch。只允许本ADR的六种frame schema：client只发送client hello、
lookup request与terminal request；server只发送server hello、lookup response与terminal response。EOF、
trailing packet、unknown/duplicate/missing field、
non-canonical PF-JCS、invalid UTF-8、oversize均拒绝并spend nonce。每个server response必须紧跟其对应client
request，期间不得插入任何其他packet。

`requestId`与`headSequence`为PF-JCS safe integer `0..2^53-1`。第一个 lookup requestId固定0，之后每个
request（包括terminal request）exact加1。`taskId/operation/runId/nonce/service/headSequence/headDigest`
在全部 frame中逐字段echo signed handoff/client hello；任何漂移拒绝。operation仍只允许四个
`SPEC-TASKQUAL-001` operation。

server frame的`signature`是128 lowercase hex，不是`ApprovalSignatureV1`。对移除`signature`后的closed
object，service signature message固定为：

```text
ASCII(<frame-signature-domain>) || NUL || PF-JCS(unsignedFrame)
```

frame的full digest固定为：

```text
SHA-256(ASCII(<frame-full-domain>) || NUL || PF-JCS(fullFrame))
```

## 4. exact v2 frames

### 4.1 Client/server hello

```text
TaskQualificationStoreClientHelloV2 {
  schema: "proof-forge.task-qualification-store-client-hello.v2",
  version: "2.0.0", taskId, operation, runId, nonce,
  service: ContentRefV1, handoffDigest: Digest,
  headSequence, headDigest: Digest
}
TaskQualificationStoreServerHelloV2 {
  schema: "proof-forge.task-qualification-store-server-hello.v2",
  version: "2.0.0", taskId, operation, runId, nonce,
  service: ContentRefV1, handoffDigest: Digest,
  headSequence, headDigest: Digest,
  status: "ready", signature
}
```

`handoffDigest`是exact canonical signed `TaskQualificationProtectedHandoffV1` bytes以
`pf.taskqual.protected-handoff.v1`重算的full digest。server由ceremony在启动前取得并验证同一handoff。
本v2 exception profile只支持由supervisor一次创建的Linux
`socketpair(AF_UNIX,SOCK_SEQPACKET|SOCK_CLOEXEC,0)`；禁止bind/connect/accept取得的endpoint、第二个socketpair
或替换endpoint。namespace拓扑固定如下。descriptor钉住的privileged custody supervisor在host namespace中
创建恰一个共同ceremony user namespace U；descriptor.
userNamespace的dev/ino必须exact等于U的`/proc/self/ns/user`，U的uid_map/gid_map必须把descriptor四个UID/GID
全部映射到四个distinct host subordinate IDs，禁止sibling user namespace、unmapped与overflow ID。service和
adapter均属于同一U；descriptor中的UID/GID明确就是U内service receiver对`SCM_CREDENTIALS`看到的值。

supervisor/service位于U内parent PID namespace P；adapter child进入P的唯一child PID namespace A。因此
service可见并检查adapter，adapter的own proc只见A且看不到service/supervisor。两者使用独立mount namespace；
adapter mount不含seed/durable-state root或host proc，只含A的own proc与七参数所需readonly inputs。两者
supplementary groups均清空。adapter以descriptor.adapterUid/adapterGid、零capability、`no_new_privs`与
deny-default seccomp运行；supervisor最终以descriptor.serviceUid/serviceGid exec service。禁止依赖Yama、
hidepid或same-UID dumpable策略作为custody authority。

supervisor是正式role-key custody TCB，不是普通launcher；其identity和全部setup顺序由descriptor.supervisor/
isolationPolicy及protected provenance四role绑定。固定启动顺序为：(1)在未打开任何seed文件时建立U/P/A、
mounts、唯一seqpacket socketpair、同步pipe和§7 exact non-secret FDs；对两个endpoint stable-fstat并记录各自
fixed FD number与`(dev,ino,mode)`，禁止任何duplicate；预先safe-open descriptor.verifier executable为fixed
serviceExecutableFd，验证accepted ref/plain hash、regular single-link executable、无setuid/setgid mode bit、
`fgetxattr("security.capability")` exact为`ENODATA`、static ELF（无`PT_INTERP`且无`DT_NEEDED`）与closure/build
policy；无法证明普通non-privileged exec语义即拒绝。(2)fork adapter child，child在setup期间只临时保留adapter endpoint、同步pipe write-end与七参数其余
FD，关闭service endpoint及全部其他FD，进入A与readonly mount；在U内setup `CAP_SETPCAP`仍effective时
先以`PR_CAPBSET_DROP`删除全部bounding bits（该动作不删除当前P/E setup caps）并重验CapBnd为空；随后在
`CAP_SETGID`仍effective且`/proc/self/setgroups`允许时执行`setgroups(0,NULL)`并重验zero supplementary group，
再依次执行`setresgid(adapterGid,adapterGid,adapterGid)`与
`setresuid(adapterUid,adapterUid,adapterUid)`，要求
`getresuid/getresgid`及`/proc/self/status`的real/effective/saved/fs UID/GID全都exact为descriptor值，最后
清空五组capability、设置并验证`no_new_privs=1`；任一步失败不得写ready。child写入fixed one-byte ready、
关闭pipe，紧邻安装adapter seccomp和exec exact adapter之前只对retained adapter
endpoint执行一次`fcntl(F_SETFD,0)`并以`F_GETFD`确认`FD_CLOEXEC`已清除，禁止清除其他FD或使用
`F_DUPFD*`；(3)parent只保留service endpoint，从同步pipe取得ready后等待pidfd/proc证明child已exec为exact
adapter，再直接用kernel namespace/credential/FD facts重验
child已完成前述隔离并且其authorityStoreFd identity等于记录的adapter endpoint，关闭同步pipe；该ready只控制
时序，不替代service后续direct peer inspection；(4)parent仍持有pre-seed capability时先把bounding set除
`[8,19]`外全部永久删除，设置`PR_SET_KEEPCAPS`，在U的gid map已安装且`CAP_SETGID`仍effective且
`/proc/self/setgroups`允许时执行`setgroups(0,NULL)`并重验zero supplementary group，再依次执行
`setresgid(serviceGid,serviceGid,serviceGid)`与
`setresuid(serviceUid,serviceUid,serviceUid)`；要求`getresuid/getresgid`及`/proc/self/status`的
real/effective/saved/fs UID/GID全都exact为descriptor值，随后以`capset`把CapPrm/CapEff/CapInh exact设为
`[8,19]`，按8后19的固定顺序各执行一次`PR_CAP_AMBIENT_RAISE`，验证
CapBnd/CapPrm/CapEff/CapInh/CapAmb均exact为`[8,19]`。任何ambient raise失败、setgroups已被提前永久deny
而无法证明零group、saved/fs identity漂移、extra/missing bit或不同顺序均在seed open前拒绝；
(5)在打开任何seed文件
之前，supervisor按§6用durableStateRootFd对signed handoff tuple执行唯一`absent -> active` fsync transaction；
existing/stale state一律按§6处理并停止，reservation未commit不得继续；(6)严格按§7从与descriptor.seedRoot
匹配的唯一pre-opened seedRootFd打开四个seed并完成权限、公钥、FD唯一性检查；(7)关闭seedRootFd、同步/setup
FD和所有非exact pre-exec service-role FD；只对retained service endpoint执行一次`fcntl(F_SETFD,0)`并以
`F_GETFD`确认`FD_CLOEXEC`已清除，serviceExecutableFd必须仍设置该flag；建立含两端endpoint lineage及
serviceExecutableFd identity的sealed transition record，枚举确认U/P内除当前supervisor与既有adapter child外
不存在其他ceremony process；(8)再次验证五组capability均exact为`[8,19]`后设置
`PR_SET_NO_NEW_PRIVS=1`，再安装custody seccomp：永久禁止`fork/vfork/clone/clone3`、
`dup/dup2/dup3`、`fcntl(F_DUPFD*)`、`pidfd_getfd`、`sendmsg/sendmmsg`和任意FD transfer；pathname open只允许
对fixed procRootFd做readonly peer/self inspection，或对fixed durableStateRootFd做§6 exact transaction flags，
其他`open/openat/openat2/creat`一律拒绝；`execve`永久拒绝，seccomp只按可观察scalar参数允许
`execveat`的dirfd exact等于serviceExecutableFd且flags exact等于`AT_EMPTY_PATH`，不声称filter可解引用pathname/
argv/envp pointer；该FD必须设置`FD_CLOEXEC`；(9)不再fork，由supervisor传入policy exact fixedArgv/emptyEnv并
执行`execveat(serviceExecutableFd,"",...,AT_EMPTY_PATH)`，由kernel在成功exec时关闭serviceExecutableFd，
同一PID从supervisor image过渡为static exact descriptor.verifier service。不存在与service并存的privileged
seed-holder；adapter在seed打开前已进入不含seed/durable root的mount、不同UID与child PID namespace，且两侧
seccomp禁止事后传FD。service第一条用户逻辑在继承的custody filter下先验证`no_new_privs=1`且五组
capability均exact为`[8,19]`，再固定执行
`PR_CAPBSET_DROP(CAP_SYS_PTRACE)`、`PR_CAPBSET_DROP(CAP_SETPCAP)`、
`PR_CAP_AMBIENT_CLEAR_ALL`与一次`capset`，把状态不可逆收敛为
`CapBnd/CapInh/CapAmb=[]`、`CapPrm/CapEff=[19]`；只有exact recheck成功后才叠加拒绝全部exec的
`service-final` filter。随后从pinned procRootFd读取`self/cmdline`与`self/environ`，要求bytes分别exact为
`proof-forge-taskqualification-store-v2\0`与empty，再要求自身PPid/namespace/UID/GID/零supplementary group/
FD set、sealed transition record与policy exact，重验record中的supervisor PID和`/proc/self/stat`start-time
仍等于当前值、serviceExecutableFd已关闭且`/proc/self/exe` exact为record/descriptor identity，再关闭
transition FD；capability transition及这些检查全部先于post-exec seed FD读取、任何client packet、peer
inspection及任何role signing。任一步失败都不得加载较宽filter、执行post-exec service seed-FD读取或返回frame。
该record仅证明同一trusted
supervisor process未在seed打开后fork，不是candidate launch receipt或新的授权对象。步骤(5) active commit
之后任一root/seed/FD/public-key/transition/seccomp/exec/self-check失败，supervisor或service必须在退出前把同一
nonce原子写`rejected`；若process在写前崩溃，下一次supervisor recovery必须先把遗留`active|signing`写
`rejected`并拒绝复用，绝不重新转active。

service在读取任何client packet前设置`SO_PASSCRED=1`；每个client packet的`recvmsg`必须取得恰一个kernel
`SCM_CREDENTIALS(pid,uid,gid)`，拒绝missing/extra ancillary及packet间pid/uid/gid变化。首packet pid必须
不同于service PID，uid/gid必须exact等于descriptor.adapterUid/adapterGid，而service进程自身credentials
必须exact等于descriptor.serviceUid/serviceGid。

service的`CAP_SYS_PTRACE`位于与adapter相同且支配其credentials的U，不是sibling/child user namespace。
UID/GID mappings、namespace IDs、exact FD roles、socket buffers、capability set/drop point与两侧seccomp policy
均来自descriptor.isolationPolicy exact bytes；任何extra capability、不同policy bytes或supervisor identity
拒绝。service立即`pidfd_open(pid,0)`并在hello、每个lookup、terminal preflight和final transaction前后要求
pidfd仍指向同一alive process，禁止只比较可复用数字pid。所有proc读取只允许相对pinned procRootFd的一次
`openat/fstatat/readlinkat`；pid component由SCM pid机械生成、只含无前导零的canonical ASCII decimal。service
代码在每次syscall前只构造并exact匹配closed path grammar
`<pid>/fd`、`<pid>/fd/<handoff-fd>`、`<pid>/fdinfo/<handoff-fd>`、`<pid>/exe`、`<pid>/stat`或
`self/{cmdline,environ,exe,stat,status}`；禁止caller path、`.`、`..`、额外slash或其他proc entry。seccomp只能
强制procRootFd与scalar flags，path grammar由pinned static service在调用前强制；不声称BPF解引用path pointer。
它以`openat(procRootFd,"<pid>/fd",O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)`列举peer FD，要求恰为
`0,1,2`加handoff五个channel FD；以`fstatat`/exact `fdinfo`读取而不通过`SCM_RIGHTS`或`pidfd_getfd`复制peer
FD，并要求handoff.authorityStoreFd的FD number与`(dev,ino,mode,fdFlags=0)` exact等于sealed transition中
supervisor创建后并在child exec后复核的adapter endpoint。同时service自己的store FD identity必须exact等于
record中的另一个`fdFlags=0` endpoint。两端必须不同、共同来自record中唯一socketpair且adapter seccomp/FD
enumeration证明fork后未替换或duplicate；这里不从两个socket inode反推kernel peer关系。它只以
`openat(procRootFd,"<pid>/exe",O_RDONLY|O_CLOEXEC)`跟随该exact kernel magic link取得executable identity，
不接受caller path；在pidfd alive期间从offset 0 stable-fstat读取并按handoff.adapter.executable的accepted schema/domain重算ContentRef
和plain payload hash。adapter closure/buildPolicy bytes由supervisor在seed前预先safe-open为service-only
readonly FDs；service同样stable-fstat读取、按各自schema/domain重算并要求exact等于handoff.adapter对应refs。
sourceDigest直接由signed handoff identity绑定，不从pathname推导。

terminal preflight完成最后一次peer FD/executable检查后，service在既有`no_new_privs=1`与
`service-final` deny-default filter下用唯一一次`capset`永久清空CapPrm/CapEff；此时CapBnd/CapInh/CapAmb
必须已从service启动transition起保持为空。service从`/proc/self/status`重验五组全部为零后才允许任何role
signing；final transaction只用已打开pidfd检查liveness，不再读peer`/proc`。无法证明capability所属U、
transition顺序、steady最小化或terminal all-zero即零签名拒绝。

service不消费candidate提供的launch receipt或self-reported peer hash；共同U的exact mapping、parent/child
PID topology、separate Unix principals/mounts、single-PID custody-supervisor→service exec、kernel packet
credentials/pidfd、exact adapter FD set、live executable与service-side closure/buildPolicy bytes共同构成
peer/custody authority。非Linux、无`SOCK_SEQPACKET/SO_PASSCRED/SCM_CREDENTIALS/pidfd_open`、namespace
拓扑或mapping不exact、UID/GID不分离、custody supervisor仍并存、capability/profile不exact、peer退出或
FD/bytes/ref任一不可证明时在hello前或当次packet拒绝；禁止same-uid、sibling user namespace、pathname、
unsigned receipt或“等价平台”fallback。

hello full domains依次为`pf.taskqual.store-client-hello.v2`、
`pf.taskqual.store-server-hello.v2`；server signature domain为
`pf.taskqual.store-server-hello-signature.v2`。

### 4.2 Lookup request/response

```text
TaskQualificationStoreLookupRequestV2 {
  schema: "proof-forge.task-qualification-store-lookup-request.v2",
  version: "2.0.0", requestId, taskId, operation, runId, nonce,
  service: ContentRefV1, headSequence, headDigest: Digest,
  key: TaskQualificationStoreLookupKeyV2
}
TaskQualificationStoreLookupResponseV2 {
  schema: "proof-forge.task-qualification-store-lookup-response.v2",
  version: "2.0.0", requestId, taskId, operation, runId, nonce,
  service: ContentRefV1, headSequence, headDigest: Digest,
  status: "found", key: TaskQualificationStoreLookupKeyV2,
  object: ContentRefV1, objectBytesHex, signature
}
```

lookup key是以下closed discriminated union，字段恰含且顺序如下：

```text
TaskQualificationStoreObjectLookupKeyV2 {
  kind: "object", namespace:"task-qualification-production-v1",
  taskId, operation, gateSetDigest, objectKind, objectId
}
TaskQualificationStoreRevocationHeadLookupKeyV2 {
  kind: "revocation-head", namespace:"task-qualification-production-v1",
  taskId, operation, gateSetDigest,
  objectKind:"revocation-snapshot", headSequence, headDigest:Digest
}
TaskQualificationStoreLookupKeyV2 =
  TaskQualificationStoreObjectLookupKeyV2 |
  TaskQualificationStoreRevocationHeadLookupKeyV2
}
```

object key的objectKind/schema只允许：`authority-policy`/`BootstrapAuthorityPolicyV1`、
`production-profile-pin`/`ProductionVerificationProfilePinV1`、
`production-profile`/`ProductionVerificationProfileV1`、`adapter`/`VerifierIdentityV1`、
`snapshot-parser`/`VerifierIdentityV1`、`authority-store-service`/v2 descriptor、
`trusted-clock-service`/`VerifierIdentityV1`、`revocation-record`/既有record。
`revocation-snapshot`只允许head key，禁止object key；其response object bytes/ref必须解析为既有closed
snapshot，并要求snapshot headSequence/headDigest与key、handoff.revocationHead及server current head逐字段
exact，snapshot ContentRef从response bytes重算。相同head不同snapshot ID/ref/bytes、相同ID不同bytes/ref或
head digest不重算均拒绝。只允许found exactly one；zero/revoked/multiple拒绝。

lookup request的全序固定为：(0) authority-policy；(1) production-profile-pin；
(2) production-profile；(3) adapter；(4) snapshot-parser；(5) authority-store-service；
(6) trusted-clock-service；(7) revocation-snapshot；随后(8...)为snapshot声明的每个revocation-record，按
record id ASCII严格升序。每个request后必须立即收到同requestId/key的唯一response，才可发送下一个；
不得duplicate、extra、省略或重排。terminal requestId必须exact等于lookup request总数，即
`8 + revocationRecordCount`。objectId只能来自signed handoff、verified pin/profile/snapshot；candidate、
subject或CLI不能选择。

lookup request/response full domains为`pf.taskqual.store-lookup-request.v2`、
`pf.taskqual.store-lookup-response.v2`；response signature domain为
`pf.taskqual.store-lookup-response-signature.v2`。

### 4.3 Terminal request

```text
TaskQualificationStoreAcceptanceSignRequestV2 {
  schema: "proof-forge.task-qualification-store-acceptance-sign-request.v2",
  version: "2.0.0", requestId, taskId, operation, runId, nonce,
  service: ContentRefV1, handoffDigest: Digest,
  headSequence, headDigest: Digest,
  adapter: VerifierIdentityV1,
  productionProfilePin: ContentRefV1,
  snapshotParser: VerifierIdentityV1,
  acceptanceStatementDigest: Digest,
  unsignedAcceptanceBytesHex
}
```

另定义只用于该terminal request的closed `UnsignedProtectedTaskQualificationAcceptanceV1`：字段与accepted
`ProtectedTaskQualificationAcceptanceV1`从`schema`到`provenanceRoles`逐字段、逐顺序相同，但**不含**
`signatures`字段；它不是可发布的acceptance。`unsignedAcceptanceBytesHex` decoded size `1..2000000`，
lowercase even hex，且bytes必须是该unsigned type的canonical bytes。携带`signatures:[]`、非空signatures或
任何其他字段一律拒绝。`provenanceRoles`每项最多512 UTF-8 bytes并机械匹配§8.4 exact role grammar；该
兼容收紧使完整unsigned acceptance落入上述2,000,000-byte bound。statement digest唯一为：

```text
SHA-256("pf.taskqual.protected-acceptance-statement.v1" || NUL ||
  PF-JCS(UnsignedProtectedTaskQualificationAcceptanceV1))
```

这与accepted对象的“移除`signatures`字段后签名”规则逐字一致；不得以空array替代字段移除。

request full domain为`pf.taskqual.store-acceptance-sign-request.v2`。

### 4.4 Terminal response

```text
TaskQualificationStoreAcceptanceSignResponseV2 {
  schema: "proof-forge.task-qualification-store-acceptance-sign-response.v2",
  version: "2.0.0", requestId, taskId, operation, runId, nonce,
  service: ContentRefV1, handoffDigest: Digest,
  headSequence, headDigest: Digest,
  status: "signed",
  acceptanceStatementDigest: Digest,
  acceptance: ContentRefV1,
  acceptanceBytesHex,
  signature
}
```

service在任何role signing前必须同时预编码三项最大合法signature wire并证明最终signed acceptance decoded
size仍为`1..2000000`且完整response小于4194304 bytes；超限时零签名拒绝。`acceptanceBytesHex`是从request
unsigned object逐字段复制后，在accepted schema的最后固定位置新增`signatures`字段并填入三项sorted
`ApprovalSignatureV1`所得的exact canonical
signed bytes；除新增该字段外所有值逐字段不变。每项role signature message为：

```text
ASCII("pf.taskqual.protected-acceptance-signature.v1") || NUL ||
  raw32(acceptanceStatementDigest)
```

`acceptance`必须以`pf.taskqual.protected-acceptance.v1` full domain从exact signed bytes重算。
response full domain为`pf.taskqual.store-acceptance-sign-response.v2`；service signature domain为
`pf.taskqual.store-acceptance-sign-response-signature.v2`。

adapter exact-decode response，重验service signature、三项role signatures、fixed quorum、unsigned/signed
byte equality、ContentRef、echo tuple和terminal state；只返回response内exact signed acceptance bytes，
不得自行替换signature、重排字段或接受partial result。

## 5. authenticated adapter completion assertion

terminal request不是独立可转发的authorization object。其真实性来自以下不可拆分的protected session：

1. A+Q+S signed handoff预授权exact task/operation/run/nonce/head/profile pin/adapter/parser/service/clock；
2. ceremony把同一signed handoff、current policy及service-side adapter closure/buildPolicy payload FDs提供给
   v2 service；
3. service按§4.1对每个client frame重验kernel credentials、pidfd lifecycle、exact inherited FD set、live
   executable及service-side closure/buildPolicy refs；
4. adapter在同一不可替换authorityStoreFd上完成exact lookup transcript；
5. terminal request由该已认证alive process在同一session发送并绑定handoff digest。

service信任policy-pinned adapter已经重算pure bundle和provenance bytes；service不声称再次读取adapter的
archive/provenance/clock FDs。它必须独立重验unsigned acceptance的closed shape、task/operation/id、
authority class、candidate key、trusted instant、adapter/parser/profile pin、nullable D0 receipt fields及
全部可由handoff/lookup transcript推导的值。kernel/process/payload任一证明缺失时，request即使拥有合法
handoff bytes也必须拒绝。由此signer是one-shot live-pinned-adapter verdict signer，不是任意acceptance
oracle。

## 6. durable nonce 与 head 原子状态机

candidate-external durable store以`(taskId,operation,runId,nonce)`为key，唯一状态机为：

```text
absent -> active -> signing -> accepted
                    \-> rejected
          \------------> rejected
```

- supervisor在§4.1切换到service UID/GID后、**打开任何seed文件前**，先验证signed handoff/policy/service tuple，
  再以serializable fsync transaction执行`absent -> active`。reservation commit前不得读取seed、启动service或
  发送hello；任何existing state都是replay，禁止把`rejected|accepted|active|signing`重新转active。
- `active` commit后至durable `accepted` commit前，任一setup/root/seed/FD/public-key/transition/seccomp/exec/
  self-check失败，或malformed frame、wrong peer、lookup failure、timeout、EOF、extra frame、disconnect、
  send-preparation failure、protocol mismatch，均由当前supervisor/service原子写`rejected`，wire上零role signature。
- service startup只验证state exact为`active`，不得再次reserve；terminal request通过preflight后CAS
  `active -> signing`，并发同nonce最多一个成功。
- supervisor/process restart在接收新session或打开seed前，必须先把所有遗留`active|signing`原子转
  `rejected`并fsync；若遗留key正是请求tuple，本次直接拒绝，不创建第二个active。
- service读取并暂存exact head H0，生成三项role signatures和完整response于service-private memory；在任何
  signature bytes发送前进入serializable final transaction：重新读取current policy/head，要求H1==H0、
  signingKeyIds仍映射同一三个current principals，并CAS `signing -> accepted`，同时持久记录signed
  acceptance digest、response full digest和terminal timestamp。
- head/policy漂移、partial role signing、HSM/seed failure、service-signature failure或final commit failure均
  丢弃全部signature buffers并原子写`rejected`；wire上返回零role signatures。
- 只有accepted transaction fsync/commit成功后才发送完整response。commit后的send/connection failure保持
  durable `accepted`，不回退、不重发，并在内部audit标记`accepted-response-undelivered`（该标记不是新
  protocol state）；caller必须取得新signed handoff和nonce。
- terminal response后拒绝任何frame并关闭session。`maximumTerminalAcceptances=1`也要求service process退出。

head在accepted transaction之后发生的合法revocation由后续consumer currentness检查处理；本协议只声称
terminal commit instant的exact head。nonce state mutation与audit record属于protocol session state，不发布、
替换或修改authority object namespace。

## 7. private-key custody

v2只允许descriptor固定的`one-time-seed-fd-v1`。ceremony只向pinned supervisor提供一个pre-opened
`seedRootFd`，从不向adapter提供root、seed、private scalar或可导出handle，也不直接向尚未隔离adapter的
process提供任何已打开seed文件。`seedRootFd`必须以`O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC`打开；
supervisor在adapter完成§4.1隔离后、切换到service UID/GID后，立即对root执行前后stable
`fstat(dev,ino,mode,uid,gid)`，要求device/inode exact等于descriptor.seedRoot、owner exact为service euid/gid、
mode exact `0700`，且root不是mount point、bind mount或magic link。该目录只允许四个literal basename：
`service.seed`、`role-0.seed`、`role-1.seed`、`role-2.seed`；`role-i`按descriptor.signingKeyIds ASCII升序映射，
存在其他directory entry、hard link、subdirectory或不可证明empty-after-four即拒绝。

supervisor按上述固定顺序用`openat(seedRootFd, basename,
O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC)`各打开恰一次；四次open必须直接返回isolation policy保留的四个
exact FD number，禁止以dup移动。每个seed FD读取前后stable `fstat(dev,ino,mode,uid,gid,nlink,size)`，要求
regular、四个`(dev,ino)`两两不同、owner exact为service euid/gid、`nlink=1`、mode exact `0400`；内容恰为32
raw bytes或64 lowercase hex加可选单个LF。读完后只允许以`fcntl(F_SETFD)`清除这四个FD的`FD_CLOEXEC`；
禁止`F_DUPFD*`。supervisor从seed派生public key并要求：

- service seed exact匹配descriptor.servicePublicKey且不同于全部role keys；
- 三个role seed按descriptor.signingKeyIds exact匹配current policy public keys；
- 三个key映射distinct principal并覆盖Architecture+Quality+Security；
- fixture RFC8032 keys与production policy静态不相交。

四个seed验证完成后，supervisor必须先关闭`seedRootFd`，创建并seal下述transition record，再枚举
`/proc/self/fd`和每个FD identity。pre-exec exact role set恰为：stdio、service socket endpoint、procRootFd、
durableStateRootFd、policy/handoff/isolation-policy readonly FD、adapter closure/buildPolicy readonly payload FD、
serviceExecutableFd、sealed transition FD及四个seed FD；不得有setup FD、adapter endpoint、pathname root、
同一seed inode的第二FD或任何未定义FD。每个非stdio FD编号/role由candidate-external isolation policy固定且
两两不同；procRootFd只指向U/P的pinned readonly proc mount，durableStateRootFd只指向candidate-external state
directory。closure/buildPolicy及其他readonly payload沿用non-seed regular-file stable-fstat/single-link/
no-symlink规则。durable state root必须owner service euid/gid、mode exact`0700`、稳定dev/ino；事务只可在该fixed
dirfd下使用no-clobber temp、`fsync`、atomic no-replace rename与directory fsync。successful exec后post-exec
exact role set只比pre-exec set少已由`FD_CLOEXEC`关闭的serviceExecutableFd；service验证并关闭transition FD后，
steady-state set再只少transition FD。

sealed transition record由supervisor在seed验证后、安装seccomp前以
`memfd_create("pf-tq-custody-transition",MFD_ALLOW_SEALING)`（明确不设`MFD_CLOEXEC`）创建，必须直接取得policy
fixed transition FD number，写入canonical closed record；exact wire与field order为：

```text
LinuxFdIdentityV2 { fd, device, inode, mode, fdFlags }
TaskQualificationCustodySeedFdV2 { slot, keyId, fd, device, inode }
TaskQualificationCustodyTransitionV2 {
  schema: "proof-forge.task-qualification-custody-transition.v2",
  version: "2.0.0", supervisorPid, startTimeTicks,
  userNamespace: LinuxNamespaceIdentityV2,
  pidNamespace: LinuxNamespaceIdentityV2,
  adapterPid,
  adapterEndpoint: LinuxFdIdentityV2,
  serviceEndpoint: LinuxFdIdentityV2,
  serviceExecutableFd,
  serviceExecutable: ContentRefV1,
  serviceExecutablePayloadSha256: Digest,
  seeds: [TaskQualificationCustodySeedFdV2]
}
```

所有整数为PF-JCS safe integer；`fdFlags`只允许`0|FD_CLOEXEC`，`startTimeTicks`来自同一pinned procRoot的
`/proc/self/stat` field 22。`seeds`按slot exact为`service,role-0,role-1,role-2`，role项keyId按descriptor顺序，service项keyId固定
`service`；四项不得增减。socket identities与§4.1 fork前记录逐字段exact，executable ref/hash与descriptor.
verifier exact。写后必须加`F_SEAL_WRITE|F_SEAL_GROW|F_SEAL_SHRINK|F_SEAL_SEAL`；service exact-decode、
重算并比较全部kernel facts后立即关闭该FD。
从第一项seed成功open直到service退出，当前PID不得fork/clone、不得dup seed、不得打开第二root、不得通过
`SCM_RIGHTS`或`pidfd_getfd`传出/取得FD；同一U/P中除adapter child与该同PID supervisor→service process外
不得有ceremony process。service启动时必须证明PID/start-time、四个seed FD number/identity和exact FD role
set与transition/policy一致，并证明`seedRootFd`已关闭；任一不一致在role curve work前拒绝。service不接受
candidate生成、未sealed或不同PID生成的transition record，且该record不替代per-packet peer检查。

candidate、subject、environment、argv、日志、transition record与durable state均不得携带seed bytes、private
scalar或可导出handle；protected provenance只携带public supervisor/isolation payload。seed读取失败、公钥不符、
权限/目录/FD set不符时在hello前零输出并按§6把已reserved nonce持久化为`rejected`。terminal结束后立即关闭四个seed FD和所有
nonstdio FD并退出整个service process；进程销毁是secret lifetime边界，不把Python不可证明的内存清零写成
authority。未来non-exportable HSM backend必须使用新protocol major/ADR，不得在v2增加alternate custody enum。

## 8. authorization 语义

signed handoff就是本次terminal signing的A+Q+S事前授权：它委托exact pinned adapter在exact candidate/
operation/session/current head上，只有全部protected checks成功时请求一次final role signatures。v2 service
不得仅凭socket/seed启动自行选择task或statement；全部选择来自signed handoff及current lookup。

final三项role signatures证明该one-shot delegation下的机器签发，不证明三位不同人或post-result人工批准。
`GOV-MAINTAINERS-001`要求的独立只读实现/安全复审继续单独满足，reviewer不得由signing principal身份替代。

## 9. docs-check 与 authority 边界

- pure verifier仍只返回`production-content-verified`或`fixture-non-authoritative`。
- 只有完整v2 protected path可返回`production-candidate-bound`。
- root `docs_check`永远structural-only，不调用v2、不读取candidate-external completion，也不把optional P
  mirror当authority。
- D0-10 C→approval→D→external receipt/acceptance→optional P无环状态机不变。
- `BootstrapAuthorityPolicyV1` six-item activation、taskRules、RequiredTestSet和release aggregate不变。

## 10. C3 migration / compatibility

| Input/consumer | v1 | v2 |
|---|---|---|
| historical lookup-only verification | 保留，行为字节不变 | 不替代历史证据 |
| new taskqualification protected handoff | 拒绝：不能签acceptance | 唯一允许 |
| profile/pin/service descriptor | v1 ref不得升级或alias | 必须exact pin v2 descriptor/ref |
| frame decoder | 只读v1 schema | 只读v2 schema；拒绝v1 |
| fallback/negotiation/dual reader | 禁止 | 禁止 |
| old candidate `1e0214f9` | 不可closeout | 必须建立新candidate |

本变更不修改v1 bytes/domain。v2 schema仍为major `2.0.0`，domain仍以`.v2`结尾；capability R2纠错发生在首个
production profile/service/isolation-policy pin及首个v2 acceptance签发之前，closed wire字段集合、service
protocol与custody enum均未增加，只把不可达的`custodyCapabilities=[19]`及其checkpoint修正为上述唯一
`[8,19]` ambient transition。后续raw artifact owner R2同样发生在首个production profile/pin/acceptance前：
profile/frame既有字段不变，只注册新的`proof-forge.task-qualification-artifact-payload.v1` schema并把既有
logical/protected roles映射到exact owner。任何按旧checkpoint或未定义owner构造的未发布policy/profile bytes
必须删除并cross-reject，关联handoff nonce永久spent；不得把同ID/ref、plain SHA或“语义等价”alias迁移为新
identity。配套接受单元必须更新`docs/governance/version-compatibility.md`和实现日志作为release note；仓库没有
已发布v2对象需要data migration。

rollback：首次production acceptance前可撤销v2 pin并保持TASK-D0-10 blocked；一旦v2签发，发现缺陷时立即
撤销v2 profile/service pin及所有未消费handoff nonce，拒绝新acceptance；禁止回退v1或caller-seed adapter，
后续修复走新protocol major。

## 11. Freeze Exception `FX-2026-07-23-D0-10` 提案

首轮独立复审确认v2 service、custody和durable nonce是原冻结包未列出的production capability。因此不再把
它描述为R2 implementation-only repair；为避免新增D0 task破坏已封顶milestone并保持D1依赖无环，选择
`GOV-TASK-FREEZE-001` §8的正式Exception路径：

| Field | Proposed value |
|---|---|
| taskId | `TASK-D0-10` |
| originalFreezeCommit | `60568e6ec6532547347530376c6da7ce241af26b` |
| blockedProposalBaseline | `70c55daa3d89af4e572cab9f8bb47a567c286313`（只证明triage/block，不是新freeze点） |
| newFreezeCommit | 由后续activation commit内replacement package写成exact 40-hex，且必须等于该activation commit的direct parent（即accepted metadata-only commit）；本proposed body不得预填未来hash |
| reason | accepted七参数/lookup-only/最终会签形成不可实现闭环；实现完整protected consumer必须增加candidate-external v2 terminal signer |
| user/security impact | adapter仍无private key；新增三角色key使用面、durable nonce/head事务和service process TCB，必须独立安全复审 |
| old output | `task-scoped formal qualification verifier + protected docs consumer + one-time completion bridge` |
| new output | `task-scoped formal qualification verifier + protected docs consumer + taskqualification authority-store v2 terminal signer + one-time completion bridge` |
| dependencies | 保持`TASK-D0-07` |
| prerequisites | 保持`ADR-0020@accepted, GOV-TASKQUAL-BOOTSTRAP-001@accepted, SPEC-TASKQUAL-001@accepted`；ADR-0021 acceptance作为exception本身的生效条件，不回填任务列 |
| tests | 保持唯一`TST-DOC-001`；只扩同一`task-qualification-v1` subprofile cases，不新增TST ID |
| added inScope | 本ADR exact v2 client/server、one-shot seed-FD custody、durable nonce/head transaction及其negative matrix |
| removed scope | 无 |
| time limit | 固定到`2026-07-25T06:00:00Z`；若Exception批准时已到或超过该instant则不得激活，逾期强制重新blocked |
| rollback | 删除未签发v2 pin/objects，spend全部handoff nonce，任务回blocked；不得以v1/caller seeds降级关闭 |
| approval record | ADR转accepted时的`approvers,approvedAt,reviewCommit,reviewLink,openFindings`同时是本Exception批准记录；approvers必须覆盖Architecture+Quality+Security，openFindings必须为none，另需独立只读安全复审P0/P1=0 |

本表在ADR未恢复`accepted`（包括`proposed|in_review`）时不授权修改task row/freeze package或恢复实现。
proposed-body阶段必须把
SPEC-TASKQUAL-001与PHASE-5显式置为`in_review`并移除旧accepted approval fields；旧批准只保留于Git历史，
因此未经批准的v2正文不会伪装成现行accepted authority。`docs/document-status.md`同步镜像PHASE-5
`in_review`。ADR-0021、SPEC-TASKQUAL-001与PHASE-5后续accepted amendment frontmatter的`reviewCommit`必须
共同指向包含本exact normative body、配套SPEC/test/trace/version migration/release-note log且经独立
P0/P1=0复审的immutable **proposed-body commit**；其后只允许一个把三个文档frontmatter与index状态写成
accepted并加入approval metadata的metadata-only commit，禁止改变normative body。`reviewLink`必须指向该
proposed-body commit及其review的HTTPS记录；accepted metadata commit不把自己的hash写入自身。

metadata-only commit只批准Exception，状态为`approved-pending-activation`，不恢复task。取得其actual 40-hex后，
唯一后续activation commit才可同时：(a)把task row改为新output/`in_progress`；(b)替换freeze package；(c)在
package写入exact `exceptionId:"FX-2026-07-23-D0-10"`、
`exceptionExpiresAt:"2026-07-25T06:00:00Z"`、`freezeCommit:<metadata-only-parent-40hex>`及表中new
output/inScope。该literal hash必须exact等于activation commit的direct parent，且parent必须是上述accepted
metadata commit；package连同accepted ADR approval metadata才构成§8完整Exception record。任何更早commit、
proposal baseline、activation commit自身或非direct parent均拒绝。只有该activation commit在expiry前完成后
TASK-D0-10才恢复`in_progress`；完成面重置后不得再次扩大。

### 11.1 activation 后 capability R2 纠错

首次activation后的Linux probe证明原checkpoint不可达，因此task按`GOV-TASK-FREEZE-001` R2重新
`blocked`。本节修正仍交付同一v2 terminal signer、同一seven-argument API、同一custody backend、同一
TST-DOC-001 subprofile及同一doneWhen，不改Output/Tests/Dependencies/Prerequisites/inScope/outOfScope，
不是第二次Exception或完成面扩张。纠错必须形成新的immutable proposed-body commit，并由独立
Architecture+Quality+Security复审至P0/P1=0；随后只允许metadata-only commit把ADR-0021、
SPEC-TASKQUAL-001与PHASE-5共同恢复`accepted`且三者reviewCommit exact指向该proposed body。

若metadata acceptance仍早于`2026-07-25T06:00:00Z`，其唯一direct-child reactivation只可把task
`blocked→in_progress`，并把existing package的`freezeCommit`重锚到该metadata commit；`exceptionId`、
`exceptionExpiresAt`及除`freezeCommit`外所有package field必须逐字不变。无论届时是否已reactivation，若
`2026-07-25T06:00:00Z`尚未`done`，必须把任何`in_progress`原子转回`blocked`（或经批准Split），旧Exception
不再授权继续实现、再次reactivation或延长时限；后续须按`GOV-TASK-FREEZE-001`重新取得书面Exception。
旧`c22ed76e`只证明原accepted black-box RED；纠错accepted后必须先补提交同一TST subprofile的
capability-transition RED，才可恢复production runtime GREEN；该RED已由
`e574aaf11d4c829eea28e3dd993f85c6e3e28bf1`完成。

### 11.2 corrected RED 后 raw artifact owner R2 纠错

GREEN审计确认§2.1所述owner缺口后，task再次按R2转`blocked`。该修正仍交付同一profile mapping、protected
adapter、v2 signer、seven-argument API、custody backend、TST-DOC-001 subprofile及doneWhen；没有增加profile/
frame字段、TST ID、Dependency、Prerequisite、inScope或output，因而不是第二次Exception或完成面扩张。
纠错必须形成新的immutable proposed-body commit；默认由实现会话以外的Architecture+Quality+Security复审至
P0/P1=0。仓库由唯一维护者独立开发时，唯一维护者可用明确owner directive替代该流程复审，但必须在实现日志中
逐字记录`single-maintainer-owner-waiver`、不得声称independent review，并继续满足全部closed wire、RED→GREEN、
真实kernel/production acceptance、A+Q+S distinct-principal签名、C→D与完整gate。waiver只替换人员/agent流程，
不替换任何可执行或密码学验收。随后只允许metadata-only commit把ADR-0021、SPEC-TASKQUAL-001与PHASE-5共同
恢复`accepted`；sole-maintainer路径的三份`approvers`只列唯一维护者，`reviewCommit` exact指向包含本条的
immutable body，normative body相对metadata commit零变化。

若该metadata acceptance与其direct-child reactivation都早于原
`2026-07-25T06:00:00Z`，该reactivation只可把task `blocked→in_progress`并把existing package的
`freezeCommit`再次重锚到metadata commit；`exceptionId`、`exceptionExpiresAt`及除`freezeCommit`外全部package
字段必须逐字不变。这是owner-R2唯一一次reanchor，不授权修改或延长Exception。owner纠错accepted后须先在
同一TST subprofile提交ref-digest/plain-digest独立性、role/schema confusion与unknown owner的focused RED，
才可恢复GREEN。若到expiry仍未done，§11.1的强制Block/Split规则原样生效。

## 12. 验证要求

既有`TST-DOC-001/task-qualification-v1`至少覆盖：

- protected API恰七个positional-only参数，无法注入seed/path/env/kwargs；
- v1/v2 descriptor、frame、schema、domain全部交叉拒绝；
- unknown/extra/missing field、noncanonical、frame/acceptance bound拒绝；worst-case encoder KAT证明最大合法
  terminal request/response均严格小于4194304 bytes，增加一个byte稳定拒绝；
- generic digest/message、错误acceptance domain、signature类型互换拒绝；
- §2.1 raw ref与plain payloadSha256分别重算：payload相同但id/version不同、ref digest仅等于plain SHA、
  payloadSha正确而artifact ref错误、artifact ref正确而payloadSha错误、known owner用于错误role、unknown/fixture
  schema、typed owner noncanonical/parse失败、identity三件套任一missing/extra/ref错配及trusted-clock三role缺失
  全部在terminal前拒绝；既有alias matrix不变，D0 `protected-consumer-*`↔`adapter-*`三对跨carrier exact
  equality为正例；每个accepted owner至少一个正例和逐byte payload mutation；
- wrong/missing `SCM_CREDENTIALS`、packet间credential漂移、PID reuse/process exit、pidfd mismatch、
  peer FD set/socket替换、adapterUid==serviceUid、shared supplementary group、adapter可traverse seed目录、
  U dev/ino或uid/gid map漂移、unmapped/overflow ID、sibling user namespace、service不在P或adapter不在唯一child A、
  supervisor/isolation-policy每个closed field错配、capability所属namespace错误/过宽/未drop、supervisor与service
  并存或seed-open后fork、socketpair endpoint lineage/FD/inode/`FD_CLOEXEC`任一替换、未清除或duplicate、dynamic
  ELF/PT_INTERP/DT_NEEDED、setuid/setgid mode bit、任意`security.capability` xattr、错误serviceExecutableFd/
  exec flags/argv/非空environment或execve/second-exec、
  executable相同但closure/buildPolicy bytes/ref不同及
  handoff/profile/parser/service/head任一漂移、proc path非canonical/非allowlisted/非procRootFd或flags错误均拒绝；
  unsigned launch receipt不能替代direct service observation；
- eligible Linux kernel-backed capability matrix必须逐checkpoint读取`/proc/self/status`并用`PR_CAPBSET_READ`
  交叉确认：旧`custodyCapabilities=[19]`、缺8或19、任一extra bit、ambient/inheritable/permitted不等、ambient raise
  失败、`no_new_privs`或exec顺序漂移、先清SETPCAP、19/8 bounding drop反序或遗漏、steady残留8/B/I/A、terminal
  非全零、sibling U及shared supplementary group全部零签名并durably reject；adapter/service还须覆盖
  adapter在credential drop前清空bounding set，以及两侧`setgroups→setresgid→setresuid`顺序、
  real/effective/saved/fs UID/GID exact与所有filtered credential mutation negatives。正例必须在ordinary
  static `execveat`后保持五组`[8,19]`，再达到`B/I/A=[] P/E=[19]`和terminal
  五组全零；
- signed seccomp matrix必须拒绝缺少/增加/放宽transition `prctl`、`capset`、final-filter overlay规则，拒绝filtered
  stage出现任何UID/GID/group mutation（含`setfsuid/setfsgid`）或第二exec；在两次bounding drop、ambient clear、steady capset任一处注入
  crash/kill都必须由recovery把nonce永久写`rejected`，不得把host不支持ambient当PASS或fallback；
- `SOCK_SEQPACKET` split frame、two-frames-one-packet、packet/u32 mismatch、socket buffer不足、`sendmsg/sendmmsg`
  或任意非kernel-injected ancillary data拒绝；六种frame的
  方向与domain exact；lookup missing/extra/duplicate/out-of-order、response插入及terminal
  requestId漂移拒绝；snapshot使用object key、unsigned head、same-head/different-ID/ref/bytes及
  headDigest不重算拒绝；
- concurrent same nonce最多一个terminal outcome；active/signing crash restart均永久rejected；
- unsigned acceptance无`signatures`字段；携带`signatures:[]`拒绝；移除signed object的signatures后所得
  statement digest与既有v1 verifier KAT逐字相同；
- signing前、三签期间、final transaction前head/policy漂移均零role signature输出；
- partial role sign、service sign、fsync/commit/send failure的spent/no-retry行为；accepted commit前disconnect
  命中rejected，commit后disconnect保持accepted并记录undelivered audit；
- seedRoot dev/ino/type/owner/mode、extra entry、root在adapter mount可达、adapter ready前seed open、seed basename/order、
  seed FD number/type/owner/mode/link/stability/content/public-key mismatch拒绝；reservation失败不得打开seed，
  active后任一root/seed/public-key/transition/seccomp/exec failure必须durably rejected且同handoff retry拒绝；
  `seedRootFd`存活过exec、duplicate inode/OFD、extra ambient FD、transition memfd未sealed/PID或start-time漂移、
  seed-open后fork/clone/dup/`F_DUPFD*`/`pidfd_getfd`/`SCM_RIGHTS`任一发生均拒绝；
- fixture key、revoked/changed key、角色复用、service/role/handoff signature互换拒绝；
- successful response exact signed acceptance bytes/ref/quorum和adapter re-verification；
- root docs-check保持D/P structural-only且不获得authority。

## 13. 替代方案

1. 新增独立task：会改变已封顶D0集合或形成D1依赖循环，故在本次选择Exception；若Exception未获批准，
   任务继续blocked而不自动增行。
2. 给七参数API增加signer FD：改变handoff/exact FD set更大，拒绝。
3. caller/env传seeds或adapter内嵌keys：违反API/custody，拒绝。
4. 预签acceptance、复用handoff/service signature：存在statement时序或domain/quorum错误，拒绝。
5. generic `sign(digest)` RPC：形成三角色签名oracle，拒绝。
6. executable file capability：引入未签`security.capability`版本/rootid、mount `nosuid`与inode metadata authority，
   且仍不能在缺`CAP_SETPCAP`时清bounding set，拒绝。
7. 以U内root身份exec后再切service UID/GID：需要额外root identity/map与post-exec setuid/group surface，
   相比exact `[8,19]` ambient bridge扩大TCB，拒绝。
