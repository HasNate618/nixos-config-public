{ config, lib, pkgs, ... }:
let
  # Mono icon theme — monochrome Adwaita-style icons from
  # https://github.com/witalihirsch/Mono-icon-theme
  # Modified to inherit from Papirus-Dark for app icon fallback.
  mono-icon-theme = pkgs.stdenv.mkDerivation {
    pname = "mono-icon-theme";
    version = "0.1";
    src = pkgs.fetchzip {
      url = "https://github.com/witalihirsch/Mono-icon-theme/releases/download/0.1/MonoIcons.zip";
      hash = "sha256-40znIZAVPkZyJ7rG0tcecyBD45B9sAqQAJEDm7fUFgs=";
    };
    installPhase = ''
      mkdir -p $out/share/icons/Mono
      cp -r . $out/share/icons/Mono/
    '';
    postFixup = ''
      # Override Inherits to fall back to Papirus-Dark for app icons
      # Mono only has system/place icons — no app icons at all
      sed -i 's/^Inherits=hicolor$/Inherits=Papirus-Dark,hicolor/' $out/share/icons/Mono/index.theme
    '';
    dontCheckForBrokenSymlinks = true;
    meta.description = "Mono icon theme — monochrome Adwaita-style icons with Papirus-Dark app fallback";
  };
in {
  # GTK theming
  gtk = {
    enable = true;

    # Dark GTK theme
    theme = {
      name = "MonoThemeDark";
    };

    # Dark icon theme — Mono for system icons, Papirus-Dark as fallback for apps
    iconTheme = {
      name = "Mono";
      package = pkgs.symlinkJoin {
        name = "icon-themes";
        paths = [ mono-icon-theme pkgs.papirus-icon-theme ];
      };
    };

    # Font
    font = {
      name = "JetBrains Mono";
      package = pkgs.jetbrains-mono;
      size = 11;
    };

    # Force dark preference in GTK3/4
    gtk3.extraConfig = {
      gtk-application-prefer-dark-theme = 1;
    };
    gtk4.extraConfig = {
      gtk-application-prefer-dark-theme = 1;
    };
  };

  # Qt theming — match GTK dark theme
  qt = {
    enable = true;
    platformTheme = {
      name = "gtk3";
    };
    style = {
      name = "adwaita";
      package = pkgs.adwaita-qt;
    };
  };
}
