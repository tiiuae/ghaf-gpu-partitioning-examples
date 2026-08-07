# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# shellcheck shell=bash

set -eu

profile_manifest=${profile_manifest:?external profile manifest path was not injected}
external_test_directory=${external_test_directory:?external test directory was not injected}
profile=
image=
output=
pull=false
allow_newer_cuda=false
image_l4t=
image_cuda=
runtime_info_command=${GPU_PARTITION_RUNTIME_INFO_COMMAND:-gpu-partition-example-runtime-info}
cdi_spec=${GPU_PARTITION_CDI_SPEC:-/etc/cdi/nvidia.json}
direct_container="ghaf-gpu-external-direct-$$"
managed_container="ghaf-gpu-external-managed-$$"

usage() {
  cat <<'EOF'
Usage: gpu-partition-example-external-smoke \
  --profile cuda-python|pytorch \
  --image REPOSITORY:TAG@sha256:DIGEST \
  --output DIR [--pull] [--image-l4t VERSION] [--image-cuda VERSION] \
  [--allow-newer-cuda]
EOF
}

cleanup() {
  docker rm -f "$direct_container" "$managed_container" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

while [ "$#" -gt 0 ]; do
  case "$1" in
    --profile)
      [ "$#" -ge 2 ] || {
        usage >&2
        exit 2
      }
      profile=$2
      shift 2
      ;;
    --image)
      [ "$#" -ge 2 ] || {
        usage >&2
        exit 2
      }
      image=$2
      shift 2
      ;;
    --output)
      [ "$#" -ge 2 ] || {
        usage >&2
        exit 2
      }
      output=$2
      shift 2
      ;;
    --pull)
      pull=true
      shift
      ;;
    --image-l4t)
      image_l4t=$2
      shift 2
      ;;
    --image-cuda)
      image_cuda=$2
      shift 2
      ;;
    --allow-newer-cuda)
      allow_newer_cuda=true
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

[ -n "$profile" ] && [ -n "$image" ] && [ -n "$output" ] || {
  usage >&2
  exit 2
}
printf '%s\n' "$image" | grep -Eq '^.+:.+@sha256:[0-9a-f]{64}$' || {
  echo "image must include both a descriptive tag and an immutable sha256 digest" >&2
  exit 2
}
jq -e --arg profile "$profile" '.profiles[$profile]' "$profile_manifest" >/dev/null || {
  echo "unknown external image profile: $profile" >&2
  exit 2
}
if [ -e "$output" ] && [ -n "$(find "$output" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then
  echo "output directory is not empty: $output" >&2
  exit 1
fi
mkdir -p "$output"

if $pull; then
  docker pull "$image"
else
  docker image inspect "$image" >/dev/null 2>&1 || {
    echo "image is not local; rerun with --pull after approving the storage impact" >&2
    exit 1
  }
fi

architecture=$(docker image inspect --format '{{.Architecture}}' "$image" | head -1)
required_architecture=$(jq -r --arg profile "$profile" '.profiles[$profile].requirements.architecture' "$profile_manifest")
[ "$architecture" = "$required_architecture" ] || {
  echo "image architecture $architecture does not match required $required_architecture" >&2
  exit 1
}

tag=${image%%@sha256:*}
tag=${tag##*:}
if [ -z "$image_l4t" ]; then
  image_l4t=$(printf '%s\n' "$tag" | grep -oE 'r[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 | sed 's/^r//')
fi
if [ -z "$image_cuda" ]; then
  cuda_tag=$(printf '%s\n' "$tag" | grep -oE 'cu[0-9]{3}' | head -1 || true)
  if [ -n "$cuda_tag" ]; then
    cuda_digits=${cuda_tag#cu}
    image_cuda="${cuda_digits%?}.${cuda_digits#??}"
  fi
fi
[ -n "$image_l4t" ] && [ -n "$image_cuda" ] || {
  echo "could not determine image L4T/CUDA versions; use --image-l4t and --image-cuda" >&2
  exit 1
}

"$runtime_info_command" --output "$output/runtime.json"
runtime_l4t=$(jq -r '.build.platform.l4t' "$output/runtime.json" | grep -oE '^[0-9]+\.[0-9]+')
runtime_cuda=$(jq -r '.build.platform.cuda' "$output/runtime.json")
required_l4t_major=$(jq -r --arg profile "$profile" '.profiles[$profile].requirements.l4tMajor' "$profile_manifest")
required_l4t_minimum=$(jq -r --arg profile "$profile" '.profiles[$profile].requirements.l4tMinimum' "$profile_manifest")
required_cuda_maximum=$(jq -r --arg profile "$profile" '.profiles[$profile].requirements.cudaMaximum' "$profile_manifest")

[ "${image_l4t%%.*}" = "$required_l4t_major" ] || {
  echo "image L4T $image_l4t is outside profile major $required_l4t_major" >&2
  exit 1
}
[ "$(printf '%s\n%s\n' "$required_l4t_minimum" "$image_l4t" | sort -V | head -1)" = "$required_l4t_minimum" ] || {
  echo "image L4T $image_l4t is older than $required_l4t_minimum" >&2
  exit 1
}
[ "${runtime_l4t%%.*}" = "$required_l4t_major" ] || {
  echo "runtime L4T $runtime_l4t is outside profile major $required_l4t_major" >&2
  exit 1
}
[ "$(printf '%s\n%s\n' "$required_l4t_minimum" "$runtime_l4t" | sort -V | head -1)" = "$required_l4t_minimum" ] || {
  echo "runtime L4T $runtime_l4t is older than $required_l4t_minimum" >&2
  exit 1
}
if [ "$(printf '%s\n%s\n' "$image_cuda" "$required_cuda_maximum" | sort -V | tail -1)" != "$required_cuda_maximum" ]; then
  if ! $allow_newer_cuda; then
    echo "image CUDA $image_cuda is newer than qualified maximum $required_cuda_maximum" >&2
    exit 1
  fi
  echo "WARNING: allowing unqualified newer image CUDA $image_cuda" >&2
fi
if [ "$(printf '%s\n%s\n' "$image_cuda" "$runtime_cuda" | sort -V | tail -1)" != "$runtime_cuda" ] && ! $allow_newer_cuda; then
  echo "image CUDA $image_cuda is newer than runtime CUDA $runtime_cuda" >&2
  exit 1
fi

jq -e '.devices[] | select(.name == "managed") | ((.containerEdits.deviceNodes // []) | length == 0)' \
  "$cdi_spec" >/dev/null

test_name=$(jq -r --arg profile "$profile" '.profiles[$profile].test' "$profile_manifest")
executable=$(jq -r --arg profile "$profile" '.profiles[$profile].executable' "$profile_manifest")
test_source="$external_test_directory/$test_name"
[ -f "$test_source" ] || {
  echo "profile test is missing: $test_source" >&2
  exit 1
}

timeout 180 docker run --name "$direct_container" --rm --network=none \
  --device nvidia.com/gpu=all \
  --mount "type=bind,src=$test_source,dst=/opt/ghaf-external-test,readonly" \
  --entrypoint "$executable" "$image" /opt/ghaf-external-test direct \
  | tee "$output/direct.log"

timeout 180 docker run --name "$managed_container" --rm --network=none \
  --device nvidia.com/gpu=managed \
  --mount "type=bind,src=$test_source,dst=/opt/ghaf-external-test,readonly" \
  --entrypoint "$executable" "$image" /opt/ghaf-external-test managed \
  | tee "$output/managed-negative.log"

timeout 60 docker run --name "$managed_container" --rm --network=none \
  --device nvidia.com/gpu=managed \
  --entrypoint /opt/ghaf/bin/gpu-partition-run "$image" status \
  | tee "$output/managed-status.log"

timeout 120 docker run --name "$managed_container" --rm --network=none \
  --device nvidia.com/gpu=managed \
  --entrypoint /opt/ghaf/bin/gpu-partition-run "$image" burn --seconds 5 \
  | tee "$output/managed-burn.log"

resolved_digests=$(docker image inspect --format '{{json .RepoDigests}}' "$image")
jq -n \
  --slurpfile runtime "$output/runtime.json" \
  --arg profile "$profile" \
  --arg reference "$image" \
  --arg architecture "$architecture" \
  --arg imageL4t "$image_l4t" \
  --arg imageCuda "$image_cuda" \
  --argjson resolvedDigests "$resolved_digests" \
  --rawfile direct "$output/direct.log" \
  --rawfile managedNegative "$output/managed-negative.log" \
  --rawfile managedStatus "$output/managed-status.log" \
  --rawfile managedBurn "$output/managed-burn.log" \
  '{
    schemaVersion: 1,
    runtime: $runtime[0],
    image: {
      profile: $profile,
      reference: $reference,
      resolvedDigests: $resolvedDigests,
      architecture: $architecture,
      l4t: $imageL4t,
      cuda: $imageCuda
    },
    tests: [
      { name: "direct", status: "ok", output: $direct },
      { name: "managed-direct-denial", status: "ok", output: $managedNegative },
      { name: "managed-status", status: "ok", output: $managedStatus },
      { name: "managed-burn", status: "ok", output: $managedBurn }
    ]
  }' > "$output/external-smoke.json"

echo "GPU_PARTITION_EXTERNAL_SMOKE_OK output=$output/external-smoke.json"
