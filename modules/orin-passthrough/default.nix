# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{ ... }:
{
  _file = ./default.nix;

  imports = [
    ./vm-composition.nix
    ./gpu-vm.nix
  ];
}
