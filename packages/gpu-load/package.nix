# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  stdenv,
  nvidia-jetpack,
}:
stdenv.mkDerivation {
  pname = "gpu-partition-example-load";
  version = "1.0";
  src = ./.;

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    $CC -std=c11 -Wall -Wextra -Werror -I. runner.c \
      -o gpu-partition-example-load \
      -L${nvidia-jetpack.l4t-cuda}/lib -l:libcuda.so.1 \
      -Wl,-rpath,${nvidia-jetpack.l4t-cuda}/lib
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 gpu-partition-example-load \
      $out/bin/gpu-partition-example-load
    runHook postInstall
  '';

  meta = {
    description = "Direct CUDA load example for the Ghaf gpu-vm";
    platforms = [ "aarch64-linux" ];
    mainProgram = "gpu-partition-example-load";
  };
}
