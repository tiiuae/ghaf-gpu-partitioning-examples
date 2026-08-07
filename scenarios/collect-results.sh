# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# shellcheck shell=bash

set -eu

output=
probe=false

usage() {
  echo "Usage: gpu-partition-example-collect-results --output DIR [--probe]"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --output)
      [ "$#" -ge 2 ] || {
        usage >&2
        exit 2
      }
      output=$2
      shift 2
      ;;
    --probe)
      probe=true
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

[ -n "$output" ] || {
  usage >&2
  exit 2
}
if [ -e "$output" ] && [ -n "$(find "$output" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then
  echo "output directory is not empty: $output" >&2
  exit 1
fi
mkdir -p "$output"

runtime_arguments=()
if $probe; then
  runtime_arguments+=(--probe)
fi
gpu-partition-example-runtime-info "${runtime_arguments[@]}" --output "$output/runtime.json"
gpu-partition-run list > "$output/plugins.txt"
gpu-partition-run status > "$output/manager-status.txt"
systemctl --failed --no-legend > "$output/failed-units.txt" || true
journalctl -u gpu-partition-manager.service -b --no-pager > "$output/manager-journal.txt"
journalctl -k -b --no-pager \
  | grep -Ei 'Xid|timed? ?out|page fault|GPU fault|BUG:|Oops:' \
    > "$output/kernel-diagnostics.txt" || true

jq -n \
  --slurpfile runtime "$output/runtime.json" \
  --rawfile plugins "$output/plugins.txt" \
  --rawfile managerStatus "$output/manager-status.txt" \
  --rawfile failedUnits "$output/failed-units.txt" \
  --rawfile kernelDiagnostics "$output/kernel-diagnostics.txt" \
  '{
    schemaVersion: 1,
    runtime: $runtime[0],
    observations: {
      plugins: ($plugins | split("\n") | map(select(length > 0))),
      managerStatus: $managerStatus,
      failedUnits: ($failedUnits | split("\n") | map(select(length > 0))),
      kernelDiagnostics: ($kernelDiagnostics | split("\n") | map(select(length > 0)))
    },
    tests: []
  }' > "$output/results.json"

echo "GPU_PARTITION_RESULTS_OK output=$output/results.json"
