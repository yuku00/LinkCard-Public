#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
python3 tests/test_source.py
xcrun --sdk macosx clang -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -I Sources tests/voice_logic.m Sources/VoiceLogic.m Sources/VoiceAudio.m -framework Foundation -framework AudioToolbox -o build/voice-logic-tests
build/voice-logic-tests | tee build/voice-logic-tests.txt
rm build/voice-logic-tests
xcrun --sdk macosx clang -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -I Sources tests/ads_logic.m Sources/AdsLogic.m -framework Foundation -o build/ads-logic-tests
build/ads-logic-tests | tee build/ads-logic-tests.txt
rm build/ads-logic-tests
xcrun --sdk macosx clang -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -I tests/ads-stubs -I Sources tests/ads_hooks.m Sources/Ads.m Sources/AdsLogic.m -framework Foundation -o build/ads-hook-tests
build/ads-hook-tests | tee build/ads-hook-tests.txt
rm build/ads-hook-tests
xcrun --sdk macosx clang -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -I Sources tests/message_logic.m Sources/MessageLogic.m -framework Foundation -o build/message-logic-tests
build/message-logic-tests | tee build/message-logic-tests.txt
rm build/message-logic-tests
xcrun --sdk macosx clang -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -I Sources tests/theme_archive.m Sources/ThemeArchive.m -framework Foundation -lz -o build/theme-archive-tests
build/theme-archive-tests | tee build/theme-archive-tests.txt
rm build/theme-archive-tests
xcrun --sdk macosx clang -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -I Sources tests/group_logic.m Sources/GroupLogic.m Sources/HomeLogic.m -framework Foundation -o build/group-logic-tests
build/group-logic-tests | tee build/group-logic-tests.txt
rm build/group-logic-tests
xcrun --sdk macosx clang -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -I Sources tests/home_logic.m Sources/HomeLogic.m Sources/GroupLogic.m -framework Foundation -o build/home-logic-tests
build/home-logic-tests | tee build/home-logic-tests.txt
rm build/home-logic-tests
xcrun --sdk macosx clang -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -I Sources tests/moments_logic.m Sources/MomentsLogic.m Sources/GroupLogic.m Sources/HomeLogic.m -framework Foundation -o build/moments-logic-tests
build/moments-logic-tests | tee build/moments-logic-tests.txt
rm build/moments-logic-tests
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
xcrun --sdk iphoneos clang -arch arm64 -isysroot "$SDK" \
  -miphoneos-version-min=16.6 -fobjc-arc -fblocks -dynamiclib \
  -Wall -Wextra -Werror -Wno-unused-parameter -Wno-nullability-completeness \
  -O2 \
  -install_name @rpath/WeChatUnified.dylib \
  Sources/*.m -framework AudioToolbox -framework Foundation -framework UIKit -framework QuartzCore -framework CoreGraphics -framework ImageIO -framework UniformTypeIdentifiers -lz \
  -o build/WeChatUnified.dylib
bash tools/test_stats.sh
xcrun strip -x build/WeChatUnified.dylib
codesign --force --sign - --timestamp=none build/WeChatUnified.dylib
codesign --verify --strict --verbose=2 build/WeChatUnified.dylib 2>&1 | tee build/signature.txt
codesign -d --verbose=4 build/WeChatUnified.dylib 2>&1 | tee -a build/signature.txt
file build/WeChatUnified.dylib | tee build/architecture.txt
otool -L build/WeChatUnified.dylib | tee build/dependencies.txt
xcrun vtool -show-build build/WeChatUnified.dylib | tee build/platform.txt
shasum -a 256 build/WeChatUnified.dylib | tee build/SHA256SUMS
cp README.md STATUS.md build/
