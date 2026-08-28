final: prev: {
  quickshell = prev.quickshell.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      # Create symlinks from the main binary for each QML service plugin
      # This makes QML find the statically-linked plugins
      if [ -f "$out/bin/.quickshell-wrapped" ]; then
        for dir in $(find "$out/lib/qt-6/qml/Quickshell/Services" -name "qmldir" -exec dirname {} \; 2>/dev/null); do
          plugin=$(grep "^optional plugin" "$dir/qmldir" | awk '{print $3}')
          if [ -n "$plugin" ] && [ ! -f "$dir/$plugin.so" ]; then
            ln -sf "$out/bin/.quickshell-wrapped" "$dir/$plugin.so"
          fi
        done
        # Also link the core plugin
        core_plugin=$(grep "^optional plugin" "$out/lib/qt-6/qml/Quickshell/qmldir" | awk '{print $3}')
        if [ -n "$core_plugin" ] && [ ! -f "$out/lib/qt-6/qml/Quickshell/$core_plugin.so" ]; then
          ln -sf "$out/bin/.quickshell-wrapped" "$out/lib/qt-6/qml/Quickshell/$core_plugin.so"
        fi
      fi
    '';
  });
}
