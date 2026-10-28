#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build dist
sdk=$(xcrun --sdk iphoneos --show-sdk-path)
xcodebuild -version
xcrun --sdk iphoneos clang --version
for arch in arm64 arm64e; do
  xcrun --sdk iphoneos clang -dynamiclib -arch "$arch" -isysroot "$sdk" \
    -miphoneos-version-min=16.6 -O2 -Wall -Wextra -Werror \
    -fvisibility=hidden -fno-stack-protector -fno-unwind-tables \
    -fno-asynchronous-unwind-tables \
    -Wl,-install_name,@rpath/MailLoadCheck.dylib \
    -Wl,-current_version,0.1.0 -Wl,-compatibility_version,0.1.0 \
    -Wl,-no_fixup_chains -Wl,-no_adhoc_codesign \
    MailLoadCheck.c -o "build/$arch.dylib"
done
revision=${GITHUB_SHA:-local}
file="MailLoadCheck-0.1.0-trollfools-arm64-arm64e-${revision:0:12}.dylib"
xcrun lipo -create build/arm64.dylib build/arm64e.dylib -output "dist/$file"
ldid -S "dist/$file"
xcrun lipo "dist/$file" -verify_arch arm64 arm64e
python3 verify.py "dist/$file" | tee dist/AUDIT.json
for arch in arm64 arm64e; do
  xcrun otool -arch "$arch" -L "dist/$file"
  xcrun otool -arch "$arch" -tvV "dist/$file"
  xcrun nm -arch "$arch" -m "dist/$file"
done
cp README.md dist/README.md
printf '\n构建提交：%s\n构建运行：https://github.com/yuku00/LinkCard-Public/actions/runs/%s\n文件：%s\n' \
  "$revision" "${GITHUB_RUN_ID:-local}" "$file" >> dist/README.md
(cd dist && shasum -a 256 "$file" README.md AUDIT.json > SHA256SUMS)
