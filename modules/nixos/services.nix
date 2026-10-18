{ ... }: {
  services.openssh.enable = true;

  # Rate-limit SSH brute-force attempts
  services.fail2ban.enable = true;

  # Location backend for the browser Geolocation API (Zen/Chrome on Linux
  # delegate navigator.geolocation to the GeoClue2 D-Bus daemon).
  services.geoclue2.enable = true;

  # GeoClue's resolver needs Avahi to resolve a location (daemon logs
  # "Failed to connect to avahi service" and otherwise can't get a fix).
  services.avahi.enable = true;

  # --- Memory-pressure defense (see hosts OOM freeze 2026-10) ---
  # nix.settings caps build concurrency (core.nix) so builds can't overrun RAM,
  # but any userspace hog can still exhaust RAM+swap. Without a userspace guard
  # the kernel wedges in the swap-cache reclaim path (page-alloc failure, NOT an
  # OOM-kill -- dmesg shows alloc_skb/warn_alloc/swapin_readahead, no "Killed
  # process") and the machine hard-freezes; only a hard reboot clears it.
  #
  # earlyoom is the last-resort safety net: when available RAM/Swap drop below
  # thresholds it kills the biggest RSS offender (or matching -p regexes) BEFORE
  # the kernel runs out entirely, trading one process for a live system.
  services.earlyoom = {
    enable = true;
    freeMemThreshold = 10;      # % of RAM kept free (kill below this)
    freeSwapThreshold = 10;     # % of swap kept free
    extraArgs = [
      "-g"                      # also report/respect memcg pressure
      "-N"                      # notify (systemd notify + log reason)
      "--avoid '(^|/)(systemd|init|sshd|hyprland|dbus-daemon)$'"
      "--prefer" "(^|/)cc1plus$"
      "--prefer" "(^|/)ld$"
      "--prefer" "(^|/)nix$"
      "-r 0"                    # do NOT reboot on kill; leave the user in control
    ];
  };

  # systemd-oomd applies DefaultMemoryPressureLimit to ALL cgroups (not just
  # those with memory.high set). At 80% the user slice was killed for a
  # transient browser spike (PSI hit 88%, 1,478 processes died). Raise to 95%
  # as a backstop; rely on memory.high (below) + earlyoom for targeted action.
  systemd.oomd.settings.OOM = {
    "DefaultMemoryPressureLimit" = "95%";
    "DefaultMemoryPressureDurationSec" = "10s";
  };
  # Early reclaim on the user slice so PSI never builds to the kill threshold.
  # Peak was 35.8G on 38G; set memory.high to 30G so the kernel reclaims ~8G
  # of headroom before thrashing.
  systemd.services.user-1000-memory-high = {
    wantedBy = [ "multi-user.target" ];
    after = [ "user@1000.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "/bin/sh -c 'echo 30G > /sys/fs/cgroup/user.slice/user-1000.slice/memory.high'";
    };
  };
  systemd.services."systemd-oomd".environment = {
    # PSI window granularity (systemd-oomd env overrides).
    OOMD_SWAP_THRESHOLD_MB = "4096";  # kill if swap use climbs past this delta
  };
  # Managed cgroup policy: user.slice acts on PSI (not just swap exhaustion).
  systemd.oomd.enableRootSlice = true;
  systemd.oomd.enableSystemSlice = true;
  systemd.oomd.enableUserSlices = true;
}
