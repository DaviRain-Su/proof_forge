# shellcheck shell=bash
# Shared near-sandbox launch resolution for pf_near_*.sh / near_runtime_test.sh.
#
# Contract:
#   - Never replace or wrap the Tool Lock near-sandbox *bytes*.
#   - On Linux, may prefix an absolute userspace dynamic linker so a host with
#     older GLIBC can still exec the locked binary (engineering compatibility).
#   - Prefer direct exec when the locked binary already runs on this host.
#   - Auto-discover Tool Root pack before requiring env vars.
#
# Tool Root layout (linux-x86_64 only; optional):
#   $PROOF_FORGE_TOOL_ROOT/near-sandbox-glibc/ld-linux-x86-64.so.2
#   $PROOF_FORGE_TOOL_ROOT/near-sandbox-glibc/lib/   # LIBRARY_PATH
#   $PROOF_FORGE_TOOL_ROOT/near-sandbox-glibc/MANIFEST.json  # optional digests
#
# Env override (still supported; both required together):
#   PF_NEAR_SANDBOX_LOADER
#   PF_NEAR_SANDBOX_LIBRARY_PATH
#
# Outputs (caller must declare locals or accept globals):
#   near_sandbox_bin       — absolute path to locked near-sandbox
#   near_sandbox_command   — bash array: argv to exec (may be loader + libpath + bin)
#   near_sandbox_compat    — "direct" | "tool-root" | "env" | "unavailable"
#   near_sandbox_compat_note — human one-liner
#
# Usage:
#   # shellcheck source=scripts/lib/near_sandbox_launch.sh
#   source "$root/scripts/lib/near_sandbox_launch.sh"
#   if ! near_sandbox_resolve; then
#     skip_clean "near-sandbox not runnable: $near_sandbox_compat_note"
#   fi
#   "${near_sandbox_command[@]}" --version
#
# Honesty: compatibility launch is runner evidence, not hermetic Tool Lock pin
# until supply-chain/near-sandbox-glibc-*.json digests are lock-materialized.

near_sandbox_resolve() {
  near_sandbox_bin=""
  near_sandbox_command=()
  near_sandbox_compat="unavailable"
  near_sandbox_compat_note="near-sandbox not found"

  local tool_root="${PROOF_FORGE_TOOL_ROOT:-}"
  local candidate=""

  if [[ -n "$tool_root" && -x "${tool_root%/}/near-sandbox" ]]; then
    candidate="${tool_root%/}/near-sandbox"
  elif command -v near-sandbox >/dev/null 2>&1; then
    candidate="$(command -v near-sandbox)"
  elif [[ -x /opt/homebrew/bin/near-sandbox ]]; then
    candidate="/opt/homebrew/bin/near-sandbox"
  elif [[ -x /usr/local/bin/near-sandbox ]]; then
    candidate="/usr/local/bin/near-sandbox"
  else
    near_sandbox_compat_note="near-sandbox not found under PROOF_FORGE_TOOL_ROOT or PATH"
    return 1
  fi

  # Prefer realpath when available so loader argv is absolute and stable.
  if command -v realpath >/dev/null 2>&1; then
    near_sandbox_bin="$(realpath "$candidate")"
  else
    near_sandbox_bin="$candidate"
  fi

  # 1) Direct launch when host GLIBC is new enough.
  if "$near_sandbox_bin" --version >/dev/null 2>&1; then
    near_sandbox_command=("$near_sandbox_bin")
    near_sandbox_compat="direct"
    near_sandbox_compat_note="direct exec (host GLIBC sufficient)"
    return 0
  fi

  # Compatibility path is Linux-only (dynamic linker + --library-path).
  if [[ "$(uname -s)" != "Linux" ]]; then
    near_sandbox_compat_note="near-sandbox present but not runnable on this host (non-Linux; no compat loader)"
    return 1
  fi

  local loader="" libpath=""

  # 2) Explicit env (both or neither — caller scripts already enforce pair).
  if [[ -n "${PF_NEAR_SANDBOX_LOADER:-}" || -n "${PF_NEAR_SANDBOX_LIBRARY_PATH:-}" ]]; then
    if [[ -z "${PF_NEAR_SANDBOX_LOADER:-}" || -z "${PF_NEAR_SANDBOX_LIBRARY_PATH:-}" ]]; then
      near_sandbox_compat_note="PF_NEAR_SANDBOX_LOADER and PF_NEAR_SANDBOX_LIBRARY_PATH must be set together"
      return 1
    fi
    loader="$PF_NEAR_SANDBOX_LOADER"
    libpath="$PF_NEAR_SANDBOX_LIBRARY_PATH"
    if [[ "$loader" != /* || ! -f "$loader" || ! -x "$loader" || -L "$loader" ]]; then
      near_sandbox_compat_note="PF_NEAR_SANDBOX_LOADER must be an absolute, executable, non-symlink file"
      return 1
    fi
    if [[ ! -d "$libpath" ]]; then
      near_sandbox_compat_note="PF_NEAR_SANDBOX_LIBRARY_PATH must be an existing directory"
      return 1
    fi
    near_sandbox_command=("$loader" --library-path "$libpath" "$near_sandbox_bin")
    if "${near_sandbox_command[@]}" --version >/dev/null 2>&1; then
      near_sandbox_compat="env"
      near_sandbox_compat_note="env loader=$loader libpath=$libpath"
      return 0
    fi
    near_sandbox_compat_note="env compatibility loader failed to run near-sandbox --version"
    return 1
  fi

  # 3) Tool Root auto-discover (engineering pack; not hermetic lock pin yet).
  if [[ -n "$tool_root" ]]; then
    local pack="${tool_root%/}/near-sandbox-glibc"
    local pack_loader="$pack/ld-linux-x86-64.so.2"
    local pack_lib="$pack/lib"
    if [[ -f "$pack_loader" && -x "$pack_loader" && ! -L "$pack_loader" && -d "$pack_lib" ]]; then
      # Prefer absolute paths.
      if command -v realpath >/dev/null 2>&1; then
        pack_loader="$(realpath "$pack_loader")"
        pack_lib="$(realpath "$pack_lib")"
      fi
      near_sandbox_command=("$pack_loader" --library-path "$pack_lib" "$near_sandbox_bin")
      if "${near_sandbox_command[@]}" --version >/dev/null 2>&1; then
        near_sandbox_compat="tool-root"
        near_sandbox_compat_note="tool-root near-sandbox-glibc pack (engineering; not hermetic lock pin)"
        return 0
      fi
      near_sandbox_compat_note="tool-root near-sandbox-glibc pack present but failed to launch near-sandbox"
      return 1
    fi
  fi

  near_sandbox_compat_note="near-sandbox not runnable (host GLIBC too old?). Install engineering pack: scripts/near_sandbox_glibc_materialize.sh, or set PF_NEAR_SANDBOX_LOADER + PF_NEAR_SANDBOX_LIBRARY_PATH"
  return 1
}
