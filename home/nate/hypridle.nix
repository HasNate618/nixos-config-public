{ config, lib, pkgs, ... }:

{
  # ─── hypridle config ───────────────────────────────────────────────────────
  xdg.configFile."hypr/hypridle.conf".text = ''
    general {
        lock_cmd = pidof hyprlock || hyprlock
        # kbd: save only if lit (avoid restoring 0 after lock/sleep chains);
        # display: save for i915 S3 register loss (panel back to black)
        before_sleep_cmd = loginctl lock-session && (v=$(brightnessctl -d '*::kbd_backlight' get); [ "$v" -gt 0 ] && echo "$v" > /tmp/kbd-brightness); brightnessctl -d '*::kbd_backlight' set 0; brightnessctl -d intel_backlight get > /tmp/display-brightness
        after_sleep_cmd = hyprctl dispatch 'hl.dsp.dpms({ action = "enable" })' && test -s /tmp/kbd-brightness && brightnessctl -d '*::kbd_backlight' set "$(cat /tmp/kbd-brightness)" && rm -f /tmp/kbd-brightness && test -s /tmp/display-brightness && brightnessctl -d intel_backlight set "$(cat /tmp/display-brightness)" && rm -f /tmp/display-brightness
    }

    # Screen off after 4:54 — 6s window to input and wake back up before lock
    listener {
        timeout = 294
        on-timeout = hyprctl dispatch 'hl.dsp.dpms({ action = "disable" })'
        on-resume = hyprctl dispatch 'hl.dsp.dpms({ action = "enable" })'
    }
    # Lock after 5 min (kbd off first, then lock)
    listener {
        timeout = 300
        on-timeout = (v=$(brightnessctl -d '*::kbd_backlight' get); [ "$v" -gt 0 ] && echo "$v" > /tmp/kbd-brightness); brightnessctl -d '*::kbd_backlight' set 0; hyprlock
        on-resume = test -s /tmp/kbd-brightness && brightnessctl -d '*::kbd_backlight' set "$(cat /tmp/kbd-brightness)" && rm -f /tmp/kbd-brightness
    }

    # Suspend after 30 min (AC+evening → delay to 23:00; battery or off-hours → now)
    listener {
        timeout = 1800
        on-timeout = $HOME/.local/bin/idle-suspend.sh schedule
        on-resume = $HOME/.local/bin/idle-suspend.sh cancel
    }

    # Power button wake: on-resume checks flag and restores
    listener {
        timeout = 1
        on-timeout = true
        on-resume = $HOME/.local/bin/power-btn-wake
    }
  '';

  # ─── systemd user service for reliable auto-start ────────────────────────
  systemd.user.services.hypridle = {
    Unit = {
      Description = "Hyprland idle daemon";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.hypridle}/bin/hypridle";
      Restart = "on-failure";
      RestartSec = 3;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
