# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# shellcheck shell=bash

set -eu

seconds="${1:-1800}"
case "$seconds" in
  *[!0-9]* | "")
    echo "usage: gpu-partition-example-endurance [seconds]" >&2
    exit 2
    ;;
esac

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

gpu-partition-run status
gpu-partition-run --slot 0 burn --seconds "$seconds" > "$work_dir/slot0.log" &
slot0_pid=$!
gpu-partition-run --slot 1 burn --seconds "$seconds" > "$work_dir/slot1.log" &
slot1_pid=$!
wait "$slot0_pid"
wait "$slot1_pid"

grep 'plugin=burn status=ok' "$work_dir/slot0.log"
grep 'plugin=burn status=ok' "$work_dir/slot1.log"
gpu-partition-run status
echo "GPU_PARTITION_ENDURANCE_OK seconds=$seconds"
