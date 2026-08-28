{ ... }: {
  # SSH config for home (tailnet: home.tailXXXXXXXX.ts.net)
  programs.ssh = {
    enableDefaultConfig = false;
    enable = true;
    settings = {
      # Fail-fast on dead/unreachable peers: ssh clients caught mid-connect()
      # during shutdown (agent exit hooks doing git-over-ssh, log streams) used
      # to ignore SIGTERM until the kernel connect timeout expired (~2 min),
      # stalling every reboot/shutdown for the full 90s stop-job timeout.
      "*" = {
        ConnectTimeout = 5;
        ServerAliveInterval = 15;
        ServerAliveCountMax = 3;
      };
      forgejo = {
        hostname = "home.tailXXXXXXXX.ts.net";
        port = 2222;
        user = "git";
        identityFile = "~/.ssh/gitea";
      };
      home = {
        hostname = "home.tailXXXXXXXX.ts.net";
        user = "nate";
        identityFile = "~/.ssh/id_ed25519";
      };
    };
  };
}
