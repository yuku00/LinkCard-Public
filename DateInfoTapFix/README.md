# DateInfoTapFix

A small companion tweak for the **DateInfo / 快捷时间胶囊** tweak (bundle prefix
`com.zhuifeng.dateinfo`) on iOS 16.6 with RootHide Bootstrap.

## The problem

DateInfo puts a transparent tap target over the status-bar clock hotspot and
attaches a `UITapGestureRecognizer` whose target is a `DIClockTapTarget`
instance. On the affected device:

- the target class is present and matches,
- the hotspot exists at `(26.687, 2, 74, 38)`,
- the target reports `userInteractionEnabled = YES`,
- the action ivar is typed `:`,

and yet a tap on the clock does nothing at all.

## What this package does

It does **not** modify the DateInfo binary, and it does **not** hook DateInfo or
intercept touches. It hooks only `_UIStatusBarForegroundView -layoutSubviews`,
looks for the DateInfo gesture target, and once it is found puts one transparent
tap area of its own on the status bar window, over the same rectangle the tweak
targets. Tapping it calls the tweak's own `-handleTap:` with the tweak's own
recognizer, so the bubble that appears is the DateInfo bubble.

If no window becomes visible 0.45 s after that call, a small self-drawn bubble
shows the current date and time instead, so the tap is never a dead end.

The recognizer is moved to the `ended` state for the duration of the call and
restored immediately afterwards, because the tweak's action only acts on that
state.

## Privacy

No logging to disk, no network access, no preference writes, no background
work. `NSLog` lines are only emitted when something throws, and never contain
the clock text, a URL or a touch coordinate.

## Install

Drop `local.dateinfo.tapfix_1.0.0_iphoneos-arm64e.deb` into Sileo or Filza and
install, then restart SpringBoard. It is a separate package from DateInfo, so it
can be removed with `dpkg -r local.dateinfo.tapfix` without touching DateInfo.

## Why not just fix DateInfo

The DateInfo binary is shipped without source and its action path cannot be
corrected without a device to test on, and the original requirement was to keep
the user's own bubble. Forwarding to the tweak's own action keeps that bubble.

## Build

Built in GitHub Actions with RootHide Theos (`workflow: dateinfo-tapfix-build`).
`ARCHS = arm64 arm64e`, `THEOS_PACKAGE_SCHEME = roothide`.

`tests/test_invariants.py` runs before the build and fails the run if the
package shape, the single hook, the guarded action call, the state restore, or
the "no persistence / no network" rules are broken.
