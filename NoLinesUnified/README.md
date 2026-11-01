# NoLines Unified / RootHide

Source reconstruction of separator-only behavior observed in PurifyLine 1.0.1 and AllInOneNoLines 1.0.6. No original binary is linked, included or loaded. The original packages have no supplied license; this project does not claim permission to redistribute or relicense those binaries. Original author names, package identifiers and behavior descriptions are attribution, not endorsement. No license grant for original materials is implied.

## Scope
Keeps separator hiding, including Photos thin views, and the original scroll-indicator hiding in Notes/Reminders/Files/Phone. Excludes Photos tab/data-source simplification, deletion-confirmation bypass, selection/zoom changes, Files tab hiding and Phone tab deletion. Broad filter suppression is restricted to thin views; context-menu separators retain layout spacing. Phone header's top 5pt mask is retained with existing-mask protection; whether that strip is only a separator is not device-verified.

## Build
Dedicated workflow `.github/workflows/no-lines-unified-build.yml`: macos-15, Xcode 16.4 (iOS 18.5 SDK, deployment target iOS 16.0), RootHide official Theos `3ac89c984ec652fd16bcd91b33ae16de45ce76fa` and its pinned submodules. Uses actual `THEOS_PACKAGE_SCHEME=roothide`, arm64 + arm64e, package architecture iphoneos-arm64e. No `/var/jb` rewrite or original package patch copying. Apple SDK is supplied by hosted Xcode, not uploaded here. Homebrew ldid/dpkg/make are runner utilities and are not fully version-pinned; builds are not claimed bit-reproducible. Workflow actions are pinned by commit.

## Validation and limits
CI compiles, links, signs and packages, then records control/files/Mach-O slices/dependencies/load commands. Build success does not prove runtime compatibility or UI effects. Target iOS 16.6 RootHide Bootstrap must supply a compatible Substrate API and enable injection per app. Bootstrap alone does not guarantee SpringBoard injection; its branch may not work. Private selectors and size-based hiding may vary or hide other small views; reused-view visibility, rotation, themes and Dynamic Type require real-device tests.

No automatic install, release publication or modification of another project's workflow. Disable the two original tweaks before testing. Verify deletion still asks for confirmation, all Photos albums/tabs remain, Files and Phone tabs are unchanged, and intended separator lines are gone. This reconstruction is not an assertion of exact visual equivalence to the original packages.
