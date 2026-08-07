<!--
SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Contributing

Keep platform mechanisms in Ghaf, manager mechanisms in
`tiiuae/ghaf-gpu-partition-manager`, and examples in this repository. GPU
ownership, CDI definitions, or service hardening belong in Ghaf. Daemon,
client, protocol, plugin ABI, and mock-CUDA test changes belong in the manager
repository. Workload plugins, images, scenarios, and measurements belong here.

Use conventional commit subjects and include a Developer Certificate of Origin
sign-off. Before submitting a pull request, format the tree, run REUSE, evaluate
both target outputs, and document any hardware validation that was skipped.

Run the local PR gate from the development container:

```bash
nix fmt -- --check .
nix run --inputs-from . nixpkgs#reuse -- lint
nix eval --raw \
  .#nixosConfigurations.nvidia-jetson-orin-agx-gpu-partitioning-example.config.system.build.ghafImage.drvPath
nix eval --raw \
  .#nixosConfigurations.nvidia-jetson-orin-nx-gpu-partitioning-example.config.system.build.ghafImage.drvPath
```

Build both images before changing shared modules, plugins, or workload code:

```bash
nix build --no-link \
  .#nvidia-jetson-orin-agx-gpu-partitioning-example \
  .#nvidia-jetson-orin-nx-gpu-partitioning-example
```

Never include credentials, SSH keys, device-specific secrets, or unreviewed
binary workloads. Flashing and live hardware tests must name the exact image,
board, and recovery device used.
