{ pkgs, ... }: {
  systemd.user.services.monitor-auto-layout-rebuild = {
    Unit = {
      Description = "Run monitor auto-layout after rebuild";
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "/etc/profiles/per-user/nate/bin/hypr-monitor-auto-layout";
      Environment = "WAYLAND_DISPLAY=wayland-0";
    };
    Install.WantedBy = [ "default.target" ];
  };

  systemd.user.services.auto-rotate = {
    Unit = {
      Description = "Always-on accelerometer screen rotation";
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "/etc/profiles/per-user/nate/bin/hypr-auto-rotate";
      Environment = "WAYLAND_DISPLAY=wayland-0";
      Restart = "always";
      RestartSec = 2;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
