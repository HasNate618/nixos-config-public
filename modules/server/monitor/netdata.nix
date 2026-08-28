# Netdata — Real-time system metrics + alerting
# Native NixOS module, port 19999 (localhost only, behind Caddy)
{ pkgs, lib, config, ... }:

{
  services.netdata = {
    enable = true;
    config = {
      global = {
        "running config" = "/etc/netdata/netdata.conf";
        "process scheduling policy" = "idle";
        "process scheduling priority" = 10;
        "OOM score" = 1000;
        "memory mode" = "dbengine";
        "page cache size" = 32;
        "dbengine disk space" = 256;
        "dbengine multihost disk space" = 256;
        "update every" = 1;
        "history" = 3600;
        "error log" = "/var/log/netdata/error.log";
        "access log" = "/var/log/netdata/access.log";
        "debug log" = "/var/log/netdata/debug.log";
      };
      web = {
        "bind to" = "127.0.0.1:19999";
        "allow connections from" = "localhost 172.16.0.0/12 192.168.0.0/16 10.0.0.0/8";
        "allow dashboard from" = "localhost 172.16.0.0/12 192.168.0.0/16 10.0.0.0/8";
        "allow badges from" = "localhost 172.16.0.0/12 192.168.0.0/16 10.0.0.0/8";
        "allow management from" = "localhost 172.16.0.0/12 192.168.0.0/16 10.0.0.0/8";
      };
      plugins = {
        "path.d" = "${pkgs.netdata}/libexec/netdata/plugins.d";
      };
      health = {
        "enabled" = "yes";
        "script to run on alarm" = "${pkgs.netdata}/libexec/netdata/plugins.d/alarm-notify.sh";
      };
    };
    # Enable SMART monitoring for disk health
  };

  # Open firewall for Netdata (local network only)
  networking.firewall.allowedTCPPorts = [ 19999 ];
}
