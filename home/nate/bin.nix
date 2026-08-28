# User scriptlets in ~/.local/bin — declared from ./bin so a fresh install
# reproduces the full toolchain. Sources are committed with the exec bit;
# home.file symlinks keep them read-only and in sync with git.
{ lib, ... }:

{
  home.file = lib.listToAttrs (map (name: {
    name = ".local/bin/${name}";
    value = {
      source = ./bin/${name};
      force = true; # replace any pre-existing real file (e.g. from setup scripts)
    };
  }) (builtins.attrNames (builtins.readDir ./bin)));
}
