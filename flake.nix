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
    # Use the authoritative PR ref until Ghaf PR 2095 merges. flake.lock pins
    # its exact revision; switch this URL to github:tiiuae/ghaf after merge.
    ghaf.url = "git+https://github.com/tiiuae/ghaf.git?ref=refs/pull/2095/head";
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
        }:
        let
          hostConfiguration = ghaf.nixosConfigurations.${upstreamName}.extendModules {
            modules = [
              self.nixosModules.default
              {
                ghaf.gpuPartitioningExamples.metadata = {
                  inherit revisions target;
                };
              }
            ];
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
        })
        (mkExample {
          name = "nvidia-jetson-orin-nx-gpu-partitioning-example";
          upstreamName = "nvidia-jetson-orin-nx-debug-from-x86_64";
          target = "orin-nx";
        })
      ];
    in
    {
      lib = ghaf.lib;

      nixosModules = {
        default = ./modules/default.nix;
        gpu-load-examples = ./modules/gpu-load-examples.nix;
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

      checks.x86_64-linux.external-container-smoke =
        let
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
          testSource = pkgs.runCommand "gpu-partition-external-container-smoke-source" { } ''
            mkdir -p $out/scenarios $out/external-tests
            cp ${./scenarios/external-container-smoke.sh} $out/scenarios/external-container-smoke.sh
            cp ${./external-tests/cuda-python.py} $out/external-tests/cuda-python.py
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
