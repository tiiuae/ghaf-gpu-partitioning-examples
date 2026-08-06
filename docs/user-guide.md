<!--
SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# User Guide

## Supported Targets

| Board | Image output | Flash helper output |
| --- | --- | --- |
| Orin AGX | `nvidia-jetson-orin-agx-gpu-partitioning-example` | `nvidia-jetson-orin-agx-flash-script` |
| Orin NX | `nvidia-jetson-orin-nx-gpu-partitioning-example` | `nvidia-jetson-orin-nx-flash-script` |

Both images use Ghaf's debug split topology: `gpu-vm` owns compute,
`disp-vm` owns display, and NetVM owns external networking.

## Build

Build on x86_64 and let Nix dispatch derivations to the configured remote
builders. Do not build on the Jetson.

```bash
# AGX
nix build .#nvidia-jetson-orin-agx-gpu-partitioning-example
nix build .#nvidia-jetson-orin-agx-flash-script \
  --max-jobs 8 -o result-flash

# NX
nix build .#nvidia-jetson-orin-nx-gpu-partitioning-example
nix build .#nvidia-jetson-orin-nx-flash-script \
  --max-jobs 8 -o result-flash
```

Use `nix build --dry-run` first when the Ghaf input changed substantially.

## Flash

Flashing is destructive. Put the board into Force Recovery Mode and verify
the USB identity:

```bash
lsusb | grep '0955:'
```

Known recovery products are `0955:7023` for AGX and `0955:7323` for the tested
16 GB NX. Confirm the actual board rather than selecting a target from an old
device path.

```bash
sudo -E env USER=root result-flash/bin/flash-ghaf-host -s result
```

The image and helper must come from the same locked Ghaf revision. The helper
does not embed the multi-gigabyte image; `-s result` supplies it explicitly.

## Connect

GPU-VM is reachable through NetVM in a debug image:

```bash
ssh -J ghaf@NETVM_LAN_IP ghaf@192.168.100.4
```

A reflash regenerates host keys. For an automated one-off check, isolate the
new keys with a temporary `UserKnownHostsFile`; do not disable checking in a
persistent SSH configuration.

## Check The Platform

```bash
systemctl status gpu-partition-manager
journalctl -u gpu-partition-manager -b
gpu-vm-green-context-probe
gpu-partition-run list
gpu-partition-run status
```

The probe is a platform capability diagnostic. With no option, it creates two
minimum-size 4-SM groups and can leave a remainder. Check the exact manager
geometry separately:

```bash
# AGX: require two 8-SM groups and no remainder in the probe output.
gpu-vm-green-context-probe --min-sm-count 8
gpu-partition-run status

# NX: require two 4-SM groups and no remainder in the probe output.
gpu-vm-green-context-probe --min-sm-count 4
gpu-partition-run status
```

Expected AGX manager geometry is 16 total SMs and two 8-SM slots. An 8-SM NX
resource should produce two 4-SM slots. The runtime CUDA query is authoritative.

## Run Examples

```bash
# Direct CDI plus managed CDI and device-node exclusion.
gpu-partition-example-smoke

# Two concurrent managed burns, 30 seconds each.
gpu-partition-example-endurance 30

# Default endurance duration is 30 minutes.
gpu-partition-example-endurance

# Verify same-slot FIFO release and Ctrl-C cancellation.
gpu-partition-example-queue-cancel

# Baseline, managed co-load, and unmanaged direct-GPU co-load.
# Arguments are latency iterations and burn seconds.
gpu-partition-example-interference 10000 30
```

The lower-level client remains available:

```bash
gpu-partition-run --slot 0 burn --seconds 60
gpu-partition-run --slot 1 latency --iterations 10000
gpu-partition-run status
gpu-partition-run cancel JOB_ID
```

`Ctrl+C` asks the manager to cancel the active job. The client exits 130 after
successful cancellation.

## Container Modes

`nvidia.com/gpu=all` injects the GPU device nodes and permits direct CUDA:

```bash
docker run --rm --device nvidia.com/gpu=all IMAGE
```

`nvidia.com/gpu=managed` injects only the manager client and socket. It does
not inject `/dev/nvgpu`, `/dev/nvhost-*`, `/dev/nvmap`, the DRM render node,
or the host1x fence:

```bash
docker run --rm --device nvidia.com/gpu=managed IMAGE \
  /opt/ghaf/bin/gpu-partition-run burn --seconds 60
```

The managed workload executes inside the trusted manager process, not in the
container. An unrestricted `gpu=all` process can bypass the manager and
interfere with both managed slots.

## Troubleshooting

- Manager exit status 78 means unsupported or inconsistent CUDA resource
  geometry. Inspect its first boot journal entry.
- Repeated manager restarts require checking the first CUDA plugin failure and
  `dmesg` for nvgpu faults.
- A managed container with GPU nodes is a failed security contract. Stop the
  test and inspect `/etc/cdi/nvidia.json`.
- A missing manager socket usually means the service never became ready or
  the managed CDI device was not enabled.
- Timing differences alone do not prove concurrency or isolation.
