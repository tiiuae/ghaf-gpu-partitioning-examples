# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  ghaf,
  runCommand,
}:
let
  lib = ghaf.lib;
  config = name: self.nixosConfigurations.${name}.config;
  agx = config "nvidia-jetson-orin-agx-combined-example";
  nx = config "nvidia-jetson-orin-nx-combined-example";
  splitAgx = config "nvidia-jetson-orin-agx-gpu-partitioning-example";
  splitNx = config "nvidia-jetson-orin-nx-gpu-partitioning-example";
  nxQemu =
    (self.nixosConfigurations."nvidia-jetson-orin-nx-combined-example".extendModules {
      modules = [
        { ghaf.virtualization.vmConfig.sysvms.guivm.vmm = lib.mkForce "qemu"; }
      ];
    }).config;

  vm = host: name: lib.ghaf.vm.getConfig host.microvm.vms.${name};
  uses = host: vmm: lib.all (entry: entry.type == vmm) host.ghaf.hardware.passthrough.vhotplug.vms;
  dceHost = host: host.hardware.nvidia-jetpack.virtualization.dceHost.enable;
  hasArg = needle: guest: lib.any (lib.hasInfix needle) guest.microvm.crosvm.extraArgs;
  hasDevice = needle: guest: lib.any (device: lib.hasInfix needle device.path) guest.microvm.devices;
  bpmpConsumers = host: host.hardware.nvidia-jetpack.virtualization.bpmpHost.consumers;
  hasReceiverDeny =
    host:
    lib.any (
      rule: lib.any (device: device.vendorId == "046d" && device.productId == "c52b") rule.deny
    ) host.ghaf.hardware.passthrough.usb.guivmRules;
  hasShutdown =
    host: name:
    host.systemd.services ? "ghaf-crosvm-shutdown-${name}"
    && host.systemd.services."microvm@${name}".serviceConfig.TimeoutStopSec == "35"
    &&
      lib.elem "CAP_DAC_OVERRIDE"
        host.systemd.services."ghaf-crosvm-shutdown-${name}".serviceConfig.CapabilityBoundingSet;
  shutdownScript =
    host: name: host.systemd.services."ghaf-crosvm-shutdown-${name}".serviceConfig.ExecStop;

  agxGui = vm agx "gui-vm";
  nxGui = vm nx "gui-vm";
  splitAgxGpu = vm splitAgx "gpu-vm";
  splitAgxDisp = vm splitAgx "disp-vm";
  splitNxNet = vm splitNx "net-vm";
  nxQemuGui = vm nxQemu "gui-vm";
  nxApp = vm nx "chromium-vm";
  memoryBase =
    self.nixosConfigurations."nvidia-jetson-orin-agx-combined-example".pkgs.nvidia-jetpack.orinVirtualizationSupport.passthrough.crosvmLayout.memoryBase;
  managedNames = host: map (entry: entry.name) host.ghaf.hardware.passthrough.vhotplug.vms;
  assertions = [
    {
      name = "all four debug targets select Crosvm and ghaf-device-manager";
      ok =
        lib.all
          (
            host:
            uses host "crosvm"
            && host.ghaf.hardware.passthrough.deviceManager.backend == "ghaf-device-manager"
            && host.systemd.services."ghaf-device-manager".enable
            && !(host.systemd.services.vhotplug.enable or false)
          )
          [
            agx
            nx
            splitAgx
            splitNx
          ];
    }
    {
      name = "release targets retain QEMU defaults";
      ok =
        ghaf.nixosConfigurations."nvidia-jetson-orin-agx-release".config.ghaf.virtualization.vmConfig.defaultSysVmVmm
        == "qemu"
        &&
          ghaf.nixosConfigurations."nvidia-jetson-orin-agx-release".config.ghaf.virtualization.vmConfig.defaultAppVmVmm
          == "qemu";
    }
    {
      name = "GPU, display, and combined guests receive only their payload arguments";
      ok =
        splitAgxGpu.microvm.crosvm.memoryBase == memoryBase
        && splitAgxDisp.microvm.crosvm.memoryBase == memoryBase
        && nxGui.microvm.crosvm.memoryBase == memoryBase
        && hasDevice "17000000.gpu" splitAgxGpu
        && !(hasDevice "13830000.disp_caps_pt" splitAgxGpu)
        && hasDevice "13830000.disp_caps_pt" splitAgxDisp
        && !(hasDevice "17000000.gpu" splitAgxDisp)
        && hasDevice "17000000.gpu" nxGui
        && hasDevice "13830000.disp_caps_pt" nxGui;
    }
    {
      name = "BPMP policies and device paths are isolated per VM";
      ok =
        builtins.attrNames (bpmpConsumers splitAgx) == [
          "disp-vm"
          "gpu-vm"
          "net-vm"
        ]
        && builtins.attrNames (bpmpConsumers nx) == [ "gui-vm" ]
        && hasArg "/dev/bpmp-host-gpu-vm" splitAgxGpu
        && hasArg "/dev/bpmp-host-disp-vm" splitAgxDisp
        && hasArg "/dev/bpmp-host-gui-vm" agxGui
        && agx.systemd.services."microvm@gui-vm".environment.GHAF_BPMP_HOST == "/dev/bpmp-host-gui-vm";
    }
    {
      name = "DCE host support is owned by the downstream examples";
      ok =
        lib.all dceHost [
          agx
          nx
          splitAgx
          splitNx
        ]
        && !dceHost ghaf.nixosConfigurations."nvidia-jetson-orin-agx-debug-from-x86_64".config
        && !dceHost ghaf.nixosConfigurations."nvidia-jetson-orin-nx-debug-from-x86_64".config;
    }
    {
      name = "NX PCI Ethernet uses the Crosvm-specific guest address";
      ok =
        lib.any (device: device.bus == "pci" && device.path == "0008:01:00.0") splitNxNet.microvm.devices
        && lib.any (
          device:
          device.bus == "pci"
          && device.path == "0008:01:00.0"
          && device.crosvm.guestAddress == "00:1f.0"
          && device.crosvm.iommu == "off"
        ) splitNxNet.microvm.devices;
    }
    {
      name = "bounded guest-owned shutdown covers system and application VMs";
      ok =
        lib.all (hasShutdown nx) (managedNames nx)
        && agxGui.systemd.services ? ghaf-crosvm-poweroff
        && splitAgxGpu.systemd.services ? givc-gpu-vm
        && splitAgxDisp.systemd.services ? givc-disp-vm
        && lib.elem "ghaf-crosvm-poweroff.service" agxGui.givc.sysvm.capabilities.services
        && nxApp.systemd.user.services ? ghaf-crosvm-poweroff
        && lib.elem "ghaf-crosvm-poweroff.service" nxApp.ghaf.givc.appvm.services;
    }
    {
      name = "MGBE and DCE shutdown hooks are present";
      ok =
        (vm agx "net-vm").systemd.services ? ghaf-mgbe0-poweroff
        && agxGui.systemd.services ? dce-rm-deinit
        && splitAgxDisp.systemd.services ? dce-rm-deinit;
    }
    {
      name = "QEMU GUI fallback restores vhotplug and receiver denial";
      ok =
        nxQemuGui.microvm.hypervisor == "qemu"
        && nxQemu.ghaf.hardware.passthrough.deviceManager.backend == "vhotplug"
        && nxQemu.systemd.services.vhotplug.enable
        && hasReceiverDeny nxQemu
        && !hasReceiverDeny nx;
    }
  ];
  failed = map (assertion: assertion.name) (lib.filter (assertion: !assertion.ok) assertions);
in
assert lib.assertMsg (
  failed == [ ]
) "Orin Crosvm target checks failed: ${lib.concatStringsSep "; " failed}";
runCommand "orin-crosvm-targets" { } ''
  grep -Fq -- '--no-syslog stop' ${shutdownScript splitAgx "disp-vm"}
  touch "$out"
''
