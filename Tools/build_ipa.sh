#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# macOS/Xcode only. Ad-hoc signature is NOT Apple provisioning or NFC authorization.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/logs build/export

# Run the production coordinator against a host-only deterministic CoreBluetooth double.
# The double lives outside LinkCard and is never part of the iOS target.
mkdir -p build/ble-session-mocks
swiftc -emit-module -emit-library -module-name CoreBluetooth Reference/SessionMocks/CoreBluetooth.swift \
  -emit-module-path build/ble-session-mocks/CoreBluetooth.swiftmodule \
  -o build/ble-session-mocks/libCoreBluetooth.dylib
swiftc -I build/ble-session-mocks -L build/ble-session-mocks -lCoreBluetooth \
  -Xlinker -rpath -Xlinker "$PWD/build/ble-session-mocks" \
  LinkCard/PCRProtocol.swift LinkCard/PN532Identify.swift LinkCard/BLEProfiles.swift LinkCard/PCRBluetooth.swift \
  Reference/BLESessionChecks.swift -o build/ble-session-checks
build/ble-session-checks | tee build/logs/ble-session-checks.log

# Execute the actual Foundation-only Swift parser on the macOS host.
swiftc LinkCard/PCRProtocol.swift Reference/PCRProtocolChecks.swift -o build/pcr-protocol-checks
build/pcr-protocol-checks | tee build/logs/pcr-protocol-checks.log
swiftc LinkCard/PCRProtocol.swift Reference/PCRNFCProChecks.swift -o build/pcr-nfcpro-checks
build/pcr-nfcpro-checks | tee build/logs/pcr-nfcpro-checks.log
swiftc LinkCard/PCRProtocol.swift LinkCard/BLEProfiles.swift Reference/BLEProfileChecks.swift -o build/ble-profile-checks
build/ble-profile-checks | tee build/logs/ble-profile-checks.log

xcodebuild build \
  -project LinkCard.xcodeproj \
  -scheme LinkCard \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData \
  -resultBundlePath build/Build.xcresult \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY= \
  DEVELOPMENT_TEAM=

APP=build/staging/Payload/LinkCard.app
mkdir -p build/staging/Payload
# A fresh CI checkout is expected; refuse to merge stale app contents.
test ! -e "$APP"
ditto build/DerivedData/Build/Products/Release-iphoneos/LinkCard.app "$APP"
test -f "$APP/LinkCard"

# This project has no embedded frameworks/extensions. If that changes, fail rather
# than produce a partially signed IPA; nested code needs inside-out signing.
python3 - "$APP" <<'PY'
import pathlib, plistlib, sys
app = pathlib.Path(sys.argv[1])
assert not list(app.rglob('*.framework')), 'Add explicit nested framework signing first'
assert not list(app.rglob('*.appex')), 'Add explicit extension signing first'
assert not list(app.rglob('*.dylib')), 'Add explicit embedded dylib signing first'
with open('LinkCard/LinkCard.entitlements', 'rb') as f:
    assert plistlib.load(f) == {'com.apple.developer.nfc.readersession.formats': ['TAG']}
with (app / 'Info.plist').open('rb') as f:
    info = plistlib.load(f)
assert info['CFBundleExecutable'] == 'LinkCard'
assert info['NFCReaderUsageDescription']
assert info['CFBundleSupportedPlatforms'] == ['iPhoneOS']
PY

# '-' is an ad-hoc identity: no developer certificate, keychain secret or profile.
# Do not use --deep, platform-application or private NFC entitlements.
codesign --force --sign - --timestamp=none --generate-entitlement-der \
  --entitlements LinkCard/LinkCard.entitlements "$APP"
codesign --verify --strict --verbose=2 "$APP"
codesign -d --entitlements :- "$APP" > build/logs/signed-entitlements.plist
codesign -dvvv "$APP"
python3 - <<'PY'
import plistlib
with open('build/logs/signed-entitlements.plist', 'rb') as f:
    actual = plistlib.load(f)
assert actual == {'com.apple.developer.nfc.readersession.formats': ['TAG']}, actual
PY

# Zip Payload itself, not the containing staging directory.
(cd build/staging && /usr/bin/zip -qry ../export/LinkCard-TrollStore.ipa Payload)
python3 - <<'PY'
import zipfile
with zipfile.ZipFile('build/export/LinkCard-TrollStore.ipa') as z:
    assert z.testzip() is None
    assert 'Payload/LinkCard.app/Info.plist' in z.namelist()
    assert 'Payload/LinkCard.app/LinkCard' in z.namelist()
    assert all(name.startswith('Payload/') for name in z.namelist())
PY
(cd build/export && shasum -a 256 LinkCard-TrollStore.ipa > LinkCard-TrollStore.ipa.sha256)
echo 'Packaged with ad-hoc signature. TrollStore installation and CoreNFC are NOT verified.'

# Preserve matching release symbols before tests, including any failed/aborted run.
DSYM=build/DerivedData/Build/Products/Release-iphoneos/LinkCard.app.dSYM
dwarfdump --uuid "$APP/LinkCard" > build/logs/release-uuids.log
dwarfdump --uuid "$DSYM" >> build/logs/release-uuids.log
ditto -c -k --keepParent "$DSYM" build/logs/LinkCard.app.dSYM.zip
python3 Tools/test_mist_uikit.py
python3 Tools/test_full_app_ui.py
python3 Tools/require_ui_gates.py
