{ pkgs, zen-browser, ... }:

let
  zen-profile = "7khcdo47.Default (release)";
in
{
  home.packages = [ zen-browser ];

  xdg.configFile = {
    "zen/${zen-profile}/chrome/userChrome.css" = {
      source = ./zen/userChrome.css;
      force = true;
    };
    "zen/${zen-profile}/chrome/userContent.css" = {
      source = ./zen/userContent.css;
      force = true;
    };
    "zen/${zen-profile}/user.js" = {
      source = ./zen/user.js;
      force = true;
    };
  };
}
