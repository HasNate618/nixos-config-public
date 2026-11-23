{ config, lib, ... }:

let
  opacity = config.theme.opacity;
  # Bar keeps a 1/10 scale relative to app opacity.
  barOpacity = opacity / 10;
  # Zen (and any #RRGGBBAA) needs the alpha as a 2-digit hex.
  zenAlphaRaw = builtins.floor (opacity * 255 + 0.5);
  zenAlphaStr = lib.toHexString zenAlphaRaw;
  # Pad to 2 digits (e.g. "9" -> "09") if needed.
  zenAlphaPadded = if lib.stringLength zenAlphaStr < 2 then "0" + zenAlphaStr else zenAlphaStr;
in
{
  options.theme = {
    opacity = lib.mkOption {
      type = lib.types.float;
      default = 0.20;
      description = "Global app background opacity (0.0-1.0). Drives foot, GTK, SwayOSD, Zen, and the hyprlock input field. The quickshell bar uses 1/10 of this.";
    };
    barOpacity = lib.mkOption {
      type = lib.types.float;
      description = "Quickshell bar opacity (1/10 of theme.opacity). Internal.";
      internal = true;
    };
    zenAlphaHex = lib.mkOption {
      type = lib.types.str;
      description = "2-digit hex alpha for Zen/hex-based transparency. Internal.";
      internal = true;
    };
  };

  config.theme.barOpacity = barOpacity;
  config.theme.zenAlphaHex = zenAlphaPadded;
}
