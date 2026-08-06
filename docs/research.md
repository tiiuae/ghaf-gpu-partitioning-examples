<!--
SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Research Guide

## Required Test Matrix

Run each case on AGX and NX using the same Ghaf lock revision:

| Case | Primary observation |
| --- | --- |
| Capability probe | Total SMs, two groups, remainder, readback |
| Direct CDI smoke | Device injection and real kernel completion |
| Managed CDI smoke | No GPU nodes, socket access, managed completion |
| Two-slot burn | Both slots complete under overlap |
| Same-slot queue | FIFO job starts after predecessor exits |
| Cancellation | Active job exits 130 and queued work proceeds |
| 30-minute endurance | Iterations, validation, faults, restarts |
| Latency baseline | p50, p95, p99, maximum |
| Managed co-load | Latency while the opposite slot burns |
| Unmanaged co-load | Latency while direct CUDA bypasses the manager |

Record the exact image store path, Ghaf revision, board model, manager journal,
GPU-VM restart count, manager restart count, and relevant `dmesg` lines.

## Interpretation

An overlapping wall-clock interval proves that clients were active together;
it does not prove simultaneous SM execution. Lower latency in one sample does
not establish isolation or an improvement. Repeat experiments, report sample
counts, and retain raw reports before making comparative claims.

Do not convert exploratory numbers into CI thresholds until variance is known
for both boards, thermal states, power modes, and unmanaged background load.

## Follow-Up Topics

- Configurable partition geometry beyond two equal slots
- Scheduling fairness and per-client quotas
- Structured JSON result output
- Thermal and power-mode sensitivity
- Memory-bandwidth and copy-engine interference
- Manager recovery after plugin CUDA failure
- Long-duration queue, disconnect, and cancellation races
- Live NX parity with the AGX validation suite
