{ ... }: {
  # Pi coding agent TUI config.
  #
  # pi resolves its config dir via getAgentDir() = $PI_CODING_AGENT_DIR or
  # ~/.pi/agent. It does NOT read ~/.config/pi/agent, which is where
  # xdg.configFile deployed these files — so every entry below was inert until
  # it moved to home.file. Verified: XDG_CONFIG_HOME is unset.
  #
  # settings.json is deliberately NOT managed. pi rewrites it at runtime (model,
  # thinking level, enabled models, lastChangelogVersion), so a forced copy would
  # silently revert those choices on every rebuild. It lives at
  # ~/.pi/agent/settings.json and is pi's to own. Its intended contents are
  # documented in ~/.pi-rollback-0.83.md.
  home.file.".pi/agent/APPEND_SYSTEM.md" = {
    force = true;
    text = ''
# Interaction preference
- Before executing any state-changing action (file edits, installs, git
  operations, system/config changes, deletions), state the intent and wait
  for explicit approval.
- Default to proposing and asking rather than acting — even when the
  request sounds like a directive — unless the action was already approved.
- Research, reading, and read-only lookups need no confirmation.
    '';
  };

  home.file.".pi/agent/keybindings.json" = {
    force = true;
    text = builtins.toJSON {
      "app.message.copy" = [];
      "app.models.clearAll" = [];
    };
  };

  # Deployed from the file rather than inlined so the managed copy is exactly
  # what pi-zentui had written at ~/.pi/agent/zentui.json — the previous inline
  # block had drifted behind it. (pi-zentui is not in the packages list, so this
  # is currently inert; it is kept for when it is re-enabled.)
  home.file.".pi/agent/zentui.json" = {
    force = true;
    source = ./pi-zentui.json;
  };
}
