set -euo pipefail

RUNNER=windows/runner
[ -d "$RUNNER" ] || { echo "windows/runner not found; run tool/setup_platforms.sh first."; exit 1; }

cp windows_overlay/title_bar.h windows_overlay/title_bar.cpp "$RUNNER/"

WIN="$RUNNER/flutter_window.cpp"
if ! grep -q "RegisterTitleBarChannel" "$WIN"; then
  awk '
    /#include "flutter\/generated_plugin_registrant.h"/ && !inc {
      print; print "#include \"title_bar.h\""; inc = 1; next
    }
    /RegisterPlugins\(flutter_controller_->engine\(\)\);/ && !call {
      print
      print "  RegisterTitleBarChannel(flutter_controller_->engine()->messenger(), GetHandle());"
      call = 1; next
    }
    { print }
    END { if (!inc || !call) exit 3 }
  ' "$WIN" > "$WIN.tmp" && mv "$WIN.tmp" "$WIN" || {
    rm -f "$WIN.tmp"
    echo "Could not patch $WIN automatically. Add by hand:"
    echo '  #include "title_bar.h"'
    echo '  RegisterTitleBarChannel(flutter_controller_->engine()->messenger(), GetHandle());   // after RegisterPlugins(...)'
    exit 1
  }
fi

CMAKE="$RUNNER/CMakeLists.txt"
if ! grep -q "title_bar.cpp" "$CMAKE"; then
  awk '
    /"flutter_window.cpp"/ && !done { print; print "  \"title_bar.cpp\""; done = 1; next }
    { print }
    END { if (!done) exit 3 }
  ' "$CMAKE" > "$CMAKE.tmp" && mv "$CMAKE.tmp" "$CMAKE" || {
    rm -f "$CMAKE.tmp"
    echo "Could not patch $CMAKE. Add \"title_bar.cpp\" next to \"flutter_window.cpp\" in add_executable."
    exit 1
  }
  printf '\ntarget_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")\n' >> "$CMAKE"
fi

echo "Windows title bar channel installed."
