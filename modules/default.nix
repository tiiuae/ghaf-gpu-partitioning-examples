# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ pkgs, ... }:
let
  mkPlugin =
    pluginName: pluginSource:
    pkgs.callPackage ../packages/gpu-partition-plugin.nix {
      inherit pluginName pluginSource;
    };

  burnPlugin = mkPlugin "burn" ../packages/plugins/burn.c;
  latencyPlugin = mkPlugin "latency" ../packages/plugins/latency.c;
in
{
  _file = ./default.nix;

  ghaf.hardware.nvidia.passthroughs.gpu_vm = {
    containerRuntime.enable = true;
    partitionManager = {
      enable = true;
      plugins = [
        burnPlugin
        latencyPlugin
      ];
    };
  };

  # Add only example payloads to gpu-vm. GPU ownership, the manager, CDI, and
  # the security boundary remain supplied by the pinned Ghaf input.
  ghaf.hardware.definition.gpuvm.extraModules = [ ./gpu-load-examples.nix ];
}
