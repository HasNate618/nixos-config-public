# Hyprland 0.56.2 tracking nixpkgs unstable + the special-workspace patch.
#
# WHY no 0.55.4 pin: the foot transparent-background blur regression that
# motivated it was fixed upstream in commit 6a8c7613 (PR #14639), which
# landed IN 0.56.0 itself. foot.ini needs `blur = yes` under [colors-dark]
# to opt into ext-background-effect-v1 (a client-side setting on 0.56+).
#
# ── aquamarine: override the src to the rev upstream pairs with 0.56.2 ──
#
# WHY: nixpkgs ships hyprland 0.56.2 built against aquamarine TAG v0.14.0,
# but upstream Hyprland 0.56.2's own flake.lock pins aquamarine commit
# 1a10fe26a9f7 (a post-v0.14.0 commit). Tag v0.14.0 lacks the fix for the
# stranded page-flip that wedges the eDP panel after an idle DPMS-off:
#
#   drm: Modesetting eDP-1 with 2560x1600@240.00Hz
#   ERR drm: Cannot commit when a page-flip is awaiting
#   ERR drm: Cannot commit when a page-flip is awaiting
#
# Mechanism: `dpms off` powers the connector down while a page-flip is in
# flight, so its completion event never reaches handlePF() and the
# scheduler's in-flight flag stays set forever. Every later commit is then
# rejected -> backlight on, dpmsStatus=1, no scanout, input dead. Only a
# connector teardown/rebuild (e.g. a DPMS cycle) clears it.
#
# Upstream: hyprwm/aquamarine#304 (and hyprwm/Hyprland#14521).
# Fix: invalidateFrame() -> crtc->disarmPageFlip() in applyCommit's disable
# branch. Absent in v0.12.1/v0.13.0/v0.14.0; present from 0.15.0 on.
#
# 1a10fe2 is the exact rev upstream pairs with 0.56.2, so it is ABI-matched
# by construction: SOVERSION stays 13 and CMakeLists.txt is byte-identical
# to v0.14.0 (pure src swap, no dependency change). The hash below equals
# the narHash in hyprland v0.56.2's own flake.lock.
#
# Drop this override once nixpkgs ships aquamarine >= 0.15.0.

final: prev: {
  hyprland = prev.hyprland.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./hyprland-special-workspace-no-fade.patch ];
  });

  aquamarine = prev.aquamarine.overrideAttrs (old: {
    version = "0.14.0-unstable-2026-08-04";

    src = prev.fetchFromGitHub {
      owner = "hyprwm";
      repo = "aquamarine";
      rev = "1a10fe26a9f7d989c359e6a9ea61aa2e44d06c36";
      hash = "sha256-H2CrAlJD9FsUbSEIhPVK3IyVjnK0vSxPruBef17GcBs=";
    };
  });
}
