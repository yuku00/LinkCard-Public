# Synthetic theme fixtures (CC0-1.0)

All imagery, SVG geometry, palette values and package contents here were generated for this test batch. No original plugin binary, user data, downloaded theme image or copyrighted theme package is included.

- synthetic-theme.zip: PNG light/dark + preserved nested duplicate basenames + WeUI literal CSS + resources/color XML + alias descriptor.
- append-no-conflict.zip: a new relative file. Expected: existing files survive.
- append-conflict.zip: changed existing relative path plus a new path. Default append must reject the complete batch. Explicit replace must atomically replace only that path and keep the other old files.
- synthetic-svg.zip: two local shape-only SVGs. Requires a real WCSVGImage decoder with the checked signature; rejection without that renderer is expected.
- Synthetic.xcassets: synthetic cover asset. No fake Assets.car is supplied. On an Xcode machine, generate a real one with:

```sh
mkdir -p /tmp/wu-synthetic-car
xcrun actool tests/fixtures/themes/Synthetic.xcassets \
  --compile /tmp/wu-synthetic-car --platform iphoneos \
  --minimum-deployment-target 16.6 --target-device iphone
```

Then import the generated `/tmp/wu-synthetic-car/Assets.car`; its `cover` asset is a preflight/preview default candidate. For a simulator-rendering test compile for `iphonesimulator` instead; neither simulator execution nor a successful import is a target-WeChat device acceptance result.

Regenerate all committed synthetic input files with `python3 tests/make_theme_fixtures.py`. The ZIP timestamps, file ordering and permissions are deterministic. Runtime export is implemented by production WUWriteThemeZIP, not by this generator.
