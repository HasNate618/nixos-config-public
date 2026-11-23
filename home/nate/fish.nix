{ pkgs, ... }: {
  xdg.configFile."fish/config.fish".force = true;
  programs.fish = {
        enable = true;
    generateCompletions = false;
    # Abbreviations, NOT aliases. Two reasons:
    #   1. Agent safety by construction. home-manager emits shellAliases inside
    #      `status is-interactive`, so non-interactive `fish -c` already skipped
    #      them — but that is a side effect of the guard. Abbrs never expand in a
    #      non-interactive shell at all, so an agent running `fish -c` can never
    #      pick up `ls`->eza or `grep`->rg no matter how the guard changes.
    #   2. They expand visibly. `grep`->`rg` is NOT argument-compatible: grep -r
    #      means recursive while rg -r means --replace (needs a value), so
    #      `grep -rn foo` becomes `rg -rn foo` and fails. With an alias that
    #      breaks silently at exec; with an abbr you see the expansion on space
    #      and can catch it before hitting enter.
    shellAbbrs = {
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
      llama = "bash $HOME/AI/llama.sh $argv";
      vpn = ''
        set -l sub $argv[1]
        if test "$sub" = on
          sudo systemctl start wg-quick-nordlynx
        else if test "$sub" = off
          sudo systemctl stop wg-quick-nordlynx
        else if test "$sub" = status
          if ip link show nordlynx >/dev/null 2>&1
            echo "nordlynx: UP"
            sudo wg show nordlynx
          else
            echo "nordlynx: DOWN"
          end
        else
          if ip link show nordlynx >/dev/null 2>&1
            echo "nordlynx is up — disabling..."
            sudo systemctl stop wg-quick-nordlynx
          else
            echo "nordlynx is down — enabling..."
            sudo systemctl start wg-quick-nordlynx
          end
        end
      '';
    };
  };
}
