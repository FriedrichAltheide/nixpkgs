# This module adds the calamares installer to the basic graphical NixOS
# installation CD.

{ pkgs, ... }:
let
  calamares-nixos-autostart = pkgs.makeAutostartItem {
    name = "io.calamares.calamares";
    package = pkgs.calamares-nixos;
  };
in
{
  imports = [ ./installation-cd-graphical-base.nix ];

  programs.calamares-nixos-extensions = {
    enable = true;
    autoStart = true;
  };

  # Support choosing from any locale
  i18n.supportedLocales = [ "all" ];
}
