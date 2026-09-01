{ ... }: {
  # herdr terminal multiplexer config
  xdg.configFile."herdr/config.toml" = {
    force = true;
    text = ''
      onboarding = false

      [theme]
      name = "terminal"

      [theme.custom]
      panel_bg = "reset"

      [keys]
      prefix = "ctrl+a"

      # Splits - empty so herdr-navigator can own them via [[keys.command]]
      split_vertical = ""
      split_horizontal = ""

      # Pane focus — prefix+hjkl only (alt+arrows removed)
      focus_pane_left = "prefix+h"
      focus_pane_down = "prefix+j"
      focus_pane_up = "prefix+k"
      focus_pane_right = "prefix+l"

      # Tab switching
      switch_tab = "alt+1..9"

      # Tab management
      new_tab = "prefix+c"
      close_tab = "prefix+shift+x"
      rename_tab = ""
      previous_tab = "prefix+p"
      next_tab = "prefix+n"

      # Workspace management
      goto = "prefix+s"
      new_workspace = "prefix+shift+n"
      close_workspace = "prefix+shift+d"

      # Pane management
      close_pane = "prefix+x"
      zoom = "prefix+z"
      resize_mode = "prefix+r"
      copy_mode = "prefix+["

      # UI
      toggle_sidebar = "prefix+space"
      settings = "prefix+,"
      help = "prefix+?"
      detach = "prefix+q"

      # Herdr-navigator: ctrl+hjkl seamless nvim <-> herdr navigation
      [[keys.command]]
      key = "ctrl+h"
      type = "shell"
      command = "herdr-navigator dispatch left"
      description = "navigate left (nvim/herdr)"

      [[keys.command]]
      key = "ctrl+j"
      type = "shell"
      command = "herdr-navigator dispatch down"
      description = "navigate down (nvim/herdr)"

      [[keys.command]]
      key = "ctrl+k"
      type = "shell"
      command = "herdr-navigator dispatch up"
      description = "navigate up (nvim/herdr)"

      [[keys.command]]
      key = "ctrl+l"
      type = "shell"
      command = "herdr-navigator dispatch right"
      description = "navigate right (nvim/herdr)"

      # Splits via navigator (keeps layout cache fresh)
      [[keys.command]]
      key = "prefix+v"
      type = "shell"
      command = "herdr-navigator split right"
      description = "split vertical"

      [[keys.command]]
      key = "prefix+-"
      type = "shell"
      command = "herdr-navigator split down"
      description = "split horizontal"

      # herdr-nvim: IDE sidebar + picker (prefix+e for nvim, left side)
      [[keys.command]]
      key = "prefix+e"
      type = "plugin_action"
      command = "chmarax.herdr-nvim.toggle"
      description = "nvim sidebar (herdr-nvim)"

      [[keys.command]]
      key = "prefix+o"
      type = "plugin_action"
      command = "chmarax.herdr-nvim.pick-file"
      description = "pick file from agent output"

      [ui.toast]
      delivery = "system"
      delay_seconds = 1

      [ui.toast.herdr]
      position = "bottom-right"

      [ui.sound]
      enabled = true

      [experimental]
      pane_history = true

      [ui]
      show_agent_labels_on_pane_borders = false
      agent_panel_sort = "spaces"
    '';
  };

  # herdr-nvim plugin config
  xdg.configFile."herdr-nvim/config.toml" = {
    force = true;
    text = ''
      [sidebar]
      nvim_bin = "nvim"
      position = "left"

      [picker]
      scan_lines = 300
      max_files = 20
    '';
  };
}
