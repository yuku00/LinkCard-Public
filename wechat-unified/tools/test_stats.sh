#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
DEVELOPER="$(xcode-select -p)"
FRAMEWORKS="$DEVELOPER/Platforms/MacOSX.platform/Developer/Library/Frameworks"
BUNDLE=build/WUStatsTests.xctest
mkdir -p "$BUNDLE/Contents/MacOS"
/usr/libexec/PlistBuddy -c 'Add :CFBundleExecutable string WUStatsTests' "$BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string org.wechatunified.stats-tests' "$BUNDLE/Contents/Info.plist"
xcrun --sdk macosx clang -fobjc-arc -fblocks -bundle -Wall -Wextra -Werror -Wno-unused-parameter -I Sources -F "$FRAMEWORKS" -Wl,-rpath,"$FRAMEWORKS" tests/WUStatsTests.m tests/WUStatsCompletionTests.m Sources/WUStatsHostProfile.m Sources/WUHostRead.m Sources/WUStatsDetails.m Sources/WUStats.m Sources/WUStatsVisits.m Sources/WUStatsOverview.m -framework Foundation -framework XCTest -o "$BUNDLE/Contents/MacOS/WUStatsTests"
xcrun xctest "$BUNDLE" 2>&1 | tee build/stats-tests.txt
rm -rf "$BUNDLE"
