{ pkgs, ... }: {
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    shellAliases = {
      ls = "eza --icons";
      ll = "eza -l --icons";
      la = "eza -la --icons";
      lt = "eza -T --icons";
      cat = "bat";
      grep = "rg";
      find = "fd";
      vim = "nvim";
      vi = "nvim";
      p = "python";
      g = "lazygit";
      c = "opencode --continue";
      t = "tmux new-session -A -s main";
      n = "nvim";
    };
    initContent = ''
      eval "$(zoxide init zsh)"
      eval "$(fzf --zsh)"

      # yazi: cd to last visited dir on quit
      y() {
        local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" yazi_cmd="$@"
        yazi "$yazi_cmd" --cwd-file="$tmp"
        if [ -f "$tmp" ] && [ "$(cat "$tmp")" != "$(pwd)" ]; then
          cd "$(cat "$tmp")"
        fi
        rm -f "$tmp"
      }
      eval "$(starship init zsh)"

      export PATH="$HOME/.local/bin:$PATH"
      export PATH="$PATH:$HOME/.cargo/bin"

      HISTSIZE=10000
      HISTFILESIZE=20000
      export HERMES_HOME="$HOME/.hermes"
      SAVEHIST=10000
      setopt SHARE_HISTORY
    '';
  };
}
