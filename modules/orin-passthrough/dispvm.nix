# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Disp VM Configuration Module
#
# globalConfig pattern: global settings via globalConfig specialArg,
# host-specific (networking.hosts) via hostConfig. Self-contained; all
# platforms use the evaluatedConfig pattern with a profile's dispvmBase.
#
# This repository supplies the base and evaluated configuration. The module is
# inert unless a passthrough example enables it.
{
  config,
  lib,
  inputs,
  ...
}:
let
  vmName = "disp-vm";

  cfg = config.ghaf.virtualization.microvm.dispvm;
in
{
  _file = ./dispvm.nix;

  options.ghaf.virtualization.microvm.dispvm = {
    enable = lib.mkEnableOption "DispVM";

    evaluatedConfig = lib.mkOption {
      type = lib.types.nullOr lib.types.unspecified;
      default = null;
      description = "Pre-evaluated NixOS configuration for the display VM.";
    };

    extraNetworking = lib.mkOption {
      type = lib.types.networking;
      description = "Extra Networking option";
      default = { };
    };
  };

  config = lib.mkMerge [
    {
      ghaf.virtualization.microvm.sysvm.vms.dispvm = {
        inherit vmName;
        inherit (cfg) enable evaluatedConfig extraNetworking;
      };
    }
    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = cfg.evaluatedConfig != null;
          message = ''
            ghaf.virtualization.microvm.dispvm.evaluatedConfig must be set.
            Import the Orin passthrough example composition that provides it.
          '';
        }
      ];

      microvm.vms."${vmName}" = {
        autostart = !config.ghaf.microvm-boot.enable;
        restartIfChanged = false;
        inherit (inputs) nixpkgs;
        inherit (cfg) evaluatedConfig;
      };
    })
  ];
}
