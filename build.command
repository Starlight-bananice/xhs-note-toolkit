#!/bin/zsh
set -euo pipefail
TASK_ROOT="${0:A:h}"
cd "$TASK_ROOT"
APP="$TASK_ROOT/dist/小红书笔记助手.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$TASK_ROOT/.build/cache"
export CLANG_MODULE_CACHE_PATH="$TASK_ROOT/.build/cache"
export SWIFT_MODULECACHE_PATH="$TASK_ROOT/.build/cache"
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
swiftc -swift-version 5 -target arm64-apple-macosx13.0 -O -framework AppKit -framework SwiftUI \
    Sources/*.swift -o "$APP/Contents/MacOS/XHSNoteToolkit"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/toolkit-bridge.dex "$APP/Contents/Resources/"
codesign --force --deep --sign - --identifier com.starlightbananice.xhsnotetoolkit "$APP"
echo "构建完成：$APP"
