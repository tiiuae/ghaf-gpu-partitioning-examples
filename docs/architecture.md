<!--
SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Architecture

## Repository Boundary

This repository depends on Ghaf in one direction. Ghaf supplies hardware and
security-sensitive mechanisms; this repository supplies replaceable example
payloads.

```text
example target
  ├── burn and latency plugins
  ├── OCI images and scenario commands
  └── pinned Ghaf input
        ├── AGX/NX passthrough and BPMP policy
        ├── gpu-vm and disp-vm topology
        ├── Docker/CDI integration
        └── pinned partition-manager input
              ├── daemon and client
              ├── protocol and plugin ABI
              └── mock-CUDA integration tests
```

Neither Ghaf nor the manager imports this repository. Updating the examples
therefore cannot change a normal Ghaf image unless a downstream target
explicitly imports the module.

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

## Versioning

The manager protocol and plugin ABI are both version 1. A plugin declares its
ABI in `gpm_plugin_v1` and exposes `gpm_plugin_get_v1`. A layout or semantic
change requires a new version; do not silently reinterpret an existing field.

The `flake.lock` pins the Ghaf implementation and SDK used to build each
plugin. Update that lock as one reviewed change and rerun both target builds.
