# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ pkgs, ... }:
let
  gpuLoad = pkgs.callPackage ../packages/gpu-load/package.nix { };

  directImage = pkgs.dockerTools.buildImage {
    name = "ghaf-gpu-direct-example";
    tag = "latest";
    copyToRoot = gpuLoad;
    config.Cmd = [
      "/bin/gpu-partition-example-load"
      "5"
    ];
  };

  managedImage = pkgs.dockerTools.buildImage {
    name = "ghaf-gpu-managed-example";
    tag = "latest";
    copyToRoot = pkgs.buildEnv {
      name = "ghaf-gpu-managed-example-root";
      paths = [
        pkgs.busybox
        gpuLoad
      ];
      pathsToLink = [ "/bin" ];
    };
    config.Cmd = [
      "/bin/sh"
      "-c"
      ''
        test ! -e /dev/nvgpu
        test ! -e /dev/nvhost-gpu
        if /bin/gpu-partition-example-load 1; then
          echo MANAGED_GPU_NODE_LEAK
          exit 1
        fi
        /opt/ghaf/bin/gpu-partition-run status
        /opt/ghaf/bin/gpu-partition-run burn --seconds 5
        echo MANAGED_CONTAINER_GPU_OK
      ''
    ];
  };

  smoke = pkgs.writeShellApplication {
    name = "gpu-partition-example-smoke";
    runtimeInputs = [
      pkgs.docker
      pkgs.gnugrep
    ];
    text = ''
      direct_image=${directImage}
      managed_image=${managedImage}
      ${builtins.readFile ../scenarios/smoke.sh}
    '';
  };

  endurance = pkgs.writeShellApplication {
    name = "gpu-partition-example-endurance";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
    ];
    text = builtins.readFile ../scenarios/endurance.sh;
  };

  interference = pkgs.writeShellApplication {
    name = "gpu-partition-example-interference";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      gpuLoad
    ];
    text = builtins.readFile ../scenarios/interference.sh;
  };

  queueCancel = pkgs.writeShellApplication {
    name = "gpu-partition-example-queue-cancel";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
    ];
    text = builtins.readFile ../scenarios/queue-cancel.sh;
  };
in
{
  _file = ./gpu-load-examples.nix;

  environment.systemPackages = [
    gpuLoad
    smoke
    endurance
    interference
    queueCancel
  ];
}
