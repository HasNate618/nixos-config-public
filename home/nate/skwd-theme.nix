{ config, lib, pkgs, ... }:

{
  # skwd-wall runtime config — defines matugen integrations
  xdg.configFile."skwd/data/config.json" = { force = true; text = builtins.toJSON { programs = { bar = false; }; }; };
  xdg.configFile."skwd-wall/config.json" = { force = true; source = ./skwd-theme-configs/config.json; };

  # skwd-wall matugen templates (custom overrides)
  xdg.configFile."skwd-wall/data/matugen/templates/hyprland-border-color".source = ./skwd-theme-configs/templates/hyprland-border-color;
  xdg.configFile."skwd-wall/data/matugen/templates/hyprland-group-border-color".source = ./skwd-theme-configs/templates/hyprland-group-border-color;
  xdg.configFile."skwd-wall/data/matugen/templates/foot-colors.conf" = { force = true; source = ./skwd-theme-configs/templates/foot-colors.conf; };
  xdg.configFile."skwd-wall/data/matugen/templates/gtk-css.css" = { force = true; source = ./skwd-theme-configs/templates/gtk-css.css; };
  xdg.configFile."skwd-wall/scripts/patch-monotheme.sh" = { force = true; executable = true; source = ./skwd-theme-configs/scripts/patch-monotheme.sh; };

  # matugen wrapper for skwd-wall — converts WebP to PNG, bypasses interactive TUI
  home.packages = with pkgs; [
    (writeShellScriptBin "skwd-matugen-wrapper" ''
      set -e
      CONFIG=""; IMAGE=""
      while [ "$#" -gt 0 ]; do
        case "$1" in
          -c|--config) CONFIG="$2"; shift 2 ;;
          image) IMAGE="$2"; shift 2 ;;
          *) shift ;;
        esac
      done
      [ -n "$IMAGE" ] || exit 1
      case "$IMAGE" in
        *.webp|*.WEBP)
          PNG_IMAGE="/tmp/skwd-matugen-$$.png"
          ${pkgs.imagemagick}/bin/magick "$IMAGE" "$PNG_IMAGE"
          MATUGEN_IMAGE="$PNG_IMAGE"
          ;;
        *) MATUGEN_IMAGE="$IMAGE" ;;
      esac
      ARGS=""
      [ -n "$CONFIG" ] && ARGS="$ARGS -c \"$CONFIG\""
      # Achromatic images get a deeper dark palette (scheme-content's green
      # fallback accent would otherwise be light tone-80 green).
      EXTRA_LIGHTNESS=""
      SAT=$(${pkgs.imagemagick}/bin/magick "$MATUGEN_IMAGE" -resize 25% -colorspace HSL -channel G -separate -format '%[fx:maxima]' info: 2>/dev/null)
      if [ "$SAT" = "0" ]; then
        EXTRA_LIGHTNESS="--lightness-dark=-0.5"
      fi
      # --fallback-color '#9575CD': achromatic (monochrome) wallpapers have no
      # extractable color -> matugen uses a default BLUE seed. Override to green
      # (user pref). Wallpapers WITH color are unaffected.
      eval "${pkgs.matugen}/bin/matugen $ARGS image \"$MATUGEN_IMAGE\" --source-color-index 0 --fallback-color '#9575CD' $EXTRA_LIGHTNESS"
      [ -n "$PNG_IMAGE" ] && rm -f "$PNG_IMAGE"
    '')
  ];
}
