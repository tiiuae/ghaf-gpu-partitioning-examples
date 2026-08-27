<!--
SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Architecture

## Repository Boundary

This repository depends on Ghaf in one direction. Ghaf supplies the reusable
split and combined Orin GPU/display VM compositions plus generic device-manager,
GIVC, and shutdown mechanisms. This repository supplies replaceable runtime and
workload payloads. Jetpack-nixos supplies the hardware descriptions, patches,
role policies, and device-tree builders through Ghaf's pinned input.

```text
example target
  ├── Docker/CDI integration
  ├── burn, latency, and GEMM plugins
  ├── OCI images and scenario commands (split targets)
  └── pinned Ghaf input
        ├── split or combined GPU/display composition
        ├── generic device-manager integration
        ├── Orin BPMP, DCE, and MGBE host mechanisms
        ├── pinned jetpack-nixos hardware policy
        ├── pinned upstream microvm.nix Crosvm interface
        └── pinned partition-manager input
              ├── daemon and client
              ├── protocol and plugin ABI
              └── mock-CUDA integration tests
```

Neither Ghaf nor the manager imports this repository. Normal Ghaf targets do
not acquire the example container runtime, manager configuration, plugins, or
workloads unless a downstream target explicitly imports
`nixosModules.orin-passthrough`.

External registry images are runtime test inputs, not flake inputs and not part
of the flash closure. A profile supplies compatibility requirements and a test
program; an operator supplies an immutable image digest. This keeps registry
selection outside the trusted manager and preserves reproducible target builds.

## Runtime Data Flow

```text
native client                    managed container
gpu-partition-run                /opt/ghaf/bin/gpu-partition-run
        |                                      |
        +--------- AF_UNIX SOCK_SEQPACKET ------+
                              |
              /run/gpu-partition-manager/control.sock
                              |
                  gpu-partition-manager
                  /                   \
            slot 0 worker         slot 1 worker
            Green Context         Green Context
                  \                   /
                   passed-through GA10B
```

At startup, the manager queries the CUDA SM resource, creates two equal groups
with no remainder, creates one Green Context and persistent worker per group,
loads the Nix-selected plugins, and then opens its local socket.

The scheduler runs one job per slot. Explicit placement uses that slot's FIFO.
Automatic placement selects an idle or shorter queue, with slot 0 winning a
tie. At most 16 active and queued jobs are accepted.

## Trust And Isolation

Plugins are trusted in-process code. They execute as the dedicated
`gpu-partition` service user with GPU access. Nix selects their immutable store
paths; the socket protocol cannot upload a shared object or PTX payload.

Managed containers have no direct GPU device nodes, but this is a mediation
boundary, not a CUDA tenant boundary. The following remain outside its scope:

- memory-bandwidth and engine isolation;
- fault containment between CUDA workloads;
- real-time or forward-progress guarantees;
- protection from a process using unrestricted `gpu=all`; and
- protection from a malicious trusted plugin.

Rootful Docker membership is root-equivalent inside GPU-VM. Product
configurations must decide independently whether that access is acceptable.

The external-image harness uses `nvidia.com/gpu=all` only for its direct CUDA
test. Its managed test receives no GPU device nodes and can reach only the
manager socket and mounted client closure. It never uses privileged mode, host
networking, or Jetson Containers' broad default device mounts.

## Versioning

The manager protocol and plugin ABI are both version 1. A plugin declares its
ABI in `gpm_plugin_v1` and exposes `gpm_plugin_get_v1`. A layout or semantic
change requires a new version; do not silently reinterpret an existing field.

The `flake.lock` pins the Ghaf implementation and SDK used to build each
plugin. Update that lock as one reviewed change and rerun both target builds.
