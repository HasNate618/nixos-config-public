# sops-nix — secrets management for the homelab
{ pkgs, lib, config, sopsFile, ... }:

{
  environment.systemPackages = with pkgs; [
    sops
    age
  ];

  sops = {
    defaultSopsFile = sopsFile;
    age.keyFile = "/root/.config/sops/age/keys.txt";
    secrets = {
      "postgres-immich-password" = {};
      "postgres-nextcloud-password" = {};
      "postgres-forgejo-password" = {};
      "redis-password" = {};
      "samba-password" = {};
      "nordvpn-api-key" = {};
      "nordvpn-user" = {};
      "nordvpn-pass" = {};
      "tailscale-api-key" = {};
      "crowdsec-api-key" = {};
      "open-terminal-api-key" = {};
      "crawl4ai-api-token" = {};
      "exa-api-key" = {};
      "exa-api-key-secondary" = {};
      "nextcloud-admin-pass" = {};
      "searxng-secret-key" = {};
      "cohere-api-key" = {};
      "lunar-admin-token" = {};
      "lunar-auth-secret" = {};
    };
  };
}
