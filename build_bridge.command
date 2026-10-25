#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
JAVA_DIR="${TOOLKIT_JAVA_HOME:-}"
if [[ -z "$JAVA_DIR" ]]; then JAVA_DIR="$(/usr/libexec/java_home -v 17)"; fi
mkdir -p .build/bridge Resources
COMPILER=.build/r8-8.3.37.jar
if [[ ! -f "$COMPILER" ]]; then
    curl --fail --location --connect-timeout 15 --max-time 120 \
      https://storage.googleapis.com/r8-releases/raw/8.3.37/r8.jar -o "$COMPILER.part"
    mv "$COMPILER.part" "$COMPILER"
fi
"$JAVA_DIR/bin/javac" --release 8 -d .build/bridge AndroidBridge/ToolkitBridge.java
"$JAVA_DIR/bin/java" -cp "$COMPILER" com.android.tools.r8.D8 --release --min-api 30 \
    --output .build/bridge .build/bridge/ToolkitBridge.class
cp .build/bridge/classes.dex Resources/toolkit-bridge.dex
echo "安卓控件组件已构建。"
