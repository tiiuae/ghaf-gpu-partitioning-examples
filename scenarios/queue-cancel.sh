# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# shellcheck shell=bash

set -eu

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

gpu-partition-run --slot 0 burn --seconds 60 > "$work_dir/active.log" &
active_pid=$!
sleep 2
gpu-partition-run --slot 0 burn --seconds 5 > "$work_dir/queued.log" &
queued_pid=$!
sleep 2
kill -INT "$active_pid"

if wait "$active_pid"; then
  echo "active job unexpectedly succeeded after cancellation" >&2
  exit 1
else
  active_status=$?
fi
test "$active_status" -eq 130
wait "$queued_pid"
grep 'status=cancelled' "$work_dir/active.log"
grep 'plugin=burn status=ok' "$work_dir/queued.log"
echo GPU_PARTITION_QUEUE_CANCEL_OK
