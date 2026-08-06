# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# shellcheck shell=bash

set -eu

iterations="${1:-10000}"
burn_seconds="${2:-30}"
work_dir="$(mktemp -d)"
cleanup() {
  status=$?
  trap - EXIT INT TERM
  while IFS= read -r pid; do
    kill "$pid" 2>/dev/null || true
  done < <(jobs -pr)
  wait 2>/dev/null || true
  if [ "$status" -ne 0 ]; then
    echo "results retained in $work_dir" >&2
  else
    rm -rf "$work_dir"
  fi
  exit "$status"
}
trap cleanup EXIT INT TERM

echo "case=baseline"
gpu-partition-run --slot 0 latency --iterations "$iterations"

echo "case=managed_coload"
gpu-partition-run --slot 1 burn --seconds "$burn_seconds" > "$work_dir/managed-burn.log" &
managed_pid=$!
sleep 2
gpu-partition-run --slot 0 latency --iterations "$iterations"
wait "$managed_pid"
grep 'plugin=burn status=ok' "$work_dir/managed-burn.log"

echo "case=unmanaged_coload"
gpu-partition-example-load "$burn_seconds" > "$work_dir/unmanaged-burn.log" &
unmanaged_pid=$!
sleep 2
gpu-partition-run --slot 0 latency --iterations "$iterations"
wait "$unmanaged_pid"
grep GPU_LOAD_OK "$work_dir/unmanaged-burn.log"
echo GPU_PARTITION_INTERFERENCE_OK
