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

      mkExample =
        {
          name,
          upstreamName,
        }:
        let
          hostConfiguration = ghaf.nixosConfigurations.${upstreamName}.extendModules {
            modules = [ self.nixosModules.default ];
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
        })
        (mkExample {
          name = "nvidia-jetson-orin-nx-gpu-partitioning-example";
          upstreamName = "nvidia-jetson-orin-nx-debug-from-x86_64";
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

      formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixfmt-rfc-style;
    };
}
