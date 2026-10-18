{ config, lib, pkgs, ... }:
{
  systemd.services.thermal-snap = {
    description = "Periodic thermal snapshot logger";
    after = [ "nvidia-persistenced.service" ];
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "15s";
      ExecStart = pkgs.writeShellScript "thermal-snap" ''
        export PATH="${config.hardware.nvidia.package}/bin:${pkgs.coreutils}/bin:${pkgs.procps}/bin:$PATH"
        export LD_LIBRARY_PATH="${config.hardware.nvidia.package}/lib:$LD_LIBRARY_PATH"
        LOG=/var/log/thermal-snap.log
        TS=$(date '+%Y-%m-%d %H:%M:%S')

        # CPU temp
        TCPU_C=""
        for d in /sys/class/thermal/thermal_zone*/; do
          t=$(cat "$d/type" 2>/dev/null)
          case "$t" in x86_pkg_temp|TCPU)
            v=$(cat "$d/temp" 2>/dev/null)
            TCPU_C=$(( v / 1000 ))
            break;;
          esac
        done

        # GPU temp + power (with timeout to avoid hanging)
        GPU_T="?"; GPU_W="?"
        if GPU_LINE=$(timeout 8 nvidia-smi --query-gpu=temperature.gpu,power.draw --format=csv,noheader 2>/dev/null); then
          GPU_T=$(echo "$GPU_LINE" | cut -d',' -f1 | tr -d ' ')
          GPU_W=$(echo "$GPU_LINE" | cut -d',' -f2 | tr -d ' W')
        fi

        # Fan speeds (pure shell)
        FANS=""
        for f in /sys/class/hwmon/hwmon*/fan*_input; do
          v=$(cat "$f" 2>/dev/null)
          [ -n "$FANS" ] && FANS="$FANS/"
          FANS="$FANS$v"
        done

        # CPU freq (avg, pure shell)
        SUM=0; N=0
        for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq; do
          v=$(cat "$f" 2>/dev/null) || continue
          SUM=$(( SUM + v ))
          N=$(( N + 1 ))
        done
        [ "$N" -gt 0 ] && FREQ=$(( SUM / N / 1000 )) || FREQ="?"

        AC=$(cat /sys/class/power_supply/AC0/online 2>/dev/null || echo "?")
        PROF=$(cat /sys/devices/platform/asus-nb-wmi/platform-profile 2>/dev/null || echo "?")

        printf '%s | CPU:%s°C GPU:%s°C GPU_Power:%sW | Fans:%s | Freq:%sMHz AC:%s Profile:%s\n' \
          "$TS" "$TCPU_C" "$GPU_T" "$GPU_W" "$FANS" "$FREQ" "$AC" "$PROF" >> "$LOG"
      '';
    };
  };

  systemd.timers.thermal-snap = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "30s";
      OnUnitActiveSec = "30s";
      AccuracySec = "5s";
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/log 0755 root root -"
  ];
}
