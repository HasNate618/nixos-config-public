{ ... }: {
  services.openssh.enable = true;

  # Rate-limit SSH brute-force attempts
  services.fail2ban.enable = true;
}
