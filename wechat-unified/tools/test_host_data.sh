#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 tests/history-events/test_contract.py
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
python3 tests/history-events/extract_callback.py build/history-events/CommentCompletion.inc
xcrun --sdk macosx clang -fobjc-arc -fobjc-arc-exceptions -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -I Sources -I build/history-events \
  tests/history-events/comment_history.m Sources/MomentsCacheLogic.m Sources/RepositoryLogic.m Sources/DraftMediaLogic.m \
  -framework Foundation -o build/history-events/comment-tests
build/history-events/comment-tests | tee build/history-events/comment-tests.txt
rm -f build/history-events/comment-tests
