# wl-kbptr override: build from sophronesis fork that fixes pointer placement
# on rotated outputs under Hyprland (moverest/wl-kbptr#53).
# Upstream Hyprland handles wlr-virtual-pointer coordinates differently from
# wlroots on rotated outputs; the client-side transform causes double-applied
# rotation. The fork skips _apply_transform when XDG_CURRENT_DESKTOP=Hyprland.
self: super: {
  wl-kbptr = super.wl-kbptr.overrideAttrs (old: {
    version = "0.4.1-hyprland-fix";
    src = super.fetchFromGitHub {
      owner = "sophronesis";
      repo = "wl-kbptr";
      rev = "fix/hyprland-rotated-output-transform";
      hash = "sha256-3ZslBKCQ5ggqe3SiCtb8/zqFvcW3htdHTTFO1GPLSwg=";
    };
    meta = old.meta // {
      description = (old.meta.description or "") + " (Hyprland rotation fix)";
    };
  });
}
