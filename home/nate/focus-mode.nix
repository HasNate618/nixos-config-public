{ lib, ... }:
# Focus-mode colour schemes (sources: ./focus-schemes/*.conf).
#
# Deployed read-only to ~/.config/focus-mode/schemes/; the ACTIVE scheme is
# a runtime choice (~/.config/focus-mode/active, default kanagawa-dragon)
# switchable live with `focus-scheme <name>` — no rebuild needed. Extra
# .conf files dropped into the deployed directory also survive: HM only
# manages the files it declares.
#
# The active scheme drives every focused surface via focus-apply-scheme:
# the solid wallpaper, the quickshell palette, foot terminals (alpha forced
# to 1.0 via OSC 11), and the hyprlock screen colours.
{
  xdg.configFile = lib.listToAttrs (map (name: {
    name = "focus-mode/schemes/${name}";
    value = { source = ./focus-schemes/${name}; force = true; };
  }) (builtins.attrNames (builtins.readDir ./focus-schemes)));
}
