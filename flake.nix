# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  description = "Reproducible GPU partitioning examples for Ghaf on NVIDIA Orin";

  nixConfig = {
    extra-substituters = [ "https://ghaf-dev.cachix.org" ];
    extra-trusted-public-keys = [
      "ghaf-dev.cachix.org-1:S3M8x3no8LFQPBfHw1jl6nmP8A7cVWKntoMKN3IsEQY="
    ];
    allow-import-from-derivation = false;
  };

  inputs = {
    # Use the authoritative PR ref until Ghaf PR 2133 merges. flake.lock pins
    # its exact revision; switch this URL to github:tiiuae/ghaf after merge.
    ghaf.url = "git+https://github.com/tiiuae/ghaf.git?ref=refs/pull/2133/head";
    nixpkgs.follows = "ghaf/nixpkgs";
  };

  outputs =
    {
      self,
      ghaf,
      nixpkgs,
    }:
    let
      lib = ghaf.lib;

      inputRevision = input: input.rev or input.dirtyRev or "unknown";
      revisions = {
        examples = inputRevision self;
        ghaf = inputRevision ghaf;
        manager = inputRevision ghaf.inputs."gpu-partition-manager";
      };

      mkExample =
        {
          name,
          upstreamName,
          target,
          modules ? [ ],
          workloads ? false,
        }:
        let
          hostConfiguration = ghaf.nixosConfigurations.${upstreamName}.extendModules {
            modules = [
              self.nixosModules.orin-passthrough
            ]
            ++ lib.optional workloads self.nixosModules.default
            ++ modules
            ++ lib.optional workloads {
              ghaf.gpuPartitioningExamples.metadata = {
                inherit revisions target;
              };
            };
          };
        in
        {
          inherit name hostConfiguration;
          package = hostConfiguration.config.system.build.ghafImage;
        };

      examples = [
        (mkExample {
          name = "nvidia-jetson-orin-agx-gpu-partitioning-example";
          upstreamName = "nvidia-jetson-orin-agx-debug-from-x86_64";
          target = "orin-agx";
          workloads = true;
          modules = [
            {
              ghaf.hardware.nvidia.passthroughs = {
                gpu_vm.enable = true;
                disp_vm.enable = true;
              };
            }
          ];
        })
        (mkExample {
          name = "nvidia-jetson-orin-nx-gpu-partitioning-example";
          upstreamName = "nvidia-jetson-orin-nx-debug-from-x86_64";
          target = "orin-nx";
          workloads = true;
          modules = [
            {
              ghaf.hardware.nvidia.passthroughs = {
                gpu_vm.enable = true;
                disp_vm.enable = true;
              };
              ghaf.virtualization.vmConfig.sysvms = {
                gpuvm.mem = 2048;
                dispvm.mem = 1536;
              };
            }
          ];
        })
        (mkExample {
          name = "nvidia-jetson-orin-agx-combined-example";
          upstreamName = "nvidia-jetson-orin-agx-debug-from-x86_64";
          target = "orin-agx";
          modules = [
            { ghaf.hardware.nvidia.passthroughs.gui_vm.enable = true; }
          ];
        })
        (mkExample {
          name = "nvidia-jetson-orin-nx-combined-example";
          upstreamName = "nvidia-jetson-orin-nx-debug-from-x86_64";
          target = "orin-nx";
          modules = [
            {
              ghaf.hardware.nvidia = {
                passthroughs.gui_vm.enable = true;
                orin.flashScriptOverrides.appPartitionSizeBytes = 34359738368;
              };
              ghaf.virtualization.vmConfig.sysvms.guivm.mem = 4096;
            }
          ];
        })
      ];
    in
    {
      lib = ghaf.lib;

      nixosModules = {
        default = ./modules/default.nix;
        gpu-load-examples = ./modules/gpu-load-examples.nix;
        orin-passthrough = ./modules/orin-passthrough;
      };

      nixosConfigurations = builtins.listToAttrs (
        map (example: lib.nameValuePair example.name example.hostConfiguration) examples
      );

      packages.x86_64-linux =
        builtins.listToAttrs (map (example: lib.nameValuePair example.name example.package) examples)
        // {
          default = self.packages.x86_64-linux.nvidia-jetson-orin-agx-gpu-partitioning-example;
          nvidia-jetson-orin-agx-flash-script =
            ghaf.packages.x86_64-linux.nvidia-jetson-orin-agx-debug-from-x86_64-flash-script;
          nvidia-jetson-orin-nx-flash-script =
            ghaf.packages.x86_64-linux.nvidia-jetson-orin-nx-debug-from-x86_64-flash-script;
        };

      checks.x86_64-linux =
        let
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
        in
        {
          external-container-smoke =
            let
              testSource = pkgs.runCommand "gpu-partition-external-container-smoke-source" { } ''
                mkdir -p $out/scenarios $out/external-tests
                cp ${./scenarios/external-container-smoke.sh} $out/scenarios/external-container-smoke.sh
                cp ${./external-tests/cuda-python.py} $out/external-tests/cuda-python.py
                cp ${./external-tests/pytorch.py} $out/external-tests/pytorch.py
              '';
            in
            pkgs.runCommand "gpu-partition-external-container-smoke-test"
              {
                nativeBuildInputs = [
                  pkgs.bash
                  pkgs.coreutils
                  pkgs.jq
                ];
              }
              ''
                bash ${./tests/external-container-smoke.sh} ${testSource}
                touch $out
              '';

          orin-crosvm-targets = pkgs.callPackage ./tests/orin-crosvm-targets.nix {
            inherit self ghaf;
          };
        };

      devShells.x86_64-linux.default =
        let
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
        in
        pkgs.mkShellNoCC {
          packages = [
            pkgs.clang-tools
            pkgs.python3
            pkgs.reuse
            pkgs.shellcheck
          ];
        };

      formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixfmt;
    };
}
