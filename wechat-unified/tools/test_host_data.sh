#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v xcrun >/dev/null 2>&1; then
  echo 'SKIP: host-data Objective-C production mocks require macOS Foundation; no Apple test pass claimed.'
  exit 77
fi
mkdir -p build
xcrun --sdk macosx clang -fobjc-arc -fobjc-arc-exceptions -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -I Sources \
  tests/host_data.m Sources/WUHostRead.m Sources/MomentsHostComments.m Sources/WUStatsHostProfile.m \
  Sources/MomentsCacheLogic.m Sources/RepositoryLogic.m Sources/DraftMediaLogic.m \
  Sources/WUStats.m Sources/WUStatsDetails.m -framework Foundation -o build/host-data-tests
build/host-data-tests | tee build/host-data-tests.txt
rm -f build/host-data-tests
