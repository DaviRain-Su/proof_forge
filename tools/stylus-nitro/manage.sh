#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
revision="$(tr -d '[:space:]' < "$repo_root/tools/stylus-nitro/nitro-testnode.rev")"
source_url="https://github.com/OffchainLabs/nitro-testnode.git"
checkout="${PROOF_FORGE_NITRO_TESTNODE_DIR:-$repo_root/build/tools/nitro-testnode}"
endpoint="${PROOF_FORGE_STYLUS_ENDPOINT:-http://127.0.0.1:8547}"
dev_key="b6b15c8cb491557369f3c7d2c287b053eb229daa9c22138887752191c9520659"

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "stylus-nitro: required command not found: $1" >&2
    exit 1
  }
}

install_testnode() {
  require_command git
  mkdir -p "$(dirname "$checkout")"
  if [[ ! -d "$checkout/.git" ]]; then
    git clone --filter=blob:none --no-checkout "$source_url" "$checkout"
  fi
  git -C "$checkout" fetch --depth 1 origin "$revision"
  git -C "$checkout" checkout --detach "$revision"
  git -C "$checkout" submodule update --init --recursive --depth 1
  actual="$(git -C "$checkout" rev-parse HEAD)"
  [[ "$actual" == "$revision" ]] || {
    echo "stylus-nitro: expected $revision, checked out $actual" >&2
    exit 1
  }
  echo "stylus-nitro: installed $revision at $checkout"
}

require_docker() {
  require_command docker
  docker compose version >/dev/null
  docker info >/dev/null 2>&1 || {
    echo "stylus-nitro: Docker daemon is not available" >&2
    exit 1
  }
}

wait_rpc() {
  require_command curl
  attempts="${PROOF_FORGE_NITRO_WAIT_ATTEMPTS:-180}"
  for ((attempt = 1; attempt <= attempts; attempt++)); do
    response="$(curl -fsS -H 'content-type: application/json' \
      --data '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' \
      "$endpoint" 2>/dev/null || true)"
    if [[ "$response" == *'"result"'* ]]; then
      echo "stylus-nitro: RPC ready at $endpoint ($response)"
      return 0
    fi
    sleep 2
  done
  echo "stylus-nitro: RPC did not become ready at $endpoint" >&2
  return 1
}

case "${1:-}" in
  install)
    install_testnode
    ;;
  init)
    [[ "${PROOF_FORGE_NITRO_RESET:-0}" == "1" ]] || {
      echo "stylus-nitro: init resets local Nitro Docker state; set PROOF_FORGE_NITRO_RESET=1 to confirm" >&2
      exit 1
    }
    require_docker
    install_testnode
    (cd "$checkout" && ./test-node.bash --init-force --detach --nowait)
    wait_rpc
    ;;
  up)
    require_docker
    install_testnode
    (cd "$checkout" && ./test-node.bash --detach --nowait)
    wait_rpc
    ;;
  wait)
    wait_rpc
    ;;
  status)
    wait_rpc
    ;;
  down)
    require_docker
    [[ -d "$checkout" ]] || exit 0
    (cd "$checkout" && docker compose down --remove-orphans)
    ;;
  key)
    key_path="$repo_root/build/stylus/nitro/dev-private-key"
    mkdir -p "$(dirname "$key_path")"
    printf '%s\n' "$dev_key" > "$key_path"
    chmod 600 "$key_path"
    printf '%s\n' "$key_path"
    ;;
  --self-test)
    [[ "$revision" =~ ^[0-9a-f]{40}$ ]]
    [[ "$source_url" == "https://github.com/OffchainLabs/nitro-testnode.git" ]]
    [[ "$endpoint" == http://127.0.0.1:8547 || -n "${PROOF_FORGE_STYLUS_ENDPOINT:-}" ]]
    [[ "$checkout" == "$repo_root"/build/* || -n "${PROOF_FORGE_NITRO_TESTNODE_DIR:-}" ]]
    echo "stylus-nitro-manage: self-test ok ($revision)"
    ;;
  *)
    echo "usage: $0 {install|init|up|wait|status|down|key|--self-test}" >&2
    exit 2
    ;;
esac
