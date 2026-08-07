# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# shellcheck shell=bash

set -eu

runtime_manifest=${runtime_manifest:?runtime manifest path was not injected}
probe=false
output=-

usage() {
  echo "Usage: gpu-partition-example-runtime-info [--probe] [--output FILE]"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --probe)
      probe=true
      shift
      ;;
    --output)
      [ "$#" -ge 2 ] || {
        usage >&2
        exit 2
      }
      output=$2
      shift 2
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

status=$(gpu-partition-run status)

status_field() {
  printf '%s\n' "$status" | tr ' ' '\n' | sed -n "s/^$1=//p"
}

total_sm_count=$(status_field total_sm_count)
slot0_sm_count=$(status_field slot0_sm_count)
slot0_busy=$(status_field slot0_busy)
slot0_queued=$(status_field slot0_queued)
slot1_sm_count=$(status_field slot1_sm_count)
slot1_busy=$(status_field slot1_busy)
slot1_queued=$(status_field slot1_queued)
jobs=$(status_field jobs)

for value in "$total_sm_count" "$slot0_sm_count" "$slot0_busy" \
  "$slot0_queued" "$slot1_sm_count" "$slot1_busy" "$slot1_queued" "$jobs"; do
  case "$value" in
    '' | *[!0-9]*)
      echo "invalid manager status: $status" >&2
      exit 1
      ;;
  esac
done

driver_version_json=null
device_name_json=null
compute_capability_json=null
probe_result_json=null
if $probe; then
  if [ "$jobs" -ne 0 ]; then
    echo "refusing capability probe while manager jobs are active" >&2
    exit 1
  fi
  probe_log=$(gpu-vm-green-context-probe --min-sm-count "$slot0_sm_count" 2>&1)
  probe_device=$(printf '%s\n' "$probe_log" | grep '^device=0 ' | tail -1)
  driver_version=$(printf '%s\n' "$probe_device" | sed -n 's/.*driver_version=\([0-9][0-9]*\).*/\1/p')
  device_name=$(printf '%s\n' "$probe_device" | sed -n 's/^device=0 name=\(.*\) driver_version=.*/\1/p')
  compute_capability=$(printf '%s\n' "$probe_device" | sed -n 's/.*compute_capability=\([^ ]*\).*/\1/p')
  case "$driver_version" in
    '' | *[!0-9]*)
      echo "could not parse CUDA driver version from probe" >&2
      exit 1
      ;;
  esac
  [ -n "$device_name" ] && [ -n "$compute_capability" ] || {
    echo "could not parse CUDA device identity from probe" >&2
    exit 1
  }
  printf '%s\n' "$probe_log" | grep -q 'GREEN_CONTEXT_PROBE_OK groups=2'
  driver_version_json=$driver_version
  device_name_json=$(jq -Rn --arg value "$device_name" '$value')
  compute_capability_json=$(jq -Rn --arg value "$compute_capability" '$value')
  probe_result_json='"ok"'
fi

docker_version=$(docker version --format '{{.Server.Version}}')
manager_restarts=$(systemctl show gpu-partition-manager.service -p NRestarts --value)
cdi_version=$(jq -r '.cdiVersion' /etc/cdi/nvidia.json)
cdi_devices=$(jq -c '[.devices[].name | "nvidia.com/gpu=" + .]' /etc/cdi/nvidia.json)
generated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

jq -n \
  --slurpfile manifest "$runtime_manifest" \
  --arg generatedAt "$generated_at" \
  --arg kernel "$(uname -r)" \
  --arg docker "$docker_version" \
  --arg cdiVersion "$cdi_version" \
  --argjson cdiDevices "$cdi_devices" \
  --argjson managerRestarts "$manager_restarts" \
  --argjson totalSmCount "$total_sm_count" \
  --argjson slot0SmCount "$slot0_sm_count" \
  --argjson slot0Busy "$slot0_busy" \
  --argjson slot0Queued "$slot0_queued" \
  --argjson slot1SmCount "$slot1_sm_count" \
  --argjson slot1Busy "$slot1_busy" \
  --argjson slot1Queued "$slot1_queued" \
  --argjson jobs "$jobs" \
  --argjson driverVersion "$driver_version_json" \
  --argjson deviceName "$device_name_json" \
  --argjson computeCapability "$compute_capability_json" \
  --argjson probeResult "$probe_result_json" \
  '{
    schemaVersion: 1,
    generatedAt: $generatedAt,
    build: $manifest[0],
    runtime: {
      kernel: $kernel,
      docker: $docker,
      cdi: { version: $cdiVersion, devices: $cdiDevices },
      cuda: {
        driverVersion: $driverVersion,
        device: $deviceName,
        computeCapability: $computeCapability,
        probe: $probeResult
      },
      manager: {
        restarts: $managerRestarts,
        totalSmCount: $totalSmCount,
        jobs: $jobs,
        slots: [
          { id: 0, smCount: $slot0SmCount, busy: $slot0Busy, queued: $slot0Queued },
          { id: 1, smCount: $slot1SmCount, busy: $slot1Busy, queued: $slot1Queued }
        ]
      }
    }
  }' | if [ "$output" = - ]; then cat; else tee "$output" >/dev/null; fi
