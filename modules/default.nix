# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.ghaf.gpuPartitioningExamples;

  mkPlugin =
    {
      pluginName,
      pluginSource,
      extraCudaPackages ? [ ],
      extraCudaHeaderPackages ? [ ],
      linkLibraries ? [ ],
    }:
    pkgs.callPackage ../packages/gpu-partition-plugin.nix {
      inherit
        pluginName
        pluginSource
        extraCudaPackages
        extraCudaHeaderPackages
        linkLibraries
        ;
    };

  burnPlugin = mkPlugin {
    pluginName = "burn";
    pluginSource = ../packages/plugins/burn.c;
  };
  latencyPlugin = mkPlugin {
    pluginName = "latency";
    pluginSource = ../packages/plugins/latency.c;
  };
  gemmPlugin = mkPlugin {
    pluginName = "gemm";
    pluginSource = ../packages/plugins/gemm.c;
    extraCudaPackages = with pkgs.nvidia-jetpack.cudaPackages; [
      cuda_cudart
      libcublas
    ];
    extraCudaHeaderPackages = with pkgs.nvidia-jetpack.cudaPackages; [
      cccl
      cuda_nvcc
    ];
    linkLibraries = [ "cublas" ];
  };
in
{
  _file = ./default.nix;

  options.ghaf.gpuPartitioningExamples.metadata = lib.mkOption {
    type = lib.types.submodule {
      options = {
        target = lib.mkOption {
          type = lib.types.enum [
            "orin-agx"
            "orin-nx"
          ];
          description = "Jetson target represented by this example image.";
        };
        revisions = lib.mkOption {
          type = lib.types.submodule {
            options =
              lib.genAttrs
                [
                  "examples"
                  "ghaf"
                  "manager"
                ]
                (
                  _:
                  lib.mkOption {
                    type = lib.types.str;
                    description = "Pinned source revision recorded in runtime results.";
                  }
                );
          };
          description = "Source revisions used to build the example image.";
        };
      };
    };
    description = "Build metadata injected into GPU partitioning example results.";
  };

  config = {
    ghaf.hardware.nvidia.passthroughs.gpu_vm = {
      containerRuntime.enable = true;
      partitionManager = {
        enable = true;
        plugins = [
          burnPlugin
          latencyPlugin
          gemmPlugin
        ];
      };
    };

    # Add only example payloads to gpu-vm. GPU ownership, the manager, CDI, and
    # the security boundary remain supplied by the pinned Ghaf input.
    ghaf.hardware.definition.gpuvm.extraModules = [
      {
        _module.args.gpuPartitionExampleMetadata = cfg.metadata;
        imports = [ ./gpu-load-examples.nix ];
      }
    ];
  };
}
