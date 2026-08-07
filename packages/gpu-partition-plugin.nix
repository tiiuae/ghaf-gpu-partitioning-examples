# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  stdenv,
  nvidia-jetpack,
  gpu-vm-partition-manager-sdk,
  pluginName,
  pluginSource,
  extraCudaPackages ? [ ],
  extraCudaHeaderPackages ? [ ],
  linkLibraries ? [ ],
}:
let
  includeFlags = lib.concatMapStringsSep " " (package: "-I${lib.getInclude package}/include") (
    extraCudaPackages ++ extraCudaHeaderPackages
  );
  libraryFlags = lib.concatMapStringsSep " " (
    package: "-L${lib.getLib package}/lib"
  ) extraCudaPackages;
  linkFlags = lib.concatMapStringsSep " " (library: "-l${library}") linkLibraries;
  extraRpath = lib.optionalString (extraCudaPackages != [ ]) (
    "-Wl,-rpath,${lib.makeLibraryPath extraCudaPackages}"
  );
in
assert gpu-vm-partition-manager-sdk.pluginAbiVersion == 1;
stdenv.mkDerivation {
  pname = "gpu-partition-example-plugin-${pluginName}";
  version = "1.0";

  dontUnpack = true;
  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    cp ${pluginSource} plugin.c
    cp ${./gpu-load/vadd.ptx} vadd.ptx
    $CC -std=c11 -Wall -Wextra -Werror -fPIC -shared -I. \
      -I${gpu-vm-partition-manager-sdk}/include/ghaf/gpu-partition-manager \
      -I${nvidia-jetpack.cudaPackages.cuda_cudart}/include \
      ${includeFlags} \
      plugin.c -o plugin.so \
      -L${nvidia-jetpack.l4t-cuda}/lib -l:libcuda.so.1 \
      ${libraryFlags} ${linkFlags} ${extraRpath} \
      -Wl,-rpath,${nvidia-jetpack.l4t-cuda}/lib
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 plugin.so $out/lib/gpu-partition-manager/plugin.so
    runHook postInstall
  '';

  passthru = {
    gpuPartitionPluginName = pluginName;
    requiredPluginAbiVersion = gpu-vm-partition-manager-sdk.pluginAbiVersion;
  };

  meta = {
    description = "${pluginName} example for the Ghaf GPU partition manager";
    platforms = [ "aarch64-linux" ];
  };
}
