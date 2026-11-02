#!/usr/bin/env python3
"""Run exactly the existing four UIKit XCTest methods on an installed simulator."""
import json
import os
import platform
import subprocess
import sys
from pathlib import Path

sys.dont_write_bytecode = True
from generate import generate

EXPECTED = {
    "testRealPropertyApplicationAndDisable",
    "testHostMutationIsNotOverwritten",
    "testThemeColorsReallyApplyAndExplicitOverrideWins",
    "testRepeatedLayoutsDoNotOverwriteOriginalBaseline",
}


def choose_device(runtimes, devices):
    candidates = []
    for runtime in runtimes["runtimes"]:
        if not runtime.get("isAvailable") or not runtime["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-"):
            continue
        version = tuple(int(n) for n in runtime["version"].split("."))
        if version < (16,):
            continue
        for device in devices["devices"].get(runtime["identifier"], []):
            if device.get("isAvailable") and device["name"].startswith("iPhone"):
                candidates.append((version, device.get("state") == "Booted", device["name"], runtime, device))
    if not candidates:
        raise RuntimeError("FAIL: no available installed iOS >=16 iPhone simulator; no tests ran")
    _, _, _, runtime, device = max(candidates, key=lambda x: x[:3])
    return runtime, device


def test_records(tree):
    records = []
    def walk(node, parents=()):
        if isinstance(node, dict):
            ident = node.get("identifier", {}).get("_value", "")
            lineage = parents + (ident,) if ident else parents
            if "testStatus" in node:
                if not any(x == "WUSurfaceStyleTests" or x.startswith("WUSurfaceStyleTests/") for x in lineage):
                    raise RuntimeError(f"Unexpected test class: {lineage}")
                records.append((ident.rsplit("/", 1)[-1].removesuffix("()"), node["testStatus"]["_value"]))
            for value in node.values():
                walk(value, lineage)
        elif isinstance(node, list):
            for value in node:
                walk(value, parents)
    walk(tree)
    return records


def require_four_passes(records):
    if len(records) != 4 or {name for name, _ in records} != EXPECTED or any(status != "Success" for _, status in records):
        raise RuntimeError(f"FAIL: require all four named tests, no skips/retries/duplicates: {records}")


def capture(command, output=None, timeout=120):
    data = subprocess.check_output(command, stderr=None, timeout=timeout)
    if output:
        output.write_bytes(data)
    return data


def cleanup_owned(out):
    marker=Path(out)/'booted-by-harness.json'
    if not marker.is_file(): return
    device=json.loads(marker.read_text())['udid']
    subprocess.run(['xcrun','simctl','shutdown',device],check=False,timeout=60,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    marker.unlink(missing_ok=True)


def main():
    if len(sys.argv)==3 and sys.argv[1]=='--cleanup':
        cleanup_owned(sys.argv[2]); return
    if len(sys.argv) != 3:
        raise RuntimeError("Usage: python3 run.py SOURCE_ROOT NEW_RESULT_DIRECTORY")
    if platform.system() != "Darwin":
        raise RuntimeError("FAIL: macOS + Xcode + installed iPhoneSimulator SDK required; no UIKit tests ran")
    root, out = (Path(p).resolve() for p in sys.argv[1:])
    out.mkdir(parents=True, exist_ok=False)  # Never accept a stale result bundle.
    print(capture(["xcodebuild", "-version"]).decode(), flush=True)
    print("Simulator SDK:", capture(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"]).decode().strip(), flush=True)
    runtimes = json.loads(capture(["xcrun", "simctl", "list", "runtimes", "--json"], out / "runtimes.json"))
    devices = json.loads(capture(["xcrun", "simctl", "list", "devices", "--json"], out / "devices.json"))
    runtime, device = choose_device(runtimes, devices)
    (out / "destination.json").write_text(json.dumps({"runtime": runtime, "device": device}, indent=2))
    print(f"Destination: {device['name']} / iOS {runtime['version']} / {device['udid']}", flush=True)
    project = generate(root, out / "project")
    capture(["plutil", "-lint", str(project / "project.pbxproj")])
    booted_here = device["state"] != "Booted"
    passed=False
    try:
        if booted_here:
            capture(["xcrun", "simctl", "boot", device["udid"]])
            (out/'booted-by-harness.json').write_text(json.dumps({'udid':device['udid']}))
        capture(["xcrun", "simctl", "bootstatus", device["udid"], "-b"], timeout=240)
        result = out / "SurfaceTests.xcresult"
        command = ["xcodebuild", "test", "-project", str(project), "-scheme", "SurfaceHarness",
                   "-configuration", "Debug", "-sdk", "iphonesimulator",
                   "-destination", f"platform=iOS Simulator,id={device['udid']}",
                   "-destination-timeout", "60", "-derivedDataPath", str(out / "DerivedData"),
                   "-resultBundlePath", str(result), "-parallel-testing-enabled", "NO",
                   "-only-testing:WUSurfaceTests/WUSurfaceStyleTests",
                   "-test-timeouts-enabled", "YES", "-default-test-execution-time-allowance", "60",
                   "-maximum-test-execution-time-allowance", "120",
                   "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO"]
        log = out / "xcodebuild.log"
        print(f"Running real XCTest; build/test log: {log}", flush=True)
        try:
            with log.open("wb") as stream:
                subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT, check=True, timeout=1200)
        finally:
            print("\n".join(log.read_text(errors="replace").splitlines()[-60:]), flush=True)
        # The legacy typed tree exposes per-method status; never trust just exit code/counts.
        command = ["xcrun", "xcresulttool", "get", "object", "--legacy", "--path", str(result), "--format", "json"]
        tree = json.loads(capture(command, out / "result-root.json"))
        refs = [action["actionResult"]["testsRef"]["id"]["_value"]
                for action in tree.get("actions", {}).get("_values", [])
                if "testsRef" in action.get("actionResult", {})]
        records = []
        for i, ref in enumerate(refs):
            records.extend(test_records(json.loads(capture(command + ["--id", ref], out / f"tests-{i}.json"))))
        require_four_passes(records)
        (out / "verified-tests.json").write_text(json.dumps(records, indent=2))
        passed=True
        print("PASS: 4/4 real UIKit simulator XCTest. NOT real-device/WeChat validation.", flush=True)
    finally:
        if not (passed and os.environ.get('WU_HARNESS_KEEP_BOOTED')=='1'):
            cleanup_owned(out)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)
