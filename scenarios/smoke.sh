# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# shellcheck shell=bash
# shellcheck disable=SC2154

set -eu

docker load < "$direct_image"
docker run --rm --device nvidia.com/gpu=all \
  ghaf-gpu-direct-example:latest | grep GPU_LOAD_OK
echo DIRECT_CDI_OK

docker load < "$managed_image"
docker run --rm --device nvidia.com/gpu=managed \
  ghaf-gpu-managed-example:latest | grep MANAGED_CONTAINER_GPU_OK
echo MANAGED_CDI_OK
echo GPU_PARTITION_EXAMPLE_SMOKE_OK
