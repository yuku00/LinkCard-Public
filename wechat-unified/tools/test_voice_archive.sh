#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build
xcrun --sdk macosx clang -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -I Sources tests/voice_archive.m -framework Foundation -lz -o build/voice-archive-tests
build/voice-archive-tests
