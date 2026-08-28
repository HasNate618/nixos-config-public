# Killer E2200 NIC — alx driver PHY bug workaround
# The alx driver randomly drops to 10 Mbps after link disturbances.
# This service checks every 5 minutes and reloads the driver if speed < 1000 Mbps.
{ pkgs, ... }:
{
  systemd.services.alx-fix-speed = {
    description = "Fix Killer E2200 NIC speed (reload alx driver if < 1 Gbps)";
    # modprobe (kmod) + logger (util-linux) are NOT in systemd's minimal PATH
    path = with pkgs; [ kmod util-linux ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "alx-fix-speed" ''
        SPEED=$(cat /sys/class/net/enp13s0/speed 2>/dev/null)
        if [ "$SPEED" != "1000" ]; then
          logger -t alx-fix "NIC speed is $SPEED Mbps, reloading alx driver"
          modprobe -r alx
          modprobe alx
          logger -t alx-fix "alx driver reloaded, new speed: $(cat /sys/class/net/enp13s0/speed 2>/dev/null) Mbps"
        fi
      '';
      TimeoutSec = 10;
    };
  };

  systemd.timers.alx-fix-speed = {
    description = "Check NIC speed every 5 minutes";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*:0/5";
      Persistent = true;
    };
  };
}
