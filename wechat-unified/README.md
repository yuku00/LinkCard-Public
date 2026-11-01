# WeChat Unified 0.1.0 — independent experimental dylib

Independent Objective-C source implementation; no original plugin binary, source dump, assets, account data, credentials, AI client or remote service is included. Publication is prepared for the `wechat-unified/` directory on a dedicated branch. Build and publication status must be checked against the dedicated GitHub Actions run for the exact source commit; local structural tests alone do not prove compilation or device compatibility. Existing projects are untouched.

## This release

This is a small functional first delivery, **not the whole requested feature set**. Implemented: targeted official-account feed advertising switches/plugin filtering; literal Moments keyword filtering; scoped input/system-notice outlines; home-list separator hiding; manual local link detection with explicit default-browser confirmation. One entry is appended to WeChat Settings navigation bar, titled **整合**. No existing navigation item is removed. Actual private class/selector signatures are checked before installation; unsupported switches are disabled with an explanation. The diagnostic page lists structural hook results only, never message/account contents.

Default: all interception and appearance switches OFF. Enable the master and individual items deliberately. No message is sent, recalled, deleted, exported or scanned. Device-level cosmetic/keyword preferences alone are stored in Application Support/WeChatUnified. Atomic writes, checked file fsync, backup and O_NOFOLLOW are used. The plugin does not touch host data files. Account-specific storage/dispatch modules are deliberately absent rather than writing to an unsafe shared account bucket.

## Build

On a macOS Xcode runner: `bash tools/build.sh`. No Theos, substrate, third-party framework or additional SDK download. Product: `build/WeChatUnified.dylib`, arm64, deployment target iOS 16.6, ad-hoc signed. The build checks source invariants, compiles with warnings-as-errors, checks signature, architecture, minimum OS and dependencies, and emits SHA256. GitHub Actions uploads the product and verification files.

## Installation / acceptance (not executed here)

Use an isolated test account/device and back up WeChat. In TrollFools inject this dylib into WeChat, cold-start, open **我 → 设置 → 整合**. A missing entry means the host settings controller is not adapted; do not interpret this as success. Do not inject the old ad/appearance plugins simultaneously when isolating behavior. ActionBar may remain a separate plugin, but coexistence is not tested. This plugin never hooks system keyboard Dock.

Test every switch OFF/ON/OFF, empty and populated feeds, cell reuse, foreground/background, light/dark mode, settings reentry and kill/restart. Ad effects require host feed refresh; previously cached ads may remain. Keyword filters preserve the original filter result and only add literal case/diacritic-insensitive matches, at most 2048 configured characters, 128 per word; texts over 65536 characters are untouched. Turning filtering off does not resurrect unloaded items until the feed reloads. Appearance uses an owned noninteractive layer, not modified host text/message data. Separator hiding is restricted to the adapted home controller.

Links are manually entered/pasted in settings, with at most 8192 characters and 10 HTTP(S) candidates. Credentials in URLs and other schemes are rejected. Each open shows the actual host and full URL. This does not integrate a chat context menu, disable WeChat security, force Safari when it is not default, or guarantee a blocked destination can be opened.

## Safety / limits

Private ABI matching is necessary, not sufficient to prove semantic compatibility. No physical device test has been performed. Target WeChat is provisionally 8.0.70; exact build unverified. Future versions, arm64e-specific injection behavior, TrollFools loading and feature effectiveness are **not certified**. Do not equate CI compilation with compatibility. Missing methods pass through/disable only affected functionality. Original IMPs are called once on pass-through; each class+selector has one owner. A host method inherited from a superclass gets a local override rather than modifying the shared superclass. Runtime uninstall does not attempt to restore IMPs across other plugins.

See STATUS.md for the complete remaining scope. Removed/deferred features have no fake settings switches. No reward callbacks are forged, no original licensing/authorization logic is reused. License: GPL-3.0-or-later, consistent with the containing repository; independent authored source, no imported binary implementation.
