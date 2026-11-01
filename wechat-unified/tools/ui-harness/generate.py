#!/usr/bin/env python3
"""Disposable unsigned UIKit/XCTest Xcode project."""
import json
import sys
from pathlib import Path

PRODUCTION = ("SurfaceStyle.m", "ThemeCatalog.m", "ThemeColors.m", "InteractionLogic.m")
HEADERS = ("WU.h", "ThemeCatalog.h", "ThemeArchive.h", "ThemePrimitives.h", "InteractionLogic.h")


def generate(root, out):
    root, out = Path(root).resolve(), Path(out).resolve()
    sources = [root / "Sources" / n for n in PRODUCTION] + [root / "tests/surface_style_ios.m"]
    for p in sources + [root / "Sources" / n for n in HEADERS]:
        if not p.is_file():
            raise SystemExit(f"Missing input: {p}")
    out.mkdir(parents=True, exist_ok=False)
    harness = Path(__file__).resolve().parent
    (out / "Host.m").write_bytes((harness / "Host.m").read_bytes())
    (out / "Prefix.pch").write_text('#import <QuartzCore/QuartzCore.h>\n')
    objects = {}

    def obj(isa, **fields):
        key = f"{len(objects) + 1:024X}"
        objects[key] = dict(isa=isa, **fields)
        return key

    def config(settings):
        c = obj("XCBuildConfiguration", name="Debug", buildSettings=settings)
        return obj("XCConfigurationList", buildConfigurations=[c], defaultConfigurationIsVisible=0, defaultConfigurationName="Debug")

    settings = dict(SDKROOT="iphonesimulator", IPHONEOS_DEPLOYMENT_TARGET="16.0",
        SUPPORTED_PLATFORMS="iphonesimulator", TARGETED_DEVICE_FAMILY="1",
        CLANG_ENABLE_OBJC_ARC="YES", CLANG_ENABLE_MODULES="YES",
        CODE_SIGNING_ALLOWED="NO", CODE_SIGNING_REQUIRED="NO",
        GENERATE_INFOPLIST_FILE="YES", PRODUCT_NAME="$(TARGET_NAME)",
        GCC_PREFIX_HEADER="$(SRCROOT)/Prefix.pch", HEADER_SEARCH_PATHS=['"' + str(root / "Sources") + '"'],
        FRAMEWORK_SEARCH_PATHS=["$(inherited)", "$(PLATFORM_DIR)/Developer/Library/Frameworks"],
        LD_RUNPATH_SEARCH_PATHS=["$(inherited)", "@executable_path/Frameworks", "@loader_path/Frameworks"])
    refs, products = [], []

    def target(name, files, kind, extra):
        builds = []
        for p in files:
            ref = obj("PBXFileReference", path=str(p), sourceTree="<absolute>", lastKnownFileType="sourcecode.c.objc")
            refs.append(ref)
            builds.append(obj("PBXBuildFile", fileRef=ref))
        phase = obj("PBXSourcesBuildPhase", files=builds, buildActionMask=2147483647, runOnlyForDeploymentPostprocessing=0)
        ext = "app" if kind == "application" else "xctest"
        product = obj("PBXFileReference", path=f"{name}.{ext}", sourceTree="BUILT_PRODUCTS_DIR", explicitFileType="wrapper.application" if ext == "app" else "wrapper.cfbundle")
        products.append(product)
        flags = "-framework UIKit -framework Foundation -framework QuartzCore"
        if ext == "xctest":
            flags += " -framework XCTest"
        cfg = dict(PRODUCT_BUNDLE_IDENTIFIER=f"org.wechatunified.harness.{name}", OTHER_LDFLAGS=flags, **extra)
        return obj("PBXNativeTarget", name=name, productReference=product,
            productType="com.apple.product-type." + kind, buildConfigurationList=config(cfg),
            buildPhases=[phase], buildRules=[], dependencies=[])

    host = target("WUHost", [out / "Host.m"], "application", {"INFOPLIST_KEY_UILaunchScreen_Generation": "YES"})
    tests = target("WUSurfaceTests", sources, "bundle.unit-test", {"TEST_HOST": "$(BUILT_PRODUCTS_DIR)/WUHost.app/WUHost", "BUNDLE_LOADER": "$(TEST_HOST)"})
    pg = obj("PBXGroup", children=products, name="Products", sourceTree="<group>")
    group = obj("PBXGroup", children=refs + [pg], sourceTree="<group>")
    project = obj("PBXProject", buildConfigurationList=config(settings), mainGroup=group,
        productRefGroup=pg, targets=[host, tests], compatibilityVersion="Xcode 14.0",
        projectDirPath="", developmentRegion="en",
        attributes={"TargetAttributes": {tests: {"TestTargetID": host}}})
    proxy = obj("PBXContainerItemProxy", containerPortal=project, proxyType=1, remoteGlobalIDString=host, remoteInfo="WUHost")
    objects[tests]["dependencies"] = [obj("PBXTargetDependency", target=host, targetProxy=proxy)]

    def plist(v):
        if isinstance(v, dict):
            return "{\n" + "".join(f"{json.dumps(k)} = {plist(x)};\n" for k, x in v.items()) + "}"
        if isinstance(v, list):
            return "(" + ",".join(plist(x) for x in v) + ")"
        return json.dumps(v)

    pbx = out / "SurfaceHarness.xcodeproj"
    schemes = pbx / "xcshareddata/xcschemes"
    schemes.mkdir(parents=True)
    (pbx / "project.pbxproj").write_text("// !$*UTF8*$!\n" + plist(dict(archiveVersion=1, classes={}, objectVersion=56, objects=objects, rootObject=project)))
    template = (harness / "SurfaceHarness.xcscheme.in").read_text()
    (schemes / "SurfaceHarness.xcscheme").write_text(template.format(host=host, tests=tests))
    return pbx


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("Usage: generate.py SOURCE_ROOT NEW_OUTPUT_DIRECTORY")
    print(generate(*sys.argv[1:]))
