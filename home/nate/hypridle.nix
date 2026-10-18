{ config, lib, pkgs, ... }:

{
  # ─── hypridle config ───────────────────────────────────────────────────────
  xdg.configFile."hypr/hypridle.conf".text = ''
    general {
        lock_cmd = pidof hyprlock || hyprlock
        # kbd: shared kbd-save-restore (first-wins, records 0, idempotent restore);
        # display: save for i915 S3 register loss (panel back to black)
        before_sleep_cmd = loginctl lock-session; $HOME/.local/bin/kbd-save-restore save; brightnessctl -d intel_backlight get > /tmp/display-brightness
        # dpms-wake cycles DPMS off->on UNCONDITIONALLY. `dpms enable` is a hard
        # no-op when Hyprland already reports dpmsStatus=1 (CMonitor::setDPMS
        # early-returns on `m_dpmsStatus == on`), which is exactly the state of
        # the lit-but-black failure — so a conditional cycle never fires when it
        # is needed. A real off->on cycle rebuilds the connector and is the only
        # thing that recovers (why a manual DPMS toggle works). 1s settle: this
        # runs the instant PrepareForSleep(false) arrives, while aquamarine is
        # still restoring CRTCs, and a dispatch inside that window is superseded.
        after_sleep_cmd = $HOME/.local/bin/dpms-wake 1; $HOME/.local/bin/kbd-save-restore restore; test -s /tmp/display-brightness && { v=$(cat /tmp/display-brightness); for i in 1 2 3 4 5 6 7 8 9 10; do brightnessctl -d intel_backlight set "$v" 2>/dev/null && { rm -f /tmp/display-brightness; break; }; sleep 0.4; done; }
    }

    # Screen off after 4:54 — 6s window to input and wake back up before lock
    listener {
        timeout = 294
        on-timeout = hyprctl dispatch 'hl.dsp.dpms({ action = "disable" })'
        on-resume = $HOME/.local/bin/dpms-wake
    }
    # Lock after 5 min (kbd off first, then lock)
    listener {
        timeout = 300
        on-timeout = $HOME/.local/bin/kbd-save-restore save; hyprlock
        on-resume = $HOME/.local/bin/kbd-save-restore restore
    }

    # Suspend after 30 min idle
    listener {
        timeout = 1800
        on-timeout = systemctl suspend -i
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
      # hyprlock is spawned as a CHILD of hypridle (listener on-timeout, lock_cmd) and
      # lives in hypridle.service's cgroup for the whole locked period. With the default
      # KillMode=control-group, any `systemctl --user stop/restart hypridle` (the
      # hypr-idle-toggle off branch, home-manager activation on rebuild) SIGTERMs
      # hyprlock mid-lock: Hyprland then keeps the session locked with a dead client
      # (built-in "lockdead" screen) and refuses re-locks. Kill only the daemon itself.
      KillMode = "process";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
