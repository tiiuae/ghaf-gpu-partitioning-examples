# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  gpuPartitionExampleMetadata,
  pkgs,
  ...
}:
let
  gpuLoad = pkgs.callPackage ../packages/gpu-load/package.nix { };

  runtimeManifest = pkgs.writeText "gpu-partition-example-runtime.json" (
    builtins.toJSON {
      schemaVersion = 1;
      inherit (gpuPartitionExampleMetadata) revisions target;
      platform = {
        l4t = pkgs.nvidia-jetpack.l4t-cuda.version;
        cuda = pkgs.nvidia-jetpack.cudaPackages.cudaMajorMinorVersion;
        computeCapability = "8.7";
        cdi = {
          version = "0.6.0";
          devices = [
            "nvidia.com/gpu=all"
            "nvidia.com/gpu=managed"
          ];
        };
        managerProtocol = 1;
        pluginAbi = 1;
      };
    }
  );

  runtimeInfo = pkgs.writeShellApplication {
    name = "gpu-partition-example-runtime-info";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.jq
      pkgs.systemd
    ];
    text = ''
      runtime_manifest=${runtimeManifest}
      ${builtins.readFile ../scenarios/runtime-info.sh}
    '';
  };

  collectResults = pkgs.writeShellApplication {
    name = "gpu-partition-example-collect-results";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.jq
      pkgs.systemd
      runtimeInfo
    ];
    text = builtins.readFile ../scenarios/collect-results.sh;
  };

  externalProfiles = pkgs.writeText "gpu-partition-external-profiles.json" (
    builtins.toJSON {
      schemaVersion = 1;
      profiles = {
        "cuda-python" = {
          executable = "python3";
          test = "cuda-python.py";
          requirements = {
            architecture = "arm64";
            l4tMajor = 36;
            l4tMinimum = "36.4";
            cudaMaximum = "12.6";
          };
        };
        pytorch = {
          executable = "python3";
          test = "pytorch.py";
          requirements = {
            architecture = "arm64";
            l4tMajor = 36;
            l4tMinimum = "36.4";
            cudaMaximum = "12.6";
          };
        };
      };
    }
  );

  externalSmoke = pkgs.writeShellApplication {
    name = "gpu-partition-example-external-smoke";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.docker
      pkgs.gnugrep
      pkgs.gnused
      pkgs.jq
      runtimeInfo
    ];
    text = ''
      profile_manifest=${externalProfiles}
      external_test_directory=${../external-tests}
      ${builtins.readFile ../scenarios/external-container-smoke.sh}
    '';
  };

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

  gemm = pkgs.writeShellApplication {
    name = "gpu-partition-example-gemm";
    runtimeInputs = [ pkgs.coreutils ];
    text = builtins.readFile ../scenarios/gemm.sh;
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
    gemm
    runtimeInfo
    collectResults
    externalSmoke
  ];

  environment.etc."ghaf-gpu-partitioning-example/runtime.json".source = runtimeManifest;
  environment.etc."ghaf-gpu-partitioning-example/external-profiles.json".source = externalProfiles;
}
