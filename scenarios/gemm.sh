# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
# shellcheck shell=bash

set -eu

size=${1:-1024}
seconds=${2:-30}

gpu-partition-run gemm --size "$size" --seconds "$seconds"
