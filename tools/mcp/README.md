# ProofForge MCP-V0

Minimal **stdio** MCP server that exposes product CLI tools for Code Agents.

Authority: [`docs/product/01-toolchain-install-surface.md`](../../docs/product/01-toolchain-install-surface.md) §8.

## Tools

| Tool | CLI mapping |
|---|---|
| `pf_list_targets` | `proof-forge-next list-targets [--all] --json` |
| `pf_doctor` | `proof-forge-next doctor --json` |
| `pf_install` | `proof-forge-next install --targets … --yes --json` |
| `pf_build` | `proof-forge-next build <source> --module … --target … -o … --json` |
| `pf_artifacts` | `proof-forge-next inspect --output-dir <dir> --json` |
| `pf_local` | `proof-forge-next local --target … [--mode sandbox] -- --source … --module …` |

- **No** default network broadcast tool (use product CLI `network --broadcast` explicitly if needed).
- Aleo `pf_local` is **generic**: requires `source` + `module`; optional `runs` / `golden` / `skipRun` — no default program.
- Tools **only** spawn the product CLI / package engines; they do **not** reimplement solc/leo/nargo.
- Tool Lock installs never use PATH fallback into `PROOF_FORGE_TOOL_ROOT`.
- Success is **not** formal / hermetic / mainnet / `deployable=true` evidence.

## Prerequisites

```bash
# From package root
lake build          # produces .lake/build/bin/proof-forge-next
# Optional: install toolchain assets for a target
./.lake/build/bin/proof-forge-next install --targets quint --yes
```

## Agent wiring (Cursor / Claude Desktop / other MCP hosts)

```json
{
  "mcpServers": {
    "proof-forge": {
      "command": "/usr/bin/python3",
      "args": [
        "-I",
        "/absolute/path/to/proof_forge/tools/mcp/proof_forge_mcp_server.py"
      ],
      "env": {
        "PROOF_FORGE_ROOT": "/absolute/path/to/proof_forge",
        "PROOF_FORGE_CLI": "/absolute/path/to/proof_forge/.lake/build/bin/proof-forge-next",
        "PROOF_FORGE_TOOL_ROOT": "/absolute/path/to/tool-root/linux-x86_64"
      }
    }
  }
}
```

Notes:

- `PROOF_FORGE_ROOT` must contain `scripts/proof_forge_doctor.py` (package root).
- `PROOF_FORGE_CLI` is optional if `.lake/build/bin/proof-forge-next` exists under the root.
- Inherit or set `PROOF_FORGE_TOOL_ROOT` so doctor/install/build see locked tools (never PATH fallback).

## Self-check / smoke

```bash
/usr/bin/python3 -I tools/mcp/proof_forge_mcp_server.py --self-check
scripts/mcp_smoke.sh
```

## Design boundaries

- Package is stdlib-only Python (no extra pip dependency).
- `pf_install` always passes `--yes` unless `dryRun=true` (non-interactive).
- `pf_build` rejects `broadcast` / `network` arguments.
- Design-only targets (`soroban`, `icp`, `openvm`) remain unsupported for install.
