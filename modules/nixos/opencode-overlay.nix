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

  # pi is no longer overridden here. Upstream ships its own Nix build and we
  # consume it through the `pi-flake` overlay (see flake.nix and
  # hosts/*/default.nix): a source build with nodejs_22 wrapped around node, so
  # the Cursor provider's native @cursor/sdk addon still loads.
}
