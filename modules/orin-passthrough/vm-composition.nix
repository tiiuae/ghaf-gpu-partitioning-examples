# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  inputs,
  lib,
  ...
}:
let
  mkBase =
    vmName: module:
    lib.nixosSystem {
      modules = [
        inputs.self.nixosModules.microvm-nix
        module
        {
          nixpkgs = {
            hostPlatform.system = "aarch64-linux";
            inherit (config.nixpkgs) config overlays;
          };
        }
      ];
      specialArgs = lib.ghaf.vm.mkSpecialArgs {
        inherit lib inputs;
        globalConfig = config.ghaf.global-config;
        hostConfig = lib.ghaf.vm.mkHostConfig { inherit config vmName; };
      };
    };
  mkGuest =
    name: base:
    base.extendModules {
      modules = lib.ghaf.vm.applyVmConfig {
        inherit config;
        vmName = name;
      };
    };
in
{
  _file = ./vm-composition.nix;

  imports = [
    ./gpuvm.nix
    ./dispvm.nix
  ];

  options.ghaf.hardware.definition = {
    gpuvm.extraModules = lib.mkOption {
      type = lib.types.listOf lib.types.unspecified;
      default = [ ];
      description = "Hardware modules added to the GPU example VM.";
    };
    dispvm.extraModules = lib.mkOption {
      type = lib.types.listOf lib.types.unspecified;
      default = [ ];
      description = "Hardware modules added to the display example VM.";
    };
  };

  config.ghaf.virtualization.microvm = {
    gpuvm.evaluatedConfig = mkGuest "gpuvm" (mkBase "gpu-vm" ./gpuvm-base.nix);
    dispvm.evaluatedConfig = mkGuest "dispvm" (mkBase "disp-vm" ./dispvm-base.nix);
  };
}
