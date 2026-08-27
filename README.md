<!--
SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Ghaf GPU Partitioning Examples

This repository provides reproducible CUDA load examples for Ghaf's managed
GPU partitioning support on NVIDIA Jetson Orin AGX and Orin NX. It consumes
Ghaf as a pinned flake input. Ghaf owns the reusable Orin GPU/display VM
compositions and consumes hardware descriptions and policy from jetpack-nixos.
This repository adds the container runtime, partition manager integration,
plugins, probes, scenarios, and workload payloads. The daemon, client, protocol,
plugin ABI, and mock-CUDA tests live in the standalone
[`ghaf-gpu-partition-manager`](https://github.com/tiiuae/ghaf-gpu-partition-manager)
repository that Ghaf pins.

The passthrough examples depend on
[Ghaf PR 2133](https://github.com/tiiuae/ghaf/pull/2133) through its
authoritative pull-request ref. `flake.lock` fixes the exact reviewed commit.
After that PR merges, change the input URL to `github:tiiuae/ghaf` and update
the lock in a dedicated pull request.

The examples include:

- split GPU-VM/Display-VM and combined GUI-VM example targets for AGX and NX;
- trusted `burn`, `latency`, and cuBLAS `gemm` manager plugins;
- direct and managed container images;
- digest-pinned external CUDA/PyTorch container interoperability profiles;
- CDI smoke tests;
- simultaneous two-slot endurance tests;
- queue and cancellation checks;
- exploratory managed-versus-unmanaged interference measurements; and
- runtime compatibility manifests and machine-readable result bundles.

CUDA Green Contexts provide cooperative SM placement. They do not guarantee
security isolation, concurrent progress, memory-bandwidth isolation, or
real-time behavior.

## Quick Start

On an x86_64 build machine with Ghaf's remote builders configured:

```bash
nix build .#nvidia-jetson-orin-agx-gpu-partitioning-example
nix build .#nvidia-jetson-orin-agx-flash-script --max-jobs 8 -o result-flash
sudo -E env USER=root result-flash/bin/flash-ghaf-host -s result
```

For NX, replace `agx` with `nx`. Flashing overwrites the selected Jetson
rootfs; confirm the board is in Force Recovery Mode before running the helper.
Build `nvidia-jetson-orin-{agx,nx}-combined-example` for the combined GUI-VM
display regression topology.

After boot, connect through NetVM and run the smoke suite:

```bash
ssh -J ghaf@NETVM_LAN_IP ghaf@192.168.100.4
gpu-partition-example-smoke
```

See [User Guide](docs/user-guide.md) for deployment and every installed
command. See [Architecture](docs/architecture.md) and
[Plugin Development](docs/plugin-development.md) before adding workloads.
External images require separate qualification; see
[Jetson Containers Interoperability](docs/jetson-containers-interop.md).

## Validation Status

The extracted three-repository dependency chain was flashed and live-validated
on AGX with a 16-SM resource, an 8+8 split, direct and managed CDI, concurrent
workloads, cancellation, interference observation, and a 30-minute dual-slot
run. NX currently has build and evaluation coverage only; live NX validation
remains required.

The post-extraction measurements and their limitations are recorded in
[AGX Validation](docs/results/agx-2026-08-06.md).
