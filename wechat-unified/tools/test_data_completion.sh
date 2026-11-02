#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
# Current iSH shared directories may be noexec. Compile the portable test to /tmp.
VIDEO_TEST="$(mktemp /tmp/wu-data-video.XXXXXX)"
trap 'rm -f "$VIDEO_TEST"' EXIT
cc -std=c11 -Wall -Wextra -Werror -I Sources tests/local_video_container.c -o "$VIDEO_TEST"
"$VIDEO_TEST" | tee build/data-video-tests.txt
if ! command -v xcrun >/dev/null 2>&1; then
  echo 'SKIP: Foundation/UIKit/XCTest unavailable here; run on the parent macOS CI. No Objective-C pass claimed.'
  exit 77
fi
COMMON=(-fobjc-arc -fobjc-arc-exceptions -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -I Sources)
xcrun --sdk macosx clang "${COMMON[@]}" tests/moments_data_completion.m Sources/MomentsCacheLogic.m Sources/RepositoryLogic.m Sources/DraftMediaLogic.m -framework Foundation -o build/data-moments-tests
build/data-moments-tests | tee build/data-moments-tests.txt
xcrun --sdk macosx clang "${COMMON[@]}" tests/draft_video_restore.m Sources/DraftVideoRestore.m Sources/DraftsLogic.m Sources/DraftMediaLogic.m Sources/RepositoryLogic.m -framework Foundation -o build/data-draft-tests
build/data-draft-tests | tee build/data-draft-tests.txt
xcrun --sdk macosx clang "${COMMON[@]}" tests/voice_pack_files.m Sources/VoicePackLogic.m Sources/VoiceAudio.m Sources/VoiceLogic.m Sources/VoiceSendLogic.m Sources/MessageConstruction.m Sources/RepositoryLogic.m Sources/DraftMediaLogic.m build/codec-macosx/libWUOffline.a -framework Foundation -framework AudioToolbox -o build/data-voice-tests
build/data-voice-tests | tee build/data-voice-tests.txt
rm -f build/data-moments-tests build/data-voice-tests build/data-draft-tests
bash tools/test_host_data.sh
# New stats tests are included by tools/test_stats.sh, invoked by the existing build.
