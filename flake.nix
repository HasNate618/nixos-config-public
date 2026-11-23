{
  description = "Nate's NixOS config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
    nix-cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel/release";
    hermes-agent.url = "github:NousResearch/hermes-agent?ref=v2026.8.31";
    zen-browser.url = "github:youwen5/zen-browser-flake/20195bc99e82";
    zen-browser.inputs.nixpkgs.follows = "nixpkgs";
    skwd-wall = {
      url = "github:liixini/skwd-wall/nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zen-pdf-viewer.url = "github:HasNate618/zen-pdf-viewer";
    zen-markdown-viewer.url = "github:HasNate618/zen-markdown-viewer";
    hyprland-preview-share-picker = {
      url = "git+https://github.com/WhySoBad/hyprland-preview-share-picker?submodules=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    grok-bot = {
      url = "github:jordangarrison/grok-bot-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # pi upstream ships its own Nix build: source build with nodejs_22, a
    # node wrapper (so the Cursor provider's native @cursor/sdk addon loads)
    # and autoPatchelf on native prebuilds. Consuming its overlay keeps `pi`
    # a plain pkgs attribute, so modules/nixos/packages.nix is unchanged.
    pi-flake = {
      url = "github:earendil-works/pi?ref=v1.1.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, sops-nix, hermes-agent, nix-cachyos-kernel, zen-browser, skwd-wall, zen-pdf-viewer, zen-markdown-viewer, hyprland-preview-share-picker, nix-index-database, grok-bot, pi-flake, ... }: {
    nixosConfigurations = {
      flow = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          inherit (zen-pdf-viewer.packages.x86_64-linux) zen-pdf-viewer;
          inherit (zen-markdown-viewer.packages.x86_64-linux) zen-markdown-viewer;
          # skwd-wall v2: packages come from the `nix` branch release flake;
          # the suite (skwd-wall-v2/skwd-walld/skwd-paper-v2/skwd-lens) is
          # installed by the module (services.skwd-deck), no specialArg needed.
          hyprland-preview-share-picker = hyprland-preview-share-picker.packages.x86_64-linux.default;
          nix-cachyos-kernel = nix-cachyos-kernel;
          grok-bot = grok-bot.packages.x86_64-linux.default;
          pi-flake = pi-flake;
        };
        modules = [
          hermes-agent.nixosModules.default
          skwd-wall.nixosModules.default
          nix-index-database.nixosModules.default
          ./hosts/nixos
          ./modules/nixos
          home-manager.nixosModules.home-manager {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.nate = import ./home/nate;
            home-manager.extraSpecialArgs = {
              zen-browser =
                let
                  baseZen = zen-browser.packages.x86_64-linux.default;
                  mozillaCfg = nixpkgs.legacyPackages.x86_64-linux.writeText "mozilla.cfg" (
                    "// first line is a comment" +
                    "\npref(\"general.config.sandbox_enabled\", false);" +
                    "\n" +
                    (builtins.readFile ./home/nate/zen/fx-autoconfig-config.js)
                  );
                in
                nixpkgs.legacyPackages.x86_64-linux.runCommand "zen-browser-fxautoconfig" { } ''
                  cp -r ${baseZen}/ $out
                  chmod -R u+w $out

                  # 1) Install our mozilla.cfg (fx-autoconfig loader) into the app dir.
                  for d in $out/lib/zen-*/; do
                    if [ -d "$d/defaults/pref" ]; then
                      install -m 0444 ${mozillaCfg} "$d/mozilla.cfg"
                    fi
                  done

                  # 2) CRITICAL: general.config.sandbox_enabled MUST be set in a
                  #    defaults/pref/*.js file (before autoconfig runs), not inside
                  #    mozilla.cfg (which the sandbox ignores). Without this the loader
                  #    block in mozilla.cfg is skipped and no .uc.js scripts load.
                  for d in $out/lib/zen-*/defaults/pref; do
                    cat >> "$d/autoconfig.js" << 'EOF'

                  // Disable autoconfig sandbox so the fx-autoconfig loader (mozilla.cfg)
                  // can run privileged JS and register chrome://userchromejs
                  pref("general.config.sandbox_enabled", false);
                  EOF
                  done

                  # 3) Rewrite the wrapper so it launches THIS derivation, not the
                  #    original store path.
                  for w in $out/bin/zen; do
                    if [ -f "$w" ]; then
                      chmod u+w "$w"
                      sed -i "s|${baseZen}|$out|g" "$w"
                    fi
                  done
                '';
            };
          }
        ];
      };

      live-usb = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          inherit (zen-pdf-viewer.packages.x86_64-linux) zen-pdf-viewer;
          inherit (zen-markdown-viewer.packages.x86_64-linux) zen-markdown-viewer;
          hyprland-preview-share-picker = hyprland-preview-share-picker.packages.x86_64-linux.default;
          pi-flake = pi-flake;
        };
        modules = [
          "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
          ./hosts/live-usb
          ./modules/nixos/core.nix
          ./modules/nixos/hyprland.nix
          ./modules/nixos/networking.nix
          ./modules/nixos/keyd.nix
          ./modules/nixos/packages.nix
          ./modules/shared/packages.nix
          nix-index-database.nixosModules.default
          skwd-wall.nixosModules.default
          home-manager.nixosModules.home-manager {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.nate = { imports = [
              ./home/nate
              ({ lib, pkgs, ... }: {
                systemd.user.services.auto-rotate.Service.ExecStart = lib.mkForce "${pkgs.coreutils}/bin/true";
                systemd.user.services.monitor-auto-layout-rebuild.Service.ExecStart = lib.mkForce "${pkgs.coreutils}/bin/true";
              })
            ]; };
            home-manager.extraSpecialArgs = {
              zen-browser = zen-browser.packages.x86_64-linux.default;
            };
          }
        ];
      };

      home = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          sops-nix = sops-nix;
          sopsFile = ./secrets/homelab.yaml;
        };
        modules = [
          sops-nix.nixosModules.sops
          ./hosts/home
        ];
      };
    };
  };
}
