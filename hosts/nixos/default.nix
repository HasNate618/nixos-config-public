{ config, lib, pkgs, nix-cachyos-kernel, grok-bot, pi-flake, ... }: {
  imports = [
    ./hardware-configuration.nix
    ./thermal-log.nix
  ];
  # skwd-wall v2 (1.0.0-beta.17): skwd-walld daemon, skwd-paper-v2 renderers,
  # skwd-lens semantic search. Replaces the v1 skwd-daemon stack — v2 has no
  # bundled matugen, so the LD_PRELOAD matugen-hook shim is gone.
  #
  # NixOS builds the unit PATH from `path` (+ coreutils/findutils/grep/sed/
  # systemd), so the daemon does NOT see the user profile: hand it the same
  # dirs the v1 daemon wrapper exported, so the matugen wrapper and the
  # post-processing scripts (asusctl/brightnessctl/python3/…) resolve, plus
  # the tools the daemon itself shells out to by bare name.
  services.skwd-deck.enable = true;
  systemd.user.services.skwd-walld.path = [
    # NB: systemd adds /bin (+/sbin) to every `path` entry, so pass parents.
    "/home/nate/.local"
    "/run/current-system/sw"
    "/etc/profiles/per-user/nate"
    (pkgs.writeScriptBin "matugen" (builtins.readFile ../../home/nate/bin/matugen))
    pkgs.bash
    pkgs.ffmpeg
    pkgs.hyprland
    pkgs.jq
    pkgs.procps
    pkgs.util-linux
  ];
  boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-latest;
  # acpi_call: probe ASUS WMI DSTS devids (dGPU base/set TGP 0x00090019/20)
  boot.extraModulePackages = [ config.boot.kernelPackages.acpi_call ];
  nixpkgs.overlays = [ nix-cachyos-kernel.overlays.default (import ../../modules/nixos/quickshell-overlay.nix) (import ../../modules/nixos/opencode-overlay.nix) (import ../../modules/nixos/wl-kbptr-overlay.nix) (import ../../modules/nixos/hyprland-055-overlay.nix) (import ../../modules/nixos/kvantum-overlay.nix) (import ../../modules/nixos/hyprlock-overlay.nix) pi-flake.overlays.default ];
  hardware.enableRedistributableFirmware = true;
  boot.kernelModules = [ "iwlwifi" "nvidia" "acpi_call" ];
  # Read-only WMI probe: query dGPU TGP base/max via ATKD.DSTS
  systemd.services.acpi-tgp-probe = {
    description = "Probe ASUS WMI dGPU TGP devids";
    after = [ "multi-user.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    serviceConfig.ExecStart = pkgs.writeShellScript "acpi-tgp-probe" ''
      exec > /var/log/acpi-tgp-probe.log 2>&1
      for pair in NV_DYN_BOOST:0x90011 DGPU_BASE_TGP:0x90019 DGPU_SET_TGP:0x90020; do
        name=''${pair%%:*}; devid=''${pair##*:}
        printf '%s (%s) -> ' "$name" "$devid"
        echo "\\_SB.ATKD.DSTS $devid" > /proc/acpi/call
        cat /proc/acpi/call; echo
      done
    '';
  };
  boot.kernelParams = [ "quiet" "systemd.show_status=true" "i915.enable_guc=2" "i915.enable_dc=2" "i915.enable_fbc=0" ];
  services.xserver.videoDrivers = [ "modesetting" "nvidia" ];
  # nvidia-persistenced fails (and marks the system degraded) whenever it is
  # started while the dGPU is powered off — e.g. a rebuild on battery, or
  # after an RTD3 removal. Gate it on the GPU actually being initialised:
  # the /proc glob alone can still pass for a moment mid-RTD3 (the proc
  # entry outlives the device nodes), so ExecCondition additionally gates on
  # /dev/nvidia0 — the node the daemon actually needs. An ExecCondition skip
  # (exit 1) is NOT a failure, so rebuilds with the GPU asleep exit cleanly
  # and the system stays non-degraded.
  systemd.services.nvidia-persistenced.serviceConfig = {
    ConditionPathExistsGlob = [ "/proc/driver/nvidia/gpus/*/information" ];
    ExecCondition = [ "${pkgs.coreutils}/bin/test -e /dev/nvidia0" ];
  };
  hardware.nvidia = {
    package = config.boot.kernelPackages.nvidiaPackages.new_feature;
    modesetting.enable = true;
    open = false;  # proprietary modules: nvidia-powerd NVPCF Dynamic Boost needs them (openRM lacks it)
    prime = {
      offload.enable = true;
      offload.enableOffloadCmd = true;
      intelBusId = "PCI:0@0:2:0";
      nvidiaBusId = "PCI:1@0:0:0";
    };
    powerManagement.finegrained = true;
    dynamicBoost.enable = true;
    nvidiaPersistenced = true;
    powerManagement.enable = true;
  };
  services.asusd.enable = true;
  # asusd does NOT apply charge_control_end_threshold from asusd.ron at
  # startup — it reloads whatever the EC currently holds (100 after a
  # power cycle, since the EC reset + BIOS ERP change). Re-apply the
  # user-persisted limit at boot (fallback 70 when never set).
  systemd.services.asusd-charge-limit = {
    description = "Apply ASUS battery charge limit (EC does not persist it)";
    wantedBy = [ "multi-user.target" ];
    after = [ "asusd.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      LIMIT=$(cat /var/lib/asus-charge-limit/limit 2>/dev/null || echo 70)
      case "$LIMIT" in ""|*[!0-9]*) LIMIT=70 ;; esac
      # asusd's dbus may not be ready yet — retry instead of silently
      # skipping (the old `|| true` left the EC limit wrong with no trace).
      for i in $(seq 1 30); do
        if ${pkgs.asusctl}/bin/asusctl battery limit "$LIMIT" >/dev/null 2>&1; then
          mkdir -p /var/lib/asus-charge-limit
          echo "$LIMIT" > /var/lib/asus-charge-limit/limit
          exit 0
        fi
        sleep 1
      done
      echo "asusd-charge-limit: failed to set $LIMIT after 30s" >&2
      exit 1
    '';
  };
  # Declarative asusd.ron — prevents asusd from regenerating its own
  # defaults (PptPl1Spl=100, PptPl2Sppt=135, NvDynamicBoost=20) which
  # Valid armoury ranges: ppt_pl1_spl max 110, ppt_pl2_sppt max 135, nv_dynamic_boost max 20.
  # Auto-switch OFF: ac-power-apply owns profile transitions (asusd missed plug events, stuck Quiet on AC).
  services.asusd.asusdConfig.text = ''
    (
        # FALLBACK default for the charge limit (asusd does NOT re-apply
        # this at boot — it reloads the EC value). The effective limit is
        # /var/lib/asus-charge-limit/limit, written by asus-charge-limit-set
        # whenever the widget changes it; asusd-charge-limit.service applies
        # it at boot. Edit the 70s HERE to change the never-set fallback.
        charge_control_end_threshold: 70,
        base_charge_control_end_threshold: 70,
        disable_nvidia_powerd_on_battery: true,
        ac_command: "",
        bat_command: "",
        platform_profile_linked_epp: true,
        platform_profile_on_battery: Quiet,
        change_platform_profile_on_battery: false,
        platform_profile_on_ac: Performance,
        change_platform_profile_on_ac: false,
        profile_quiet_epp: Power,
        profile_balanced_epp: BalancePower,
        profile_custom_epp: Performance,
        profile_performance_epp: Performance,
        ac_profile_tunings: {
            Balanced: (
                enabled: false,
                group: {},
            ),
            Quiet: (
                enabled: false,
                group: {},
            ),
            Performance: (
                enabled: true,
                group: {
                    PptPl2Sppt: 135,
                    NvTempTarget: 87,
                    PptPl1Spl: 110,
                    NvDynamicBoost: 20,
                },
            ),
        },
        dc_profile_tunings: {
            Performance: (
                enabled: false,
                group: {},
            ),
            Balanced: (
                enabled: false,
                group: {},
            ),
            Quiet: (
                enabled: false,
                group: {},
            ),
        },
        armoury_settings: {
            MiniLedMode: 0,
            PanelOverdrive: 1,
            BootSound: 0,
        },
    )
  '';

  systemd.services.asusd-fan-curves = {
    description = "Set custom fan curves for asusd";
    after = [ "asusd.service" ];
    wantedBy = [ "asusd.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.writeShellScriptBin "set-fan-curves" ''
        ${pkgs.asusctl}/bin/asusctl fan-curve --mod-profile performance --fan cpu --data '40c:0,55c:0,62c:45,70c:110,78c:160,85c:210,92c:245,98c:255'
        ${pkgs.asusctl}/bin/asusctl fan-curve --mod-profile performance --fan gpu --data '40c:0,55c:0,62c:40,66c:100,74c:150,82c:200,90c:240,98c:255'
        ${pkgs.asusctl}/bin/asusctl fan-curve --mod-profile performance --fan mid --data '40c:0,55c:0,62c:40,68c:90,76c:140,84c:195,92c:240,98c:255'
        ${pkgs.asusctl}/bin/asusctl fan-curve --mod-profile performance --enable-fan-curves true
        ${pkgs.asusctl}/bin/asusctl fan-curve --mod-profile balanced --fan cpu --data '40c:0,55c:0,62c:40,68c:90,75c:140,82c:190,90c:235,98c:255'
        ${pkgs.asusctl}/bin/asusctl fan-curve --mod-profile balanced --fan gpu --data '40c:0,52c:0,60c:40,66c:90,73c:140,80c:190,88c:235,98c:255'
        ${pkgs.asusctl}/bin/asusctl fan-curve --mod-profile balanced --fan mid --data '40c:0,55c:0,62c:38,68c:85,75c:135,82c:185,90c:230,98c:255'
        ${pkgs.asusctl}/bin/asusctl fan-curve --mod-profile balanced --enable-fan-curves true
        ${pkgs.asusctl}/bin/asusctl fan-curve --mod-profile quiet --fan cpu --data '55c:0,62c:0,68c:15,74c:40,80c:70,86c:110,93c:180,100c:255'
        ${pkgs.asusctl}/bin/asusctl fan-curve --mod-profile quiet --fan gpu --data '55c:0,62c:0,68c:15,74c:40,80c:70,86c:110,93c:180,100c:255'
        ${pkgs.asusctl}/bin/asusctl fan-curve --mod-profile quiet --fan mid --data '55c:0,62c:0,68c:12,74c:38,80c:68,86c:108,93c:178,100c:255'
        ${pkgs.asusctl}/bin/asusctl fan-curve --mod-profile quiet --enable-fan-curves true
      ''}/bin/set-fan-curves";
    };
  };

  # The silicon-enforced package power limit lives in the *MMIO* RAPL domain
  # (intel-rapl-mmio:0), NOT the MSR domain (intel-rapl:0) that force-perf-profile
  # writes. Left at stock ~22W/27W the CPU pins at ~2.4GHz all-core despite
  # ppt_pl1_spl=200 in EC. Set BOTH domains to 65W: unlocks 4.8-5.0GHz bursts
  # while holding CPU package temp ~75-80C under gaming/AI load (vs 95C+ at 100W+).
  systemd.services.rapl-reset = {
    description = "Set package RAPL limit to 65W (CPU+GPU, MMIO + MSR domains)";
    after = [ "multi-user.target" "asusd.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.writeShellScriptBin "rapl-reset" ''
        # MMIO domain = what the hardware actually enforces
        # AC: 50W (thermal-safe with degraded paste); Battery: 20W (cool + long runtime)
        AC=$(cat /sys/class/power_supply/AC0/online 2>/dev/null || echo 0)
        MMIO=$([ "$AC" = "1" ] && echo 50000000 || echo 20000000)
        echo $MMIO > /sys/class/powercap/intel-rapl-mmio:0/constraint_0_power_limit_uw 2>/dev/null || true
        echo $MMIO > /sys/class/powercap/intel-rapl-mmio:0/constraint_1_power_limit_uw 2>/dev/null || true
        echo $MMIO > /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw 2>/dev/null || true
      ''}/bin/rapl-reset";
    };
  };
  services.power-profiles-daemon.enable = false;
  # No cellular modem hardware on flow (WiFi-only CNVi) - MM is pure idle waste
  networking.modemmanager.enable = false;
  services.tlp = {
    enable = true;
    settings = {
      CPU_SCALING_GOVERNOR_ON_AC = "performance";
      TLP_DEFAULT_MODE = "BAT";
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
      CPU_ENERGY_PERF_POLICY_ON_AC = "performance";
      CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
      CPU_MIN_PERF_ON_AC = 0;
      CPU_MAX_PERF_ON_AC = 100;
      CPU_MIN_PERF_ON_BAT = 0;
      CPU_BOOST_ON_AC = 1;
      CPU_BOOST_ON_BAT = 0;
      PLATFORM_PROFILE_ON_AC = "";  # disabled: ac-power-apply owns profile; TLP must not flip it
      PLATFORM_PROFILE_ON_BAT = "";  # disabled: ac-power-apply owns profile; TLP must not flip it
      RUNTIME_PM_ON_AC = "on";
      RUNTIME_PM_ON_BAT = "auto";
      PCIE_ASPM_ON_AC = "default";
      PCIE_ASPM_ON_BAT = "powersupersave";
      WIFI_PWR_SAVE_ON_AC = "off";
      WIFI_PWR_SAVE_ON_BAT = "on";
      USB_AUTOSUSPEND = 1;
      SOUND_POWER_SAVE_ON_AC = 0;
      SOUND_POWER_SAVE_ON_BAT = 1;
      SOUND_POWER_SAVE_CONTROLLER = "Y";
      RUNTIME_PM_ALL = 1;
      CPU_MAX_PERF_ON_BAT = 20;
    };
  };
  # Lower swappiness: prefer dropping page cache over swapping process memory
  # to disk — fewer disk wakeups = better battery
  boot.kernel.sysctl = {
    "vm.swappiness" = 10;
    "vm.vfs_cache_pressure" = 50;
    "vm.dirty_ratio" = 10;
    "vm.dirty_background_ratio" = 5;
    "vm.dirty_writeback_centisecs" = 1500;
  };
  boot.extraModprobeConfig = "options nvidia NVreg_PreserveVideoMemoryAllocations=1 NVreg_RegistryDwords=\"OverrideMaxPerf=0x1\"
options asus_nb_wmi tablet_mode_sw=0
";
  boot.blacklistedKernelModules = [ "nouveau" ];
  boot.resumeDevice = "/dev/disk/by-uuid/716a5f26-630d-4a6e-900d-f28a62f00752";
  # Homelab CA: import caddy-ca.crt manually if you need internal TLS trust
  # for Vaultwarden/AdGuard. Not committed to this repo.
  # security.pki.certificateFiles = [ ../../modules/server/caddy-ca.crt ];
  security.sudo.extraRules = [{
    users = [ "nate" ];
    commands = [
      { command = "/run/current-system/sw/bin/asus-charge-limit-set"; options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/platform-profile"; options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/mini-led-toggle"; options = [ "NOPASSWD" ]; }
      { command = "/home/nate/.local/bin/nixos-safe-rebuild"; options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/tee"; options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/tlp"; options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/to-default"; options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/to-battery"; options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/grub-menu"; options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/systemctl"; options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/wg"; options = [ "NOPASSWD" ]; }
    ];
  }];
  environment.systemPackages = with pkgs; [
    ddcutil
    grok-bot
    (writeShellScriptBin "asus-charge-limit-set" ''
      # Widget entry point: applies via asusd's own client (so asusd's
      # in-memory state matches) AND persists for the next boot.
      pct="$1"
      case "$pct" in ""|*[!0-9]*) echo "usage: asus-charge-limit-set <percent>" >&2; exit 1 ;; esac
      ${pkgs.asusctl}/bin/asusctl battery limit "$pct" || exit 1
      mkdir -p /var/lib/asus-charge-limit
      echo "$pct" > /var/lib/asus-charge-limit/limit
    '')
    (writeShellScriptBin "platform-profile" ''
      echo "$1" > /sys/firmware/acpi/platform_profile
    '')
    (writeShellScriptBin "mini-led-toggle" ''
      val=$(cat /sys/devices/platform/asus-nb-wmi/mini_led_mode)
      echo $((val ^ 1)) > /sys/devices/platform/asus-nb-wmi/mini_led_mode
      new=$(cat /sys/devices/platform/asus-nb-wmi/mini_led_mode)
      echo "Mini-LED mode: $new"
    '')
    # Boot-entry selection: grub-editenv next_entry makes the next boot land
    # on the chosen entry with the GRUB menu skipped (entry consumed after
    # one boot, then the menu returns). No mux involvement.
    (writeShellScriptBin "to-default" ''
      ${pkgs.grub2}/bin/grub-editenv /boot/grub/grubenv set next_entry="NixOS - Default" 2>/dev/null \
        || { echo "ERROR: grubenv write failed"; exit 1; }
      echo "next boot: Default"
      if [ "$1" = "--now" ]; then systemctl reboot; fi
      exit 0
    '')
    (writeShellScriptBin "to-battery" ''
      ${pkgs.grub2}/bin/grub-editenv /boot/grub/grubenv set next_entry="NixOS - Battery" 2>/dev/null \
        || { echo "ERROR: grubenv write failed"; exit 1; }
      echo "next boot: Battery"
      if [ "$1" = "--now" ]; then systemctl reboot; fi
      exit 0
    '')
    (writeShellScriptBin "grub-menu" ''
      ${pkgs.grub2}/bin/grub-editenv /boot/grub/grubenv unset next_entry 2>/dev/null || true
      echo "next boot will show the GRUB menu"
    '')
    # Single owner for AC transitions: applies FULL power state from adapter+battery.
    # Battery mode when AC0=0 OR BAT0=Discharging (covers phantom-AC0-stuck-1).
    # Fired by udev (starts ac-power-apply.service) on AC0 change + at boot. Idempotent via /run/ac-power-last.
    (writeShellScriptBin "ac-power-apply" ''
      set +e
      AC=$(cat /sys/class/power_supply/AC0/online 2>/dev/null || echo 1)
      BS=$(cat /sys/class/power_supply/BAT0/status 2>/dev/null || echo Unknown)
      if [ "$AC" = "1" ] && [ "$BS" != "Discharging" ]; then MODE=AC; else MODE=BAT; fi
      if [ "$MODE" = "AC" ]; then want=performance; else want=quiet; fi
      last=$(cat /run/ac-power-last 2>/dev/null || echo "")
      cur=$(cat /sys/firmware/acpi/platform_profile 2>/dev/null || echo "")
      # NOTE: this intentionally overrides manual profile changes on the next
      # trigger (single-owner policy: AC state owns the profile, no exceptions).
      { [ "$MODE" = "$last" ] && [ "$cur" = "$want" ]; } && exit 0
      echo "$MODE" > /run/ac-power-last
      if [ "$MODE" = "AC" ]; then
        ${pkgs.asusctl}/bin/asusctl profile set performance || true
        /run/current-system/sw/bin/tlp ac || true
        echo 0 > /sys/devices/system/cpu/intel_pstate/no_turbo || true
        echo 100 > /sys/devices/system/cpu/intel_pstate/max_perf_pct || true
        HWMAX=$(cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq 2>/dev/null || echo 5200000)
        for c in /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq; do echo "$HWMAX" > "$c" || true; done
        for c in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo performance > "$c" || true; done
        for c in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do echo performance > "$c" || true; done
        echo 50000000 > /sys/class/powercap/intel-rapl-mmio:0/constraint_0_power_limit_uw || true
        echo 50000000 > /sys/class/powercap/intel-rapl-mmio:0/constraint_1_power_limit_uw || true
        echo 50000000 > /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw || true
      else
        ${pkgs.asusctl}/bin/asusctl profile set quiet || true
        /run/current-system/sw/bin/tlp bat || true
        echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo || true
        echo 20 > /sys/devices/system/cpu/intel_pstate/max_perf_pct || true
        for c in /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq; do echo 2600000 > "$c" || true; done
        for c in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo powersave > "$c" || true; done
        for c in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do echo power > "$c" || true; done
        echo 20000000 > /sys/class/powercap/intel-rapl-mmio:0/constraint_0_power_limit_uw || true
        echo 20000000 > /sys/class/powercap/intel-rapl-mmio:0/constraint_1_power_limit_uw || true
        echo 20000000 > /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw || true
      fi
      # Re-pin ron's auto-switch flags: asusd rewrites them on profile set.
      # --no-block: guard is After=ac-power-apply, a blocking start deadlocks boot.
      /run/current-system/sw/bin/systemctl start --no-block asusd-ron-guard.service || true
      # Immediate Hz follow-up (profile just changed; timer backstop would take up to 15s)
      /run/current-system/sw/bin/systemctl start platform-profile-switch.service || true
    '')
  ];
  # DDC/CI for monitor brightness control
  hardware.i2c.enable = true;
  # Accelerometer / auto-rotation sensor proxy
  services.udev.extraRules = ''
    KERNEL=="iio:device*", SUBSYSTEM=="iio", ATTR{name}=="accel_3d", TAG+="systemd", ENV{SYSTEMD_WANTS}="iio-sensor-proxy.service"
    # Disable ELAN9008 UNKNOWN sub-devices that cause cursor teleporting
    KERNEL=="event*", ATTRS{name}=="ELAN9008:00 04F3:2FC4 UNKNOWN", ENV{LIBINPUT_IGNORE}="1"
    # AC transitions: single-owner handler applies full power state (see ac-power-apply).
    # TLP 85-tlp.rules also fires tlp auto here; the 15s timer re-enforces on mismatch.
    # udev cannot RUN a /run path (build-time existence check) -> trigger the service instead.
    ACTION=="change", SUBSYSTEM=="power_supply", KERNEL=="AC0", TAG+="systemd", ENV{SYSTEMD_WANTS}+="ac-power-apply.service"
  '';
  systemd.services.iio-sensor-proxy = {
    description = "IIO Sensor Proxy for accelerometer/rotation";
    wantedBy = [ "multi-user.target" ];
    after = [ "multi-user.target" ];
    serviceConfig = {
      Type = "dbus";
      BusName = "net.hadess.SensorProxy";
      ExecStart = "${pkgs.iio-sensor-proxy}/libexec/iio-sensor-proxy";
      Restart = "on-failure";
    };
  };
  # Enable multi-zone before shutdown/reboot for deep blacks on dark screens,
  # then disable on boot (restore single-zone for text/UI clarity)
  systemd.services.mini-led-shutdown = {
    description = "Enable mini-LED multi-zone before shutdown/reboot";
    before = [ "shutdown.target" "reboot.target" "halt.target" ];
    wantedBy = [ "shutdown.target" "reboot.target" "halt.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "/bin/true";
      ExecStop = "${pkgs.writeShellScriptBin "mini-led-on" ''
        echo 1 > /sys/devices/platform/asus-nb-wmi/mini_led_mode
      ''}/bin/mini-led-on";
    };
  };
  systemd.services.mini-led-boot = {
    description = "Disable mini-LED multi-zone after boot (restore single-zone)";
    after = [ "graphical.target" ];
    wantedBy = [ "graphical.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.writeShellScriptBin "mini-led-off" ''
        echo 0 > /sys/devices/platform/asus-nb-wmi/mini_led_mode
      ''}/bin/mini-led-off";
    };
  };
  # Set ASUS EC power tuning values before nvidia-powerd starts
  systemd.services.asus-ec-power-tune = {
    description = "Set ASUS EC power tuning for GPU Dynamic Boost";
    before = [ "nvidia-powerd.service" ];
    wantedBy = [ "nvidia-powerd.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.writeShellScriptBin "asus-ec-power-tune" ''
        write_ec() {
          [ -f "$1" ] && echo "$2" > "$1" || echo "WARN: $1 not found, skipping"
        }
        EC=/sys/devices/platform/asus-nb-wmi
        write_ec "$EC/nv_dynamic_boost" 20
        write_ec "$EC/nv_temp_target" 87
        write_ec "$EC/ppt_pl1_spl" 110
        write_ec "$EC/ppt_pl2_sppt" 135
        write_ec "$EC/throttle_thermal_policy" 1
      ''}/bin/asus-ec-power-tune";
    };
  };
  # Force Performance profile + turbo + full clocks on AC boot.
  # asusd only re-asserts profile on AC<->BAT transition, so a transient
  # flip to Quiet (or a stuck Quiet on AC) leaves no_turbo=1 and a 2.6GHz
  # scaling_max_freq cap permanently. This corrects it on every boot (AC only).
  systemd.services.force-perf-profile = {
    description = "Force Performance profile + turbo on AC";
    after = [ "asusd.service" "multi-user.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      # Only force Performance when on AC (leave battery boot quiet/powersave alone)
      AC=$(cat /sys/class/power_supply/AC0/online 2>/dev/null || echo 1)
      [ "$AC" = "1" ] || exit 0
      ${pkgs.asusctl}/bin/asusctl profile set performance || true
      # Re-enable turbo (Quiet profile disables it)
      echo 0 > /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null || true
      # Clear any scaling_max_freq cap (Quiet sets 2.6GHz)
      HWMAX=$(cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq 2>/dev/null || echo 5200000)
      for c in /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq; do
        echo "$HWMAX" > "$c" 2>/dev/null || true
      done
      # EC package envelope (informational; the real silicon cap is the MMIO RAPL domain)
      echo 110 > /sys/devices/platform/asus-nb-wmi/ppt_pl1_spl 2>/dev/null || true
      echo 135 > /sys/devices/platform/asus-nb-wmi/ppt_pl2_sppt 2>/dev/null || true
      echo 87 > /sys/devices/platform/asus-nb-wmi/nv_temp_target 2>/dev/null || true
      # MSR domain view (intel_pstate) - keep consistent with enforced MMIO limit
      echo 50000000 > /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw 2>/dev/null || true
      # THE ENFORCED LIMIT: intel-rapl-mmio:0. Stock EC/default leaves this at
      # ~22W/27W which pins the CPU at 2.4GHz all-core. 65W unlocks 4.8-5.0GHz
      # bursts while keeping CPU package temp ~75-80C under load (95C+ at 100W+).
      echo 50000000 > /sys/class/powercap/intel-rapl-mmio:0/constraint_0_power_limit_uw 2>/dev/null || true
      echo 50000000 > /sys/class/powercap/intel-rapl-mmio:0/constraint_1_power_limit_uw 2>/dev/null || true
      # Direct MSR write: ensure PL1=PL2 (no inverted cap) so P-cores boost freely.
      modprobe msr 2>/dev/null || true
      ${pkgs.msr-tools}/bin/wrmsr -p 0 0x610 0x42864000df8640 2>/dev/null || true
    '';
  };
  # Re-assert EC GPU power tuning whenever nvidia-powerd (re)starts.
  # nixos-rebuild switch restarts nvidia-powerd, which re-reads stale EC
  # state and drops GPU power limit back to 55W. This path unit re-runs
  # force-perf-profile when nvidia-powerd starts, restoring 87/80W.
  systemd.paths.reassert-ec-on-powerd = {
    description = "Re-assert EC GPU power tuning when nvidia-powerd starts";
    wantedBy = [ "multi-user.target" ];
    pathConfig = {
      PathExistsGlob = [ "/run/systemd/units/invocation:nvidia-powerd.service" ];
      Unit = "force-perf-profile.service";
    };
  };

  # Boot + udev-driven full power-state apply (single owner for AC transitions).
  # Replaces asusd auto-switch (missed plug events) and TLP profile writes.
  # udev starts this unit on AC0 change (SYSTEMD_WANTS); wantedBy covers boot.
  systemd.services.ac-power-apply = {
    description = "Apply full power state from AC adapter/battery state";
    after = [ "asusd.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "/run/current-system/sw/bin/ac-power-apply";
    };
  };
  # asusd rewrites /etc/asusd/asusd.ron at runtime (replaces the Nix symlink
  # with a regular file), flipping change_platform_profile_* back to true and
  # re-enabling its flaky auto-switch (observed: perf->quiet flap + 50W Saga
  # 2026-09-12). Re-pin the flags after asusd is up; restart asusd only when
  # something was actually fixed. Symlink present = declaration intact, no-op.
  # Charge threshold deliberately untouched (owned by asus-charge-limit-set).
  # See above: asusd re-applies sticky profile on restart; reconcile after every start.
  systemd.services.asusd.serviceConfig.ExecStartPost = [
    "/run/current-system/sw/bin/systemctl start --no-block ac-power-apply.service"
  ];
  systemd.services.asusd-ron-guard = {
    description = "Re-pin asusd auto-switch flags asusd rewrites at runtime";
    after = [ "asusd.service" "ac-power-apply.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      RON=/etc/asusd/asusd.ron
      [ -L "$RON" ] && exit 0
      fixed=0
      for key in change_platform_profile_on_battery change_platform_profile_on_ac; do
        if ${pkgs.gnugrep}/bin/grep -q "$key: true," "$RON" 2>/dev/null; then
          ${pkgs.gnused}/bin/sed -i "s/$key: true,/$key: false,/" "$RON" 2>/dev/null && fixed=1 || true
        fi
      done
      if [ "$fixed" = "1" ]; then
        # --no-block: guard is After=asusd, a blocking restart deadlocks the same way.
        /run/current-system/sw/bin/systemctl restart --no-block asusd.service || true
      fi
    '';
  };
  # Supergfxctl manages GPU mode switching with VFIO rebind
  # Switch display Hz when platform_profile changes; sync TLP mode.
  # Change-gated (see script): unchanged ticks exit in ~1ms instead of
  # running the full 50ms+ pipeline — the old 3s unconditional poll kept
  # the CPU out of deep C-states. 15s backstop only; ac-power-apply owns transitions.
  systemd.timers.platform-profile-switch = {
    wantedBy = [ "multi-user.target" ];
    timerConfig.OnBootSec = "5s";
    timerConfig.OnUnitActiveSec = "15s";
  };
  systemd.services.platform-profile-switch = {
    description = "Set display Hz based on platform profile";
    serviceConfig.Type = "oneshot";
    serviceConfig.User = "nate";
    environment.XDG_RUNTIME_DIR = "/run/user/1000";
    
    script = ''
      export PATH="/run/wrappers/bin:/run/current-system/sw/bin:$PATH"
      profile=$(cat /sys/firmware/acpi/platform_profile 2>/dev/null || echo "performance")
      # Desired TLP power source per platform profile (quiet→BAT, else AC)
      case "$profile" in
        quiet) desired_pwr=1 ;;
        performance|balanced) desired_pwr=0 ;;
        *) desired_pwr="" ;;
      esac
      # TLP's applied mode is readable cheaply from /run/tlp/last_pwr
      # (field 2: 1=BAT, 0=AC) — no tlp-stat spawn needed.
      tlp_pwr=$(awk '{print $2}' /run/tlp/last_pwr 2>/dev/null || echo "")
      # Change gate: profile unchanged AND TLP still matching → ~1ms no-op
      last=$(cat /tmp/platform-profile-last 2>/dev/null || echo "")
      # Compute desired Hz for this profile (drift gate)
      # NOTE: this hyprctl call runs BEFORE HYPRLAND_INSTANCE_SIGNATURE is
      # exported below, so it fails under `set -e` (hyprctl prints to stdout,
      # jq parse error, exit 5) without the `|| true` guards — that killed the
      # service every 15s and skipped the TLP sync + CPU re-assert. Empty values
      # just skip the gates.
      case "$profile" in
        quiet) want_hz=60 ;;
        performance|balanced) want_hz=240 ;;
        *) want_hz="" ;;
      esac
      cur_hz=$(${pkgs.hyprland}/bin/hyprctl monitors -j | ${pkgs.jq}/bin/jq -r '.[] | select(.name == "eDP-1") | .refreshRate | floor' 2>/dev/null || true)
      if [ "$profile" = "$last" ] && [ "$tlp_pwr" = "$desired_pwr" ] && [ "$want_hz" = "$cur_hz" ]; then
        exit 0
      fi
      echo "$profile" > /tmp/platform-profile-last
      # Sync TLP mode with platform profile (phantom AC0 fools TLP)
      [ -n "$desired_pwr" ] && [ "$tlp_pwr" != "$desired_pwr" ] && {
      case "$profile" in
        quiet)
          sudo -n /run/current-system/sw/bin/tlp bat >/dev/null 2>&1 || true
          ;;
        performance|balanced)
          sudo -n /run/current-system/sw/bin/tlp ac >/dev/null 2>&1 || true
          ;;
      esac
      }
      # Backstop: enforce CPU state matching profile (handler owns transitions;
      # this only corrects drift from tlp-auto/asusd/manual races).
      if [ "$profile" = "performance" ] || [ "$profile" = "balanced" ]; then
        NT=$(cat /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null)
        MP=$(cat /sys/devices/system/cpu/intel_pstate/max_perf_pct 2>/dev/null)
        if [ "$NT" != "0" ] || [ "$MP" != "100" ]; then
          echo 0 | sudo -n /run/current-system/sw/bin/tee /sys/devices/system/cpu/intel_pstate/no_turbo >/dev/null 2>&1 || true
          echo 100 | sudo -n /run/current-system/sw/bin/tee /sys/devices/system/cpu/intel_pstate/max_perf_pct >/dev/null 2>&1 || true
          for c in /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq; do
            echo 5200000 | sudo -n /run/current-system/sw/bin/tee "$c" >/dev/null 2>&1 || true
          done
          for c in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
            echo performance | sudo -n /run/current-system/sw/bin/tee "$c" >/dev/null 2>&1 || true
          done
          for c in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
            echo performance | sudo -n /run/current-system/sw/bin/tee "$c" >/dev/null 2>&1 || true
          done
        fi
      elif [ "$profile" = "quiet" ]; then
        # Battery powersave: cap CPU at 20% / 2.6GHz / no turbo.
        NT=$(cat /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null)
        MP=$(cat /sys/devices/system/cpu/intel_pstate/max_perf_pct 2>/dev/null)
        GOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)
        if [ "$NT" != "1" ] || [ "$MP" != "20" ] || [ "$GOV" != "powersave" ]; then
          echo 1 | sudo -n /run/current-system/sw/bin/tee /sys/devices/system/cpu/intel_pstate/no_turbo >/dev/null 2>&1 || true
          echo 20 | sudo -n /run/current-system/sw/bin/tee /sys/devices/system/cpu/intel_pstate/max_perf_pct >/dev/null 2>&1 || true
          for c in /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq; do
            echo 2600000 | sudo -n /run/current-system/sw/bin/tee "$c" >/dev/null 2>&1 || true
          done
          for c in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
            echo powersave | sudo -n /run/current-system/sw/bin/tee "$c" >/dev/null 2>&1 || true
          done
          for c in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
            echo power | sudo -n /run/current-system/sw/bin/tee "$c" >/dev/null 2>&1 || true
          done
        fi
      fi
      # Find Hyprland instance — connect-test each candidate: a stale sig
      # dir (crashed/killed Hyprland) still contains its .socket.sock file,
      # and alphabetical order can pick it, making every hyprctl call fail.
      sig=""
      for d in /run/user/1000/hypr/*/; do
        s=$(basename "$d" 2>/dev/null) || continue
        if ${pkgs.hyprland}/bin/hyprctl --instance "$s" monitors -j >/dev/null 2>&1; then
          sig=$s; break
        fi
      done
      [ -z "$sig" ] && exit 0
      export XDG_RUNTIME_DIR=/run/user/1000
      export HYPRLAND_INSTANCE_SIGNATURE=$sig
      pos=$(${pkgs.hyprland}/bin/hyprctl monitors -j | ${pkgs.jq}/bin/jq -r '.[] | select(.name == "eDP-1") | "\(.x)x\(.y)"' 2>/dev/null || true)
      scale=$(${pkgs.hyprland}/bin/hyprctl monitors -j | ${pkgs.jq}/bin/jq -r '.[] | select(.name == "eDP-1") | .scale' 2>/dev/null || true)
      tr=$(${pkgs.hyprland}/bin/hyprctl monitors -j | ${pkgs.jq}/bin/jq -r '.[] | select(.name == "eDP-1") | .transform // 0' 2>/dev/null || true)
      [ -z "$pos" ] && pos="0x0"
      [ -z "$scale" ] && scale="1"
      # Refresh-rate drift gate: re-assert Hz even when profile hasn't changed
      # (config reload / monitor hotplug can reset Hz to the static 240 rule)
      case "$profile" in
        quiet) want_hz=60 ;;
        performance|balanced) want_hz=240 ;;
        *) want_hz="" ;;
      esac
      cur_hz=$(${pkgs.hyprland}/bin/hyprctl monitors -j | ${pkgs.jq}/bin/jq -r '.[] | select(.name == "eDP-1") | .refreshRate | floor' 2>/dev/null || true)
      if [ -n "$want_hz" ] && [ "$cur_hz" != "$want_hz" ]; then
      case "$profile" in
        quiet)
          ${pkgs.hyprland}/bin/hyprctl eval 'hl.monitor({ output = "eDP-1", mode = "2560x1600@60", position = "'"$pos"'", scale = '"$scale"', transform = '"$tr"' })' 2>/dev/null || true
          ;;
        performance|balanced)
          ${pkgs.hyprland}/bin/hyprctl eval 'hl.monitor({ output = "eDP-1", mode = "2560x1600@240", position = "'"$pos"'", scale = '"$scale"', transform = '"$tr"' })' 2>/dev/null || true
          ;;
      esac
      fi
    '';
  };
  environment.sessionVariables.SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
  # Force ELAN9008 touchscreen to direct-touch mode (fixes PROP=2 pointer behavior)
  environment.etc."libinput/local-overrides.quirks".text = ''
    [ASUS ROG Flow X16 ELAN9008 Touchscreen]
    MatchName=ELAN9008:00 04F3:2FC4
    MatchBus=i2c
    AttrInputProp=-INPUT_PROP_POINTER;+INPUT_PROP_DIRECT
  '';
  users.users.nate.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIALyMusgG/6+Xcpa+rylU9S52jvTIgjTSpla0CKbe2uR nate@home"
  ];
  networking.hostName = "flow";

  # Tailscale: always-on default. systemd-tailscaled doesn't set WantRunning,
  # so a oneshot enforces it at boot (idempotent; auth only if needed).
  services.tailscale.enable = true;
  systemd.services.tailscale-up = {
    description = "Ensure tailscale is up (WantRunning=true)";
    after = [ "tailscaled.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.tailscale}/bin/tailscale up";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
  services.hermes-agent = {
    enable = true;
    addToSystemPackages = true;
    environmentFiles = [ "/var/lib/hermes/env" ];
    # FIX 2026-09-04: hermes-agent input v2026.8.31 (v0.21.0) shipped broken —
    # hermes_state.py does a top-level `import hermes_state_holders`, but that
    # file is absent from the tag (landed upstream on main Sep 2 as 5e01b8fa).
    # Without it every SessionDB path fails: `sessions list/browse/stats`,
    # in-session /resume and /sessions (empty), and new chats run unindexed.
    # Workaround: vendor that exact upstream file (blob 9f4176d4, stdlib-only)
    # and inject it via the module's extraPythonPackages PYTHONPATH hook.
    # REMOVE this once the hermes-agent input moves to a tag containing
    # hermes_state_holders.py (check: file exists at the input's repo root).
    # NOTE: a pre-existing uncommitted input bump to 13939699 (which contains
    # the file) is stashed, not lost: `git stash list`.
    extraPythonPackages = [
      (pkgs.python312Packages.buildPythonPackage {
        pname = "hermes-state-holders";
        version = "0.21.0+fix1";
        format = "other";
        src = ../../modules/nixos/hermes-state-holders.py;
        dontUnpack = true;
        dontBuild = true;
        dontConfigure = true;
        installPhase = ''
          mkdir -p $out/${pkgs.python312.sitePackages}
          cp $src $out/${pkgs.python312.sitePackages}/hermes_state_holders.py
        '';
      })
    ];
    settings = {
      toolsets = [ "all" ];
      max_turns = 100;
      terminal = { backend = "local"; cwd = "."; timeout = 180; };
      compression = {
        enabled = true;
        threshold = 0.85;
        summary_model = "DeepSeek/deepseek-v4-flash";
      };
      memory = {
        memory_enabled = true;
        user_profile_enabled = true;
      };
      display = { compact = false; personality = null; };
    };
  };
  systemd.tmpfiles.rules = [
    "d /var/lib/hermes 0750 hermes hermes -"
    "d /var/lib/hermes/.hermes 0750 hermes hermes -"
    "d /etc/asusd 0755 root root -"
  ];
  # Docker container runtime - socket activation: daemon stays dead until the
  # first docker command hits /var/run/docker.sock (idle battery: no dockerd +
  # containerd resident, ~245MB RAM saved). docker CLI works unchanged.
  virtualisation.docker = {
    enable = true;
    enableOnBoot = false;
    # autoPrune runs `docker system prune -f` PLUS `docker volume prune
    # --force --all` on a TIMER (not on login), so it fires unattended and
    # `volume prune --all` deletes every unused volume -- including the
    # dockur/windows disk image backing the WinBoat VM. Re-enable only when
    # no long-lived stateful container volumes are in use.
    autoPrune.enable = false;
  };
  specialisation."battery".configuration = {
    boot.loader.grub.configurationName = lib.mkForce "Battery";
    # Override rapl-reset for battery: force 20W MMIO regardless of AC detection
    systemd.services.rapl-reset = lib.mkForce {
      description = "Set package RAPL limit to 20W (battery)";
      after = [ "multi-user.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig.Type = "oneshot";
      serviceConfig.ExecStart = pkgs.writeShellScript "rapl-reset-battery" ''
        echo 20000000 > /sys/class/powercap/intel-rapl-mmio:0/constraint_0_power_limit_uw 2>/dev/null || true
        echo 20000000 > /sys/class/powercap/intel-rapl-mmio:0/constraint_1_power_limit_uw 2>/dev/null || true
        echo 20000000 > /sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw 2>/dev/null || true
      '';
    };
    system.nixos.tags = [ "Battery" ];
    boot.blacklistedKernelModules = lib.mkForce [ "nouveau" "nvidia" "nvidia_drm" "nvidia_modeset" "nvidia_uvm" ];
    boot.kernelModules = lib.mkForce [ "iwlwifi" ];
    boot.initrd.kernelModules = lib.mkForce [ ];
    boot.kernelParams = lib.mkForce [ "modprobe.blacklist=nvidia" "quiet" "systemd.show_status=true" ];
    systemd.services.nvidia-powerd.enable = lib.mkForce false;
    services.udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x03[0-9]*", ATTR{power/control}="auto", ATTR{remove}="1"
      ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x040300", ATTR{power/control}="auto", ATTR{remove}="1"
    '';
    services.xserver.videoDrivers = lib.mkForce [ "modesetting" ];
    hardware.nvidia.nvidiaPersistenced = lib.mkForce false;
    systemd.services.block-bluetooth = {
      description = "Block Bluetooth via rfkill on battery";
      after = [ "multi-user.target" ];
      wantedBy = [ "multi-user.target" ];
      script = "${pkgs.util-linux}/bin/rfkill block bluetooth";
      serviceConfig.Type = "oneshot";
    };
  };

}
