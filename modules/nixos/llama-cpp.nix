# Restore main llama.cpp
{ config, lib, pkgs, ... }:
let
  llama-cpp-cuda = pkgs.stdenv.mkDerivation {
    pname = "llama-cpp-cuda";
    version = "unstable-2026-06-28";
    src = pkgs.fetchFromGitHub {
      owner = "ggml-org";
      repo = "llama.cpp";
      rev = "b3fed31b99f9bd37725833674252bccb429bb183";
      hash = "sha256-2tD15gjORy9MnbHFaf+Kqhx7D+mOKJ8urPQ+SXQfOQg=";
    };
    nativeBuildInputs = with pkgs; [ cmake pkg-config git ];
    buildInputs = with pkgs; [ cudaPackages.cudatoolkit cudaPackages.cudnn ] ++ lib.optionals stdenv.hostPlatform.isLinux [ cudaPackages.libcublas ];
    propagatedBuildInputs = with pkgs; [ addDriverRunpath ];
    cmakeFlags = [ "-DGGML_CUDA=ON" "-DGGML_NATIVE=ON" "-DCMAKE_BUILD_TYPE=Release" "-DLLAMA_CURL=OFF" "-DLLAMA_BUILD_UI=OFF" "-DLLAMA_BUILD_APP=OFF" "-DLLAMA_BUILD_TESTS=OFF" "-DLLAMA_BUILD_EXAMPLES=OFF" ];
    postPatch = ''
      rm -rf tools/ui/*
      cat > tools/ui/ui.h << 'HEADER'
      #pragma once
      #include <array>
      #include <string>
      struct llama_ui_asset {
          std::string           name;
          const unsigned char * data;
          std::size_t           size;
          std::string           etag;
          std::string           type;
      };
      const llama_ui_asset * llama_ui_find_asset(const std::string & name);
      bool llama_ui_use_gzip();
      const std::array<llama_ui_asset, 0> & llama_ui_get_assets();
      HEADER
      cat > tools/ui/ui.cpp << 'IMPL'
      #include "ui.h"
      bool llama_ui_use_gzip() { return false; }
      const std::array<llama_ui_asset, 0> & llama_ui_get_assets() {
          static const std::array<llama_ui_asset, 0> assets{};
          return assets;
      }
      const llama_ui_asset * llama_ui_find_asset(const std::string &) { return nullptr; }
      IMPL
      cat > tools/ui/CMakeLists.txt << 'CMAKE'
      add_library(llama-ui STATIC ui.cpp)
      target_include_directories(llama-ui PUBLIC ''${CMAKE_CURRENT_SOURCE_DIR})
      CMAKE
    '';
    preConfigure = ''
      export CUDA_PATH="${pkgs.cudaPackages.cudatoolkit}"
    '';
    meta = with lib; {
      description = "LLM inference in C/C++ with CUDA support";
      homepage = "https://github.com/ggml-org/llama.cpp";
      license = licenses.mit;
      platforms = platforms.linux;
      mainProgram = "llama-server";
    };
  };
in
{
  environment.systemPackages = [ llama-cpp-cuda ];
  systemd.tmpfiles.rules = [
    "d /home/nate/AI         0755 nate users -"
    "d /home/nate/AI/models  0755 nate users -"
    "d /home/nate/AI/logs    0755 nate users -"
  ];
}
