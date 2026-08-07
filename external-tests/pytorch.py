# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

import os
import sys

import torch


GPU_NODES = (
    "/dev/nvgpu",
    "/dev/nvhost-gpu",
    "/dev/nvmap",
    "/dev/dri/renderD128",
)


def direct_test():
    if not torch.cuda.is_available():
        raise RuntimeError("PyTorch reports CUDA unavailable")
    left = torch.ones((256, 256), device="cuda")
    right = torch.full((256, 256), 2.0, device="cuda")
    result = left @ right
    torch.cuda.synchronize()
    expected = torch.full((256, 256), 512.0, device="cuda")
    if not torch.equal(result, expected):
        raise RuntimeError("PyTorch CUDA matrix multiplication validation failed")
    print(
        "EXTERNAL_PYTORCH_DIRECT_OK "
        f"device={torch.cuda.get_device_name(0)!r} cuda={torch.version.cuda}"
    )


def managed_test():
    leaked = [node for node in GPU_NODES if os.path.exists(node)]
    if leaked:
        raise RuntimeError(f"managed CDI exposed GPU nodes: {leaked}")
    if torch.cuda.is_available():
        raise RuntimeError("managed CDI allowed direct PyTorch CUDA access")
    print("EXTERNAL_PYTORCH_MANAGED_OK")


if len(sys.argv) != 2 or sys.argv[1] not in ("direct", "managed"):
    raise SystemExit(f"usage: {sys.argv[0]} direct|managed")

if sys.argv[1] == "direct":
    direct_test()
else:
    managed_test()
