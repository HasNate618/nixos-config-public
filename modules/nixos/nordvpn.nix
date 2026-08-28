# NordVPN (NordLynx/WireGuard) client — torrenting etc.
# Tailscale stays always-on alongside: tailnet routes (100.64/10) are more
# specific than NordVPN's default-route capture, so MagicDNS/SSH keep working.
{ ... }: {
  services.nordvpn.enable = true;

  # nordvpn group = access to /run/nordvpn/nordvpnd.sock without sudo
  users.users.nate.extraGroups = [ "nordvpn" ];
}
