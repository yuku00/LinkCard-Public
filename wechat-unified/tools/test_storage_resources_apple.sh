#!/bin/bash
# Real macOS filesystem and production Foundation implementations; no simulator.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin ]] || { echo 'BLOCKED: Apple host required'; exit 1; }
mkdir -p build/migration
COMMON=(-fobjc-arc -fobjc-arc-exceptions -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -I Sources)
xcrun --sdk macosx clang "${COMMON[@]}" tests/storage_theme_files.m Sources/ThemeArchive.m Sources/ThemeCatalog.m Sources/ThemeColors.m Sources/ThemeLibrary.m -framework Foundation -lz -o build/migration/theme-files
build/migration/theme-files
python3 tools/build_codecs.py macosx
xcrun --sdk macosx clang "${COMMON[@]}" tests/voice_pack_files.m Sources/VoicePackLogic.m Sources/VoiceAudio.m Sources/VoiceLogic.m Sources/VoiceSendLogic.m Sources/MessageConstruction.m Sources/RepositoryLogic.m Sources/DraftMediaLogic.m build/codec-macosx/libWUOffline.a -framework Foundation -framework AudioToolbox -o build/migration/voice-files
build/migration/voice-files
