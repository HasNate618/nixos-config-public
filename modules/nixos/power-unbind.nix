{ pkgs, ... }: {
  # Unbind PNP0C0C (power button) from ACPI button driver at boot
  # so the kernel doesn't directly trigger shutdown.
  # Lid switch (PNP0C0D) stays bound and works normally.
  systemd.services.unbind-power-button = {
    description = "Unbind ACPI power button from kernel button driver";
    wantedBy = [ "multi-user.target" ];
    after = [ "sysinit.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "unbind-power-button" ''
        # Wait for the button driver to initialize
        sleep 1
        # Unbind PNP0C0C (power button) only
        for dir in /sys/bus/acpi/drivers/button/PNP0C0C:*/; do
          [ -d "$dir" ] || continue
          name=$(basename "$dir")
          echo "$name" > /sys/bus/acpi/drivers/button/unbind 2>/dev/null && \
            echo "Unbound $name" || echo "Failed to unbind $name"
        done
      '';
    };
  };

  # Disable non-essential ACPI wake sources so nothing wakes the machine
  # while sleeping with the lid closed (bag safety): power button GPE,
  # RTC alarm, dGPU root port. USB/Thunderbolt wake left enabled (the
  # re-suspend guard below covers accidental wakes from plugged devices).
  systemd.services.disable-wake-sources = {
    description = "Disable non-essential ACPI wake sources";
    wantedBy = [ "multi-user.target" ];
    after = [ "unbind-power-button.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      # Power button wake — disable if the sysfs control exists
      if [ -w /sys/devices/platform/PNP0C0C:00/power/wakeup ]; then
        echo disabled > /sys/devices/platform/PNP0C0C:00/power/wakeup || true
      fi
      # /proc/acpi/wakeup entries — toggle off only if currently enabled
      for dev in AWAC PEG1; do
        if grep -q "^$dev[[:space:]]" /proc/acpi/wakeup 2>/dev/null; then
          if grep "^$dev" /proc/acpi/wakeup | grep -q '\*enabled'; then
            echo "$dev" > /proc/acpi/wakeup || true
          fi
        fi
      done
    '';
  };

  # Re-suspend guard: if the machine wakes with the lid closed on battery
  # (accidental side power-button press in a bag), go back to sleep after
  # 3s. Skipped if on AC (intentional desk use) or lid open. Loop-guarded:
  # only one re-suspend per 60s window.
  systemd.services."systemd-suspend".serviceConfig.ExecStartPost = [
    ""
    (pkgs.writeShellScript "lid-resuspend-guard" ''
      status=$(cat /sys/class/power_supply/BAT0/status 2>/dev/null)
      [ "$status" = "Discharging" ] || exit 0
      case "$(cat /proc/acpi/button/lid/LID/state 2>/dev/null)" in
        *closed*) ;;
        *) exit 0 ;;
      esac
      marker=/run/lid-resuspend-guard
      now=$(date +%s)
      [ -f "$marker" ] && [ $((now - $(cat "$marker" 2>/dev/null))) -lt 60 ] && exit 0
      echo "$now" > "$marker"
      systemd-run --on-active=3 --unit=relid-resuspend systemctl suspend || true
    '')
  ];
}
