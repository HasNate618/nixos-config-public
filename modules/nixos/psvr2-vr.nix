{ config, lib, pkgs, ... }:
let
  # Beyley's Monado fork with PSVR2 HMD driver + 6DOF controller support
  # Branch: psvr2-work-steamvr (last commit: 2026-06-04)
  monado-psvr2 = pkgs.monado.overrideAttrs (oldAttrs: {
    pname = "monado-psvr2";
    version = "psvr2-work-steamvr-2026-06-04";
    src = pkgs.fetchFromGitLab {
      domain = "gitlab.freedesktop.org";
      owner = "Beyley";
      repo = "monado";
      rev = "47f9d39e686d6bbd7dad914b4dbe21f784c41911";
      hash = "sha256-APEA1ivUGTrchePh1XJXycxB9/IRze7ltCPH0qkvAE4=";  # Replace with real hash on first build
    };
    # PSVR2 driver needs additional deps
    buildInputs = (oldAttrs.buildInputs or []) ++ (with pkgs; [
      hidapi
      libuvc
      libjpeg
    ]);
    # Remove nixpkgs patches that won't apply to this fork
    patches = [];
    cmakeFlags = lib.remove "-DXRT_HAVE_STEAM:BOOL=TRUE" (oldAttrs.cmakeFlags or []);
  });
in {
  services.monado = {
    enable = true;
    package = monado-psvr2;
    defaultRuntime = true;
  };

  environment.systemPackages = with pkgs; [
    opencomposite    # OpenVR -> OpenXR bridge for SteamVR games
    xrizer           # OpenVR module for Monado (better than opencomposite for SteamVR)
  ];

  # OpenVR paths — tell SteamVR games to use xrizer via OpenComposite
  home-manager.users.nate.xdg.configFile."openvr/openvrpaths.vrpath".text =
    let steam = "/home/nate/.local/share/Steam";
    in builtins.toJSON {
      version = 1;
      jsonid = "vrpathreg";
      external_drivers = null;
      config = [ "${steam}/config" ];
      log = [ "${steam}/logs" ];
      runtime = [
        "${pkgs.xrizer}/lib/xrizer"
      ];
    };

  # Monado service environment for NVIDIA
  systemd.user.services.monado.environment = {
    # Workaround for NVIDIA DRM lease latency (bug 5372097)
    U_PACING_COMP_MIN_TIME_MS = "5";
    # Use compute compositor
    XRT_COMPOSITOR_COMPUTE = "true";
    # Force NVIDIA Vulkan driver for headset display
    VK_DRIVER_FILES = "/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json";
  };

  # Steam needs to see Monado's OpenXR runtime
  programs.steam.package = pkgs.steam.override {
    extraProfile = ''
      export PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1
    '';
  };
}
