#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/compile-only
python3 tools/build_codecs.py iphoneos
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
xcrun --sdk iphoneos clang -std=c11 -O2 -fPIC -arch arm64 -isysroot "$SDK" -miphoneos-version-min=16.6 -Wall -Wextra -Werror -I Sources -c Sources/WUNativeBoot.c -o build/compile-only/native-boot-ios.o
sources=()
while IFS= read -r source; do sources+=("$source"); done < tools/compile_only_sources.txt
for source in "${sources[@]}"; do [[ "$source" == Sources/*.m && -f "$source" ]]; done
xcrun --sdk iphoneos clang -arch arm64 -isysroot "$SDK" -miphoneos-version-min=16.6 -fobjc-arc -fobjc-arc-exceptions -fblocks -dynamiclib -Wall -Wextra -Werror -Wno-unused-parameter -Wno-nullability-completeness -O2 -install_name @rpath/WeChatUnified.dylib "${sources[@]}" build/compile-only/native-boot-ios.o build/codec-iphoneos/libWUOffline.a -Wl,-dead_strip -framework WebKit -framework SafariServices -framework Photos -framework AVKit -framework AVFoundation -framework AudioToolbox -framework Foundation -framework UIKit -framework QuartzCore -framework CoreGraphics -framework ImageIO -framework JavaScriptCore -framework UniformTypeIdentifiers -lz -o build/compile-only/WeChatUnified.dylib
xcrun strip -x build/compile-only/WeChatUnified.dylib
codesign --force --sign - --timestamp=none build/compile-only/WeChatUnified.dylib
codesign --verify --strict --verbose=2 build/compile-only/WeChatUnified.dylib 2>&1 | tee build/compile-only/signature.txt
codesign -d --verbose=4 build/compile-only/WeChatUnified.dylib 2>&1 | tee -a build/compile-only/signature.txt
file build/compile-only/WeChatUnified.dylib | tee build/compile-only/architecture.txt
otool -L build/compile-only/WeChatUnified.dylib | tee build/compile-only/dependencies.txt
xcrun vtool -show-build build/compile-only/WeChatUnified.dylib | tee build/compile-only/platform.txt
(cd build/compile-only && shasum -a 256 WeChatUnified.dylib > SHA256SUMS)
