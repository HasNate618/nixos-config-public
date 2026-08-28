{ pkgs, ... }: {
  xdg.configFile."fish/config.fish".force = true;
  programs.fish = {
        enable = true;
    generateCompletions = false;
    shellAliases = {
      ls = "eza --icons";
      ll = "eza -l --icons";
      la = "eza -la --icons";
      lt = "eza -T --icons";
      grep = "rg";
      find = "fd";
      vim = "nvim";
      vi = "nvim";
      p = "python";
      g = "lazygit";
      d = "lazydocker";
      co = "copilot";
      c = "opencode --continue";
      t = "tmux new-session -A -s main";
      hw = "herdr --session work";
      hd = "herdr --session dev";
      rb = "nixos-safe-rebuild";
      n = "nvim";
    };

    shellInit = ''
      fish_add_path --prepend --move "$HOME/.local/bin"
      set -gx HERMES_HOME "/home/nate/.hermes"
      fish_add_path --append --move "$HOME/.cargo/bin"
    '';

    interactiveShellInit = ''
      zoxide init fish | source
      fzf --fish | source
      starship init fish | source
    '';

    functions = {
      fish_greeting = "";
      llama = "bash /home/nate/AI/llama.sh $argv";
      vpn = ''
        set -l sub $argv[1]
        if test -z "$sub"
          if nordvpn status 2>/dev/null | string match -qi '*Connected*'
            echo "nordvpn up -> disconnecting..."
            nordvpn disconnect
          else
            echo "nordvpn down -> connecting..."
            nordvpn connect
          end
        else if test "$sub" = on
          nordvpn connect
        else if test "$sub" = off
          nordvpn disconnect
        else if test "$sub" = status
          nordvpn status
        else
          echo "usage: vpn [on|off|status]"
          return 1
        end
      '';
    };
  };
}
