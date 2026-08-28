# Surgical opencode bump to v1.18.7 (prebuilt upstream binary, not nixpkgs source build).
# Upstream nixpkgs pinned at nixos-unstable still carries 1.15.13; this overlay
# pulls the official GitHub release tarball and patchelfs it to our Nix glibc.
# Only `opencode` is overridden — nothing else in the pkg set rebuilds.
self: super: {
  opencode = super.stdenvNoCC.mkDerivation {
    pname = "opencode";
    version = "1.18.7";

    src = super.fetchurl {
      url = "https://github.com/anomalyco/opencode/releases/download/v1.18.7/opencode-linux-x64.tar.gz";
      sha256 = "sha256-y12dbS+PvvCpyXXtRJT3Oypi9OT/1Qi8wyEtpPp2w9o=";
    };

    dontConfigure = true;
    dontUnpack = true;
    dontBuild = true;

    nativeBuildInputs = [ super.patchelf super.makeBinaryWrapper ];

    installPhase = ''
      runHook preInstall
      mkdir -p $out/bin
      tar xzf "$src" -C $out/bin
      BIN="$out/bin/opencode"
      chmod +x "$BIN"
      patchelf --set-interpreter "$(cat ${super.stdenv.cc}/nix-support/dynamic-linker)" "$BIN" || true
      patchelf --set-rpath "${super.glibc}/lib" "$BIN" || true
      # This is a prebuilt binary, so upstream's build-time OPENCODE_CHANNEL
      # define is absent. Set it at runtime to "stable" so it reads the
      # existing opencode-stable.db (where prior sessions live) instead of
      # creating a fresh opencode.db.
      wrapProgram "$BIN" \
        --set OPENCODE_CHANNEL "stable" \
        --set OPENCODE_DISABLE_AUTOUPDATE "true"
      runHook postInstall
    '';

    meta = with super.lib; {
      description = "AI coding agent built for the terminal (pinned 1.18.7 overlay)";
      homepage = "https://github.com/anomalyco/opencode";
      license = licenses.mit;
      mainProgram = "opencode";
    };
  };


  pi = super.stdenvNoCC.mkDerivation {
    pname = "pi";
    version = "0.83.0";

    src = super.fetchurl {
      url = "https://github.com/earendil-works/pi/releases/download/v0.83.0/pi-linux-x64.tar.gz";
      sha256 = "sha256-sGJetiMZewr+IMhw0h7y80SB8VBOV3ffP2mKZsdjb18=";
    };

    dontConfigure = true;
    dontUnpack = true;
    dontBuild = true;

    nativeBuildInputs = [ super.patchelf ];

    installPhase = ''
      runHook preInstall
      mkdir -p $out/lib/pi
      tar xzf "$src" -C $out/lib/pi
      BIN="$out/lib/pi/pi/pi"
      chmod +x "$BIN"
      patchelf --set-interpreter "$(cat ${super.stdenv.cc}/nix-support/dynamic-linker)" "$BIN" || true
      patchelf --set-rpath "${super.glibc}/lib" "$BIN" || true
      mkdir -p $out/bin
      ln -s "$BIN" $out/bin/pi
      runHook postInstall
    '';

    meta = with super.lib; {
      description = "Minimal agent harness (pinned 0.83.0 overlay)";
      homepage = "https://pi.dev";
      license = licenses.mit;
      mainProgram = "pi";
    };
  };

  jcode = super.stdenvNoCC.mkDerivation {
    pname = "jcode";
    version = "0.67.1";

    src = super.fetchurl {
      url = "https://github.com/1jehuang/jcode/releases/download/v0.67.1/jcode-linux-x86_64.tar.gz";
      sha256 = "sha256-NOVj18QwGWgV+dXE+14S0bxqA8kmAIydQ7UDeS0On/g=";
    };

    dontConfigure = true;
    dontUnpack = true;
    dontBuild = true;

    nativeBuildInputs = [ super.patchelf ];

    installPhase = ''
      runHook preInstall
      mkdir -p $out/bin
      tar xzf "$src" -C $out/bin
      # Tarball: launcher script (jcode-linux-x86_64) + actual binary (.bin).
      # The launcher execs the .bin with LD_LIBRARY_PATH=$self_dir. We install
      # both and patchelf the real binary for Nix glibc/libgcc.
      mv $out/bin/jcode-linux-x86_64.bin $out/bin/jcode
      rm -f $out/bin/jcode-linux-x86_64
      chmod +x $out/bin/jcode
      patchelf --set-interpreter "$(cat ${super.stdenv.cc}/nix-support/dynamic-linker)" $out/bin/jcode || true
      patchelf --set-rpath "${super.glibc}/lib:${super.gcc.cc.lib}/lib" $out/bin/jcode || true
      runHook postInstall
    '';

    meta = with super.lib; {
      description = "Rust-native AI coding agent harness (pinned 0.67.1 overlay)";
      homepage = "https://github.com/1jehuang/jcode";
      license = licenses.mit;
      mainProgram = "jcode";
    };
  };


}
