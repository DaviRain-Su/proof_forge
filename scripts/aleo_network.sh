#!/bin/bash -p
# Explicit Aleo DevNet/Testnet deployment wrapper.
#
# Consumes an existing Aleo compile-profile proof-forge.output.v1 directory and
# publishes a separate deployment receipt. It does not build, finalize, mutate,
# or append to the OutputSet. Mainnet/canary are intentionally rejected.
#
# Authority: docs/targets/09c-aleo-network.md
set -euo pipefail

export PATH=/usr/bin:/bin

script_source=${BASH_SOURCE[0]}
if [[ ${script_source} != /* ]]; then
  script_source=${PWD}/${script_source}
fi
script_dir=${script_source%/*}
repo_root=${script_dir%/*}

exec /usr/bin/python3 -I -S "${repo_root}/scripts/aleo_network_receipt.py" "$@"
