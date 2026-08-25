# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  ...
}:
let
  configuredGuiVmm = config.ghaf.virtualization.vmConfig.sysvms.guivm.vmm or null;
  guiVmm =
    if configuredGuiVmm == null then
      config.ghaf.virtualization.vmConfig.defaultSysVmVmm
    else
      configuredGuiVmm;
in
{
  _file = ./default.nix;

  imports = [
    ./vm-composition.nix
    ./gpu-vm.nix
    ./disp-vm.nix
    ./gui-vm.nix
    ./ownership-assertions.nix
  ];

  config = {
    ghaf.hardware.passthrough.usb.guivmDeny =
      lib.mkIf config.ghaf.hardware.nvidia.passthroughs.gui_vm.enable
        (
          lib.optional (guiVmm != "crosvm") {
            vendorId = "046d";
            productId = "c52b";
            description = "Logitech Unifying Receiver: evdev-only with the QEMU rollback";
          }
        );
  };
}
