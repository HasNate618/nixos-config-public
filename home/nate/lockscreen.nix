{ config, lib, pkgs, ... }:
let
  inherit (lib.hm.dag) entryAfter;
in
{
  home.activation.createLockBg = entryAfter [ "writeBoundary" ] ''
    WALL=$(${pkgs.jq}/bin/jq -r '.path' "$HOME/.cache/skwd-wall/last-wallpaper.json" 2>/dev/null || true)
    [ -n "$WALL" ] && [ -f "$WALL" ] && ln -sf "$WALL" "$HOME/.config/hypr/lock-bg"
  '';

  # ── Manual lock ──
  xdg.configFile."hypr/hyprlock.conf".text = ''
    source = ~/.config/hypr/hyprlock-theme-fallback.conf
    source = ~/.config/hypr/hyprlock-theme.conf

    general {
        ignore_empty_input = true
    }

    background {
        monitor =
        color = $color
        path = ~/.config/hypr/lock-bg
        blur_passes = 2
    }

    animations {
        enabled = true
        bezier = linear, 1, 1, 0, 0
        animation = fadeIn, 2, 5, linear
        animation = fadeOut, 2, 5, linear
        animation = inputFieldDots, 3, 3, linear
    }

    input-field {
        monitor =
        size = 650, 100
        position = 0, 0
        halign = center
        valign = center
        inner_color = $inner_color
        outer_color = $outer_color
        outline_thickness = 4
        font_family = JetBrainsMono Nerd Font
        font_color = $font_color
        placeholder_text = Enter Password
        check_color = $check_color
        fail_color = $fail_color
        fail_text = <i>$FAIL ($ATTEMPTS)</i>
        rounding = 0
        shadow_passes = 0
        fade_on_empty = false
    }

    auth {
        fingerprint:enabled = false
    }
  '';

  # ── Matugen theme fallback ──
  xdg.configFile."hypr/hyprlock-theme-fallback.conf".source = pkgs.writeText "hyprlock-theme-fallback.conf" ''
    $color       = rgba(11, 12, 12, 1)
    $font_color  = rgba(185, 185, 185, 1)
    $inner_color = rgba(11, 12, 12, 0.8)
    $outer_color = rgba(67, 69, 73, 1)
    $check_color = rgba(237, 154, 29, 1)
    $fail_color  = rgba(255, 102, 102, 1)
  '';
}
