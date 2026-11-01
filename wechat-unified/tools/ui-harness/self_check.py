#!/usr/bin/env python3
"""Harness-only checks. These do not execute UIKit or count as XCTest passes."""
import json
import re
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

sys.dont_write_bytecode = True
from generate import generate, PRODUCTION
from run import EXPECTED, choose_device, test_records, require_four_passes


def rejects(call):
    try:
        call()
    except RuntimeError:
        return
    raise AssertionError("Expected fail-closed behavior")


root = Path(sys.argv[1]).resolve()
here = Path(__file__).resolve().parent
assert len((here / "generate.py").read_bytes()) < 5120
source = (root / "tests/surface_style_ios.m").read_text()
assert set(re.findall(r"-\s*\(void\)\s*(test\w+)", source)) == EXPECTED
with tempfile.TemporaryDirectory(prefix="wu-self-check-") as temp:
    pbx = generate(root, Path(temp) / "project")
    text = (pbx / "project.pbxproj").read_text()
    for name in (*PRODUCTION, "surface_style_ios.m", "Host.m"):
        assert text.count('/' + name + '";') == 1, name
    assert "/Core.m" not in text and "/Themes.m" not in text
    assert text.count('"isa" = "PBXBuildFile"') == 6
    ids = set(re.findall(r'"([A-F0-9]{24})" = \{', text))
    scheme = ET.parse(pbx / "xcshareddata/xcschemes/SurfaceHarness.xcscheme")
    for node in scheme.findall(".//BuildableReference"):
        assert node.attrib["BlueprintIdentifier"] in ids
    assert scheme.find(".//TestableReference").attrib["skipped"] == "NO"

runtime = dict(identifier="com.apple.CoreSimulator.SimRuntime.iOS-18-0", version="18.0", isAvailable=True)
device = dict(name="iPhone 16", udid="fixture-only", state="Shutdown", isAvailable=True)
assert choose_device({"runtimes": [runtime]}, {"devices": {runtime["identifier"]: [device]}})[1] == device
rejects(lambda: choose_device({"runtimes": []}, {"devices": {}}))
rejects(lambda: choose_device({"runtimes": [runtime]}, {"devices": {runtime["identifier"]: [dict(device, isAvailable=False)]}}))
leaves = [{"identifier": {"_value": name}, "testStatus": {"_value": "Success"}} for name in sorted(EXPECTED)]
tree = {"identifier": {"_value": "WUSurfaceStyleTests"}, "subtests": {"_values": leaves}}
records = test_records(tree)
require_four_passes(records)
for bad in ([], records[:-1], records + records[:1], [(name, "Skipped") for name, _ in records], [(name, "Failure") for name, _ in records]):
    rejects(lambda: require_four_passes(bad))
for leaf in leaves:
    leaf["identifier"]["_value"] = "WUSurfaceStyleTests/" + leaf["identifier"]["_value"] + "()"
require_four_passes(test_records({"_values": leaves}))
print("Harness static/self-checks passed. UIKit XCTest NOT executed.")
