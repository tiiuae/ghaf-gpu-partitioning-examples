<!--
SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Jetson Containers Interoperability

The [Jetson Containers](https://github.com/dusty-nv/jetson-containers)
ecosystem provides useful CUDA and AI framework images. Ghaf can qualify an
existing image as an optional direct-CDI workload without importing its build
system or weakening the managed-container contract.

## Important Differences

| Jetson Containers convention | Ghaf example contract |
| --- | --- |
| Detect L4T from `/etc/nv_tegra_release` | Read the version generated from pinned Nix inputs |
| Select a mutable compatible tag with `autotag` | Supply a descriptive tag plus immutable digest |
| `--runtime=nvidia` | `--device nvidia.com/gpu=all` |
| Broad default host devices and data mounts | One CDI device and one read-only test mount |
| Host networking and privileged package tests | `--network=none`, never privileged |
| Build on Jetson with optional GPU access | Build Ghaf and its examples through Nix remote builders |

GPU-VM intentionally has no `/etc/nv_tegra_release`. Unmodified `autotag`
therefore cannot be the source of compatibility truth. The example harness
parses L4T and CUDA tokens from a descriptive tag or accepts explicit
`--image-l4t` and `--image-cuda` values, then checks them against its profile
and runtime manifest.

## Qualification Procedure

1. Select an `arm64` image whose documented L4T and CUDA requirements match
   the pinned runtime.
2. Resolve and record its registry digest outside this repository.
3. Review the image source, licence, entrypoint, user, and expected storage
   cost.
4. Pull it explicitly on the test GPU-VM.
5. Run the profile harness and retain `external-smoke.json` plus raw logs.
6. Check manager and GPU-VM restarts and relevant nvgpu diagnostics.
7. Repeat on AGX and NX before claiming support for both.
8. Only then add the digest to a reviewed allowlist entry.

```bash
gpu-partition-example-external-smoke \
  --profile cuda-python \
  --image example/cuda-python:r36.5.0-cu126@sha256:DIGEST \
  --output results
```

The default is `--pull=never` behavior: the command fails if the image is not
already local. `--pull` is an explicit request to consume target storage. A
CUDA version newer than the qualified profile/runtime maximum is rejected.
`--allow-newer-cuda` exists only for a labelled research run and prints a
warning; its result must not become an allowlisted compatibility claim.

## Profiles

- `cuda-python` checks CUDA runtime discovery and device memory operations in
  direct mode, then confirms direct CUDA denial in managed mode.
- `pytorch` runs and validates a CUDA matrix multiplication in direct mode,
  then confirms `torch.cuda.is_available()` is false in managed mode.

Both profiles separately execute the mounted manager client through managed
CDI and submit a short burn. The external Python process never becomes a
manager plugin; trusted managed workloads remain Nix-built shared objects.

## Stop Conditions

Do not qualify an image if it requires privileged mode, host networking,
manually mounted GPU nodes, a newer unsupported CUDA driver, or mutable tags.
Stop on leaked GPU nodes in managed mode, manager/GPU-VM restart, kernel fault,
timeout, or incomplete cleanup. Do not change Docker daemon, storage, swap,
power mode, or system configuration to make an image pass without separate
review and approval.
