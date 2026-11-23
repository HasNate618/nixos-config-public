{ pkgs, zen-browser, ... }:

let
  zen-profile = "xxxxxxxx.Default (release)";
  zen-dir = "zen/${zen-profile}";
  ext-src = ./zen/extensions;
in
{
  home.packages = [ zen-browser ];

  # Zen matugen watcher — live transparency updates. The script
  # (bin/zen-matugen-watcher) is HM-declared via bin.nix; the unit itself
  # was previously a hand-written real file in ~/.config/systemd/user.
  systemd.user.services.zen-matugen-watcher = {
    Unit = {
      Description = "Zen Browser matugen watcher — live transparency updates";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "%h/.local/bin/zen-matugen-watcher";
      Restart = "on-failure";
      RestartSec = "3s";
      Nice = -5;
      Environment = [ "PYTHONUNBUFFERED=1" ];
    };
    Install = { WantedBy = [ "default.target" ]; };
  };

  xdg.configFile = {
    "${zen-dir}/chrome/userChrome.css" = { source = ./zen/userChrome.css; force = true; };
    "${zen-dir}/chrome/userContent.css" = { source = ./zen/userContent.css; force = true; };
    "${zen-dir}/chrome/colors.css" = { source = ./zen/colors.css; force = true; };
    "${zen-dir}/chrome/JS/matugen-live.uc.js" = { source = ./zen/matugen-live.uc.js; force = true; };
    "${zen-dir}/user.js" = { source = ./zen/user.js; force = true; };
    "${zen-dir}/chrome/zen-themes.css" = { source = ./zen/zen-themes.css; force = true; };
    "${zen-dir}/chrome/zen-themes/sameerasw/chrome.css" = { source = ./zen/zen-themes/sameerasw/chrome.css; force = true; };
    "${zen-dir}/chrome/zen-themes/sameerasw/preferences.json" = { source = ./zen/zen-themes/sameerasw/preferences.json; force = true; };
    "${zen-dir}/zen-keyboard-shortcuts.json" = { source = ./zen/zen-keyboard-shortcuts.json; force = true; };

    # Extensions
  } // builtins.listToAttrs (map (name: {
    inherit name;
    value = { source = ext-src + "/${name}"; force = true; };
  }) [
    "zen-internet.xpi"
    "uBlock0@raymondhill.net.xpi"
    "firefox@tampermonkey.net.xpi"
    "addon@darkreader.org.xpi"
    "side-view@mozilla.org.xpi"
    "savewebpas@jeffersonscher.com.xpi"
    "chrome-gnome-shell@gnome.org.xpi"
    # Bitwarden ({446900e4-...}.xpi, 18MB) is omitted from this public repo.
    "{762f9885-5a13-4abd-9c77-433dcd38b8fd}.xpi"
    "{7a7a4a92-a2a0-41d1-9fd7-1e92480d612d}.xpi"
    "{91aa3897-2634-4a8a-9092-279db23a7689}.xpi"
    "{a2d60e98-41cf-4c8a-bd31-ed27352ec0d3}.xpi"
  ]);
}
