<!--
SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Plugin Development

## Contract

A configured plugin package must:

1. Set `passthru.gpuPartitionPluginName`.
2. Set `passthru.requiredPluginAbiVersion` to the SDK ABI version.
3. Install one shared object at
   `lib/gpu-partition-manager/plugin.so`.
4. Export `gpm_plugin_get_v1`.
5. Return a `gpm_plugin_v1` whose name matches the Nix package metadata.

The public header is owned by `tiiuae/ghaf-gpu-partition-manager` and
re-exported in Ghaf's `gpu-vm-partition-manager-sdk` package under
`include/ghaf/gpu-partition-manager/plugin.h`.

```c
struct gpm_plugin_v1 {
  uint32_t abi_version;
  const char *name;
  const char *summary;
  int (*run)(CUstream stream, unsigned int sm_count,
             int argc, const char *const *argv,
             const volatile sig_atomic_t *cancelled,
             char *report, size_t report_size);
};
```

## Workload Rules

- Launch every kernel and asynchronous operation on the supplied stream.
- Never create another primary context or switch CUDA devices.
- Treat `sm_count` as reported placement, not a performance guarantee.
- Validate the full argument vector and place bounds on durations and counts.
- Check `cancelled` between bounded pieces of work.
- Return a short, stable, machine-readable report.
- Release allocations and modules on every exit path.
- Return `GPM_PLUGIN_CUDA_ERROR` for CUDA failures. The manager treats such a
  failure as fatal and reconstructs its contexts through systemd restart.

## Add A Plugin

Add the source under `packages/plugins/`, instantiate it with
`packages/gpu-partition-plugin.nix`, and append the resulting derivation to
`partitionManager.plugins` in `modules/default.nix`.

The example builder links against the CUDA driver and the exact SDK from the
pinned Ghaf package. It deliberately keeps PTX and other workload assets in
this repository.

The `gemm` plugin is the example for a CUDA library layered on the driver API.
It links the pinned JetPack cuBLAS package, binds its handle to the stream
supplied by the manager, bounds matrix memory and duration, checks cancellation
between synchronized operations, and validates deterministic output. Additional
library-based plugins must preserve those properties and must not create their
own CUDA context.

## Validate A Change

Run formatting and licensing checks, then evaluate both target systems:

```bash
nix fmt -- --check .
nix develop --command reuse lint
nix eval --raw \
  .#nixosConfigurations.nvidia-jetson-orin-agx-gpu-partitioning-example.config.system.build.ghafImage.drvPath
nix eval --raw \
  .#nixosConfigurations.nvidia-jetson-orin-nx-gpu-partitioning-example.config.system.build.ghafImage.drvPath
nix build .#nvidia-jetson-orin-agx-gpu-partitioning-example --dry-run
nix build .#nvidia-jetson-orin-nx-gpu-partitioning-example --dry-run
```

On hardware, run the smoke, queue/cancel, and short endurance scenarios before
a 30-minute endurance run. Record manager and GPU-VM restart counts plus nvgpu
faults; a successful client alone is not sufficient evidence.
