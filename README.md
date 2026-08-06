<!--
SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Ghaf GPU Partitioning Examples

This repository provides reproducible CUDA load examples for Ghaf's managed
GPU partitioning support on NVIDIA Jetson Orin AGX and Orin NX. It consumes
Ghaf as a pinned flake input. GPU passthrough, service integration, and the
Container Device Interface (CDI) remain upstream in Ghaf. The daemon, client,
protocol, plugin ABI, and mock-CUDA tests live in the standalone
[`ghaf-gpu-partition-manager`](https://github.com/tiiuae/ghaf-gpu-partition-manager)
repository that Ghaf pins.

The initial revision depends on
[Ghaf PR 2095](https://github.com/tiiuae/ghaf/pull/2095) through its
authoritative pull-request ref. `flake.lock` fixes the exact reviewed commit.
After that PR merges, change the input URL to `github:tiiuae/ghaf` and update
the lock in a dedicated pull request.

The examples include:

- trusted `burn` and `latency` manager plugins;
- direct and managed container images;
- CDI smoke tests;
- simultaneous two-slot endurance tests;
- queue and cancellation checks; and
- exploratory managed-versus-unmanaged interference measurements.

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

After boot, connect through NetVM and run the smoke suite:

```bash
ssh -J ghaf@NETVM_LAN_IP ghaf@192.168.100.4
gpu-partition-example-smoke
```

See [User Guide](docs/user-guide.md) for deployment and every installed
command. See [Architecture](docs/architecture.md) and
[Plugin Development](docs/plugin-development.md) before adding workloads.

## Validation Status

The original implementation was live-validated on AGX with a 16-SM resource,
an 8+8 split, concurrent workloads, cancellation, managed CDI, and a 30-minute
dual-slot run. NX currently has build and evaluation coverage only; live NX
validation remains required.

The historical measurements and their limitations are recorded in
[AGX Validation](docs/results/agx-2026-08-06.md).
