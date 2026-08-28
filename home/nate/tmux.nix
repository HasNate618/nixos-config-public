{ pkgs, ... }:

{
  programs.tmux = {
    enable = true;
    shell = "${pkgs.fish}/bin/fish";
    terminal = "tmux-256color";
    historyLimit = 50000;
    keyMode = "vi";
    shortcut = "Space";
    baseIndex = 1;
    aggressiveResize = true;
    extraConfig = ''
      set -g default-terminal "tmux-256color"
      set -ag terminal-overrides ",*:RGB"
      set -g mouse on
      set -g renumber-windows on
      set -g focus-events on
      set -g set-clipboard on
      set -g allow-passthrough on
      set -g detach-on-destroy off
      set -g extended-keys on
      set -g extended-keys-format csi-u
      set -sg escape-time 10

      set -g status-position top
      set -g status-interval 5
      set -g status-left-length 30
      set -g status-right-length 50
      set -g window-status-separator ""
      set -gw automatic-rename on
      set -gw automatic-rename-format '#{b:pane_current_path}'

      # Theme
      set -g status-style "bg=default,fg=default"
      set -g status-left "#[fg=black,bg=blue,bold] #S #[bg=default] "
      set -g status-right "#[fg=blue]#{?pane_in_mode,COPY ,}#{?client_prefix,PREFIX ,}#[fg=brightblack]#h "
      set -g window-status-format "#[fg=brightblack] #I:#W "
      set -g window-status-current-format "#[fg=blue,bold] #I:#W "
      set -g pane-border-style "fg=brightblack"
      set -g pane-active-border-style "fg=blue"
      set -g message-style "bg=default,fg=blue"
      set -g message-command-style "bg=default,fg=blue"
      set -g mode-style "bg=blue,fg=black"
      setw -g clock-mode-colour blue

      # Vi copy mode
      bind -T copy-mode-vi v send -X begin-selection
      bind -T copy-mode-vi y send -X copy-selection-and-cancel

      # Pane splits (same dir)
      bind h split-window -v -c "#{pane_current_path}"
      bind v split-window -h -c "#{pane_current_path}"
      bind x kill-pane

      # Alt+arrow pane navigation
      bind -n M-Left  select-pane -L
      bind -n M-Right select-pane -R
      bind -n M-Up    select-pane -U
      bind -n M-Down  select-pane -D

      # Alt+Shift+arrow resize
      bind -n M-S-Left  resize-pane -L 5
      bind -n M-S-Right resize-pane -R 5
      bind -n M-S-Up    resize-pane -U 5
      bind -n M-S-Down  resize-pane -D 5

      # Window management
      bind r command-prompt -I "#W" "rename-window -- '%%'"
      bind c new-window -c "#{pane_current_path}"
      bind k kill-window

      # Alt+number window select
      bind -n M-1 select-window -t 1
      bind -n M-2 select-window -t 2
      bind -n M-3 select-window -t 3
      bind -n M-4 select-window -t 4
      bind -n M-5 select-window -t 5
      bind -n M-6 select-window -t 6
      bind -n M-7 select-window -t 7
      bind -n M-8 select-window -t 8
      bind -n M-9 select-window -t 9

      # Session controls
      bind R command-prompt -I "#S" "rename-session -- '%%'"
      bind C new-session -c "#{pane_current_path}"
      bind K kill-session
      bind P switch-client -p
      bind N switch-client -n

      # Reload config
      bind q source-file ~/.config/tmux/tmux.conf
    '';
  };
}
