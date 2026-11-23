{ config, lib, pkgs, ... }:
let
  inherit (lib.hm.dag) entryAfter;
in
{
  home.activation.createLockBg = entryAfter [ "writeBoundary" ] ''
    WALL=$(${pkgs.jq}/bin/jq -r '.path' "$HOME/.cache/skwd-wall-v2/last-wallpaper.json" 2>/dev/null || true)
    [ -n "$WALL" ] && [ -f "$WALL" ] && ln -sf "$WALL" "$HOME/.config/hypr/lock-bg"
  '';

  # hyprlock.conf is HM-owned and must never be written at runtime — doing so
  # makes the next rebuild fail with "would be clobbered". The focus toggle
  # therefore only ever writes hyprlock-focus-override.conf, a plain runtime
  # file sourced by hyprlock.conf AFTER the matugen theme but BEFORE the
  # widget blocks. It must contain ONLY variable assignments: hyprlock's
  # background/input-field/label/image/shape categories are anonymous-key
  # based, so re-opening one in a later-sourced file creates a SECOND widget
  # (that is how a duplicate password field appears). Variables are expanded
  # at parse time, so overriding them ahead of the widgets is the safe path.
  # Seed the file empty when absent: a missing `source` target makes
  # hyprlock log a globbing error on every lock.
  home.activation.seedHyprlockFocusOverride = entryAfter [ "writeBoundary" ] ''
    OVERRIDE="$HOME/.config/hypr/hyprlock-focus-override.conf"
    if [ ! -e "$OVERRIDE" ]; then
      run mkdir -p "$(dirname "$OVERRIDE")"
      run touch "$OVERRIDE"
      run chmod u+w "$OVERRIDE"
    fi
  '';

  # ── Manual lock ──
  xdg.configFile."hypr/hyprlock.conf".text = ''
    source = ~/.config/hypr/hyprlock-theme-fallback.conf
    source = ~/.config/hypr/hyprlock-theme.conf
    # Focus overrides — variables only, empty when off. MUST be sourced
    # before the widget blocks (anonymous-key categories duplicate widgets).
    source = ~/.config/hypr/hyprlock-focus-override.conf

    general {
        ignore_empty_input = true
    }

    background {
        monitor =
        color = $color
        path = ~/.config/hypr/lock-bg
        blur_passes = $bg_blur_passes
        brightness = $bg_brightness
    }

    animations {
        enabled = $anim_enabled
        bezier = niercurve, 0.4, 0, 0.2, 1
        animation = fadeIn, 1, 5, niercurve
        animation = fadeOut, 1, 5, niercurve
        animation = inputFieldDots, 1, 3, niercurve
    }

    input-field {
        monitor =
        size = 600, 94
        position = 0, 0
        halign = center
        valign = center
        inner_color = $inner_color
        outer_color = $outer_color
        outline_thickness = 3
        font_family = JetBrainsMono Nerd Font
        font_color = $font_color
        placeholder_text = ENTER PASSWORD
        check_color = $check_color
        fail_color = $fail_color
        capslock_color = $outer_color
        fail_text = <i>ACCESS DENIED ($ATTEMPTS)</i>
        rounding = 0
        shadow_passes = 0
        fade_on_empty = false
        dots_text_format = @rand:Angelic:abcdefghijklmnopqrstuvwxyz
        dots_size = 0.46
        dots_spacing = 0.35
        dots_center = true
    }

    auth {
        fingerprint:enabled = false
    }
  '';

  # ── Focus-mode wallpaper ──
  # Generated per colour scheme by focus-apply-scheme into ~/.cache/focus-bg/
  # (a solid PNG of the scheme background, applied by absolute path).

  # ── Matugen theme fallback ──
  xdg.configFile."hypr/hyprlock-theme-fallback.conf".source = pkgs.writeText "hyprlock-theme-fallback.conf" ''
    $color       = rgba(11, 12, 12, 1)
    $font_color  = rgba(172, 202, 229, 1)
    $inner_color = rgba(11, 12, 12, 0.55)
    $outer_color = rgba(172, 202, 229, 0.45)
    $check_color = rgba(237, 154, 29, 1)
    $fail_color  = rgba(255, 180, 171, 1)

    # Defaults for the focus-override variables — hyprlock.conf reads these
    # via $bg_blur_passes / $bg_brightness / $anim_enabled.
    $bg_blur_passes = 3
    $bg_brightness  = 0.40
    $anim_enabled   = 1
  '';
}
