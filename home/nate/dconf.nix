{ lib, ... }: {
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      gtk-theme = lib.mkForce "MonoThemeDark";
      icon-theme = lib.mkForce "Mono";
      cursor-theme = "Adwaita";
      color-scheme = "prefer-dark";
      font-name = "JetBrains Mono 11";
    };
  };
}
