# ProofShip Cloud · C0 spike — gate in a container

**问题**：真实产品门禁（`check → build --target evm → inspect`）能否在精简 Linux 容器里跑？
镜像多大、冷启动多久、单次 gate 多长？数据回写 [`docs/plan/proofship-cloud.md`](../../docs/plan/proofship-cloud.md) §3.3。

## 复现

```bash
# 1. 准备精简上下文（repo 根执行；只拷门禁所需文件，约 11MB）
proofship/cloud-spike/prepare-context.sh

# 2. 构建镜像（含 elan + Lean v4.31.0 + lake build + locked EVM 工具）
docker build -f proofship/cloud-spike/Dockerfile -t proofship-gate-c0 proofship/cloud-spike/context

# 3. 量测
docker images proofship-gate-c0 --format 'image size: {{.Size}}'
time docker run --rm proofship-gate-c0 version
time docker run --rm proofship-gate-c0 check \
  /spike/RwaShareRegistry.lean --module RwaShareRegistry --root /spike
time docker run --rm proofship-gate-c0 build \
  /spike/RwaShareRegistry.lean --module RwaShareRegistry --root /spike \
  --target evm -o /spike/out-evm
```

（`/spike` 内的 `--root` 是容器内路径；`-o` 相对 root。）

## 已踩的坑（本机 colima）

| 坑 | 解法 |
|---|---|
| colima VM 残留失效代理 env（192.168.5.2:15236） | `colima stop x86 && colima start x86`（无代理 env；宿主机直连 Docker Hub 可达） |
| VM 内 `/etc/resolv.conf` 死符号链接 → 无 DNS | `rm -f` 后写入 `nameserver 1.1.1.1/8.8.8.8`（重启若复发需固化进 lima 配置） |
| x86_64 模拟（QEMU on aarch64）编译慢 ~7× | C0 接受；云上原生 x86_64 runner 无此问题 |
| `ProofForgeV2/Compiler/Native/*.c` 是 lakefile extern_lib 必需 | context 必须包含 .c（lakefile 在 Linux 用 /usr/bin/cc） |
| `Core/ToolLockV4.lean` 用 `include_str ../../toolchains*.lock.json` | lock 清单是**编译期**输入，COPY 必须在 `lake build` 之前（层序错 = 全量重编） |

## 结果

（构建完成后填：image size / version 冷启动 / check 时长 / build 时长 → 回写 cloud 文档 §3.3）
