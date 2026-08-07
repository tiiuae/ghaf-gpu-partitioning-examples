# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

import os
import sys


GPU_NODES = (
    "/dev/nvgpu",
    "/dev/nvhost-gpu",
    "/dev/nvmap",
    "/dev/dri/renderD128",
)


def result_value(result):
    if isinstance(result, tuple):
        error = result[0]
        value = result[1] if len(result) > 1 else None
    else:
        error = result
        value = None
    code = getattr(error, "value", int(error) if isinstance(error, int) else None)
    return code, value


def load_runtime():
    try:
        from cuda.bindings import runtime
    except ImportError:
        try:
            from cuda import cudart as runtime
        except ImportError:
            from cuda import runtime
    return runtime


def direct_test(runtime):
    code, count = result_value(runtime.cudaGetDeviceCount())
    if code != 0 or count is None or count < 1:
        raise RuntimeError(f"cudaGetDeviceCount failed: code={code} count={count}")
    code, allocation = result_value(runtime.cudaMalloc(4096))
    if code != 0 or allocation is None:
        raise RuntimeError(f"cudaMalloc failed: code={code}")
    try:
        code, _ = result_value(runtime.cudaMemset(allocation, 0x5A, 4096))
        if code != 0:
            raise RuntimeError(f"cudaMemset failed: code={code}")
        code, _ = result_value(runtime.cudaDeviceSynchronize())
        if code != 0:
            raise RuntimeError(f"cudaDeviceSynchronize failed: code={code}")
    finally:
        runtime.cudaFree(allocation)
    print(f"EXTERNAL_CUDA_PYTHON_DIRECT_OK devices={count}")


def managed_test(runtime):
    leaked = [node for node in GPU_NODES if os.path.exists(node)]
    if leaked:
        raise RuntimeError(f"managed CDI exposed GPU nodes: {leaked}")
    try:
        code, count = result_value(runtime.cudaGetDeviceCount())
    except Exception as error:  # CUDA bindings may raise before returning an error.
        print(f"EXTERNAL_CUDA_PYTHON_MANAGED_OK unavailable={type(error).__name__}")
        return
    if code == 0 and count and count > 0:
        raise RuntimeError("managed CDI allowed direct CUDA access")
    print(f"EXTERNAL_CUDA_PYTHON_MANAGED_OK code={code} devices={count}")


if len(sys.argv) != 2 or sys.argv[1] not in ("direct", "managed"):
    raise SystemExit(f"usage: {sys.argv[0]} direct|managed")

cuda_runtime = load_runtime()
if sys.argv[1] == "direct":
    direct_test(cuda_runtime)
else:
    managed_test(cuda_runtime)
