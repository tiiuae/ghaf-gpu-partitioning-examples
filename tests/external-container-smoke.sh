# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# shellcheck shell=bash

set -euo pipefail

source_root=$1
work_dir=$(mktemp -d)
bash_path=$(command -v bash)
trap 'rm -rf "$work_dir"' EXIT
mkdir -p "$work_dir/bin" "$work_dir/tests"

digest=$(printf 'a%.0s' $(seq 1 64))
image="example/cuda-python:r36.5.0-cu126@sha256:$digest"

cat > "$work_dir/profiles.json" <<'EOF'
{
  "schemaVersion": 1,
  "profiles": {
    "cuda-python": {
      "executable": "python3",
      "test": "cuda-python.py",
      "requirements": {
        "architecture": "arm64",
        "l4tMajor": 36,
        "l4tMinimum": "36.4",
        "cudaMaximum": "12.6"
      }
    }
  }
}
EOF
cp "$source_root/external-tests/cuda-python.py" "$work_dir/tests/cuda-python.py"

cat > "$work_dir/cdi.json" <<'EOF'
{
  "cdiVersion": "0.6.0",
  "kind": "nvidia.com/gpu",
  "devices": [
    { "name": "all", "containerEdits": { "deviceNodes": [{ "path": "/dev/nvgpu" }] } },
    { "name": "managed", "containerEdits": { "mounts": [] } }
  ]
}
EOF

cat > "$work_dir/bin/runtime-info" <<EOF
#!$bash_path
set -eu
[ "\$1" = "--output" ]
cat > "\$2" <<'JSON'
{
  "schemaVersion": 1,
  "build": { "platform": { "l4t": "36.5.0-test", "cuda": "12.6" } },
  "runtime": { "manager": { "jobs": 0 } }
}
JSON
EOF
chmod +x "$work_dir/bin/runtime-info"

cat > "$work_dir/bin/docker" <<EOF
#!$bash_path
set -eu
printf '%s\n' "\$*" >> "\${MOCK_DOCKER_LOG:?}"
case "\$1 \${2:-}" in
  "image inspect")
    if [ "\${3:-}" = "--format" ]; then
      case "\$4" in
        *Architecture*) echo arm64 ;;
        *RepoDigests*) echo '["example/cuda-python@sha256:$digest"]' ;;
      esac
    fi
    ;;
  "rm -f") exit 0 ;;
  "run --name")
    case "\$*" in
      *gpu-partition-run*status*) echo 'total_sm_count=16 slot0_sm_count=8 slot1_sm_count=8 jobs=0' ;;
      *gpu-partition-run*burn*) echo 'plugin=burn status=ok sm_count=8 seconds=5 iterations=1' ;;
      *managed*) echo EXTERNAL_CUDA_PYTHON_MANAGED_OK ;;
      *) echo EXTERNAL_CUDA_PYTHON_DIRECT_OK ;;
    esac
    ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$work_dir/bin/docker"

if profile_manifest="$work_dir/profiles.json" \
  external_test_directory="$work_dir/tests" \
  GPU_PARTITION_RUNTIME_INFO_COMMAND="$work_dir/bin/runtime-info" \
  GPU_PARTITION_CDI_SPEC="$work_dir/cdi.json" \
  PATH="$work_dir/bin:$PATH" \
  bash "$source_root/scenarios/external-container-smoke.sh" \
    --profile cuda-python --image example/cuda-python:latest \
    --output "$work_dir/invalid" 2>/dev/null; then
  echo "mutable image reference was accepted" >&2
  exit 1
fi

profile_manifest="$work_dir/profiles.json" \
external_test_directory="$work_dir/tests" \
GPU_PARTITION_RUNTIME_INFO_COMMAND="$work_dir/bin/runtime-info" \
GPU_PARTITION_CDI_SPEC="$work_dir/cdi.json" \
MOCK_DOCKER_LOG="$work_dir/docker.log" \
PATH="$work_dir/bin:$PATH" \
bash "$source_root/scenarios/external-container-smoke.sh" \
  --profile cuda-python --image "$image" --output "$work_dir/result"

jq -e '
  .schemaVersion == 1 and
  .image.profile == "cuda-python" and
  .image.architecture == "arm64" and
  (.tests | length) == 4 and
  all(.tests[]; .status == "ok")
' "$work_dir/result/external-smoke.json" >/dev/null

run_count=$(grep -c '^run ' "$work_dir/docker.log")
[ "$run_count" -eq 4 ]
[ "$(grep -c -- '--device nvidia.com/gpu=all' "$work_dir/docker.log")" -eq 1 ]
[ "$(grep -c -- '--device nvidia.com/gpu=managed' "$work_dir/docker.log")" -eq 3 ]
[ "$(grep -c -- '--network=none' "$work_dir/docker.log")" -eq 4 ]
if grep -Eq -- '--privileged|--runtime(=| )|--network=(host|container:)' "$work_dir/docker.log"; then
  echo "unsafe container option was used" >&2
  exit 1
fi

echo EXTERNAL_CONTAINER_OFFLINE_TEST_OK
