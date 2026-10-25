#!/usr/bin/env python3
"""Bounded UIKit regression attempt AFTER Release packaging; never invent success."""
import json, os, pathlib, signal, subprocess
logs = pathlib.Path('build/logs')
logs.mkdir(parents=True, exist_ok=True)
result = {'status': 'not-run', 'suite': 'LinkCardTests/MistEffectLifecycleTests'}
try:
    devices = json.loads(subprocess.check_output(
        ['xcrun', 'simctl', 'list', 'devices', 'available', '--json'], timeout=30))['devices']
    choices = [(runtime, d) for runtime, group in devices.items() if '.iOS-' in runtime
               for d in group if d.get('isAvailable') and d['name'].startswith('iPhone')]
    if not choices:
        result['reason'] = 'No available iPhone simulator; no runtime downloaded'
    else:
        runtime, device = sorted(choices, key=lambda x: x[0], reverse=True)[0]
        result.update(runtime=runtime, device=device['name'], udid=device['udid'])
        command = ['xcodebuild', 'test', '-project', 'LinkCard.xcodeproj', '-scheme', 'LinkCard',
                   '-configuration', 'Debug', '-sdk', 'iphonesimulator',
                   '-destination', 'platform=iOS Simulator,id=' + device['udid'],
                   '-destination-timeout', '90', '-parallel-testing-enabled', 'NO',
                   '-only-testing:' + result['suite'],
                   '-only-testing:LinkCardTests/BLEConnectionPresentationTests',
                   '-only-testing:LinkCardTests/MistBlurStoreTests',
                   '-only-testing:LinkCardTests/WorkbenchPresentationTests',
                   '-only-testing:LinkCardTests/FrameCodecTests',
                   '-only-testing:LinkCardTests/FusionPresentationTests',
                   '-only-testing:LinkCardTests/PN532IdentifyTests',
                   '-derivedDataPath', 'build/UIKitDerivedData',
                   '-resultBundlePath', 'build/logs/MistLifecycle.xcresult',
                   'CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO', 'CODE_SIGN_IDENTITY=', 'DEVELOPMENT_TEAM=']
        with (logs / 'mist-uikit-tests.log').open('w') as output:
            process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
            try:
                code = process.wait(timeout=420)
                result.update(status='passed' if code == 0 else 'failed', exit_code=code)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGTERM)
                try: process.wait(timeout=10)
                except subprocess.TimeoutExpired: os.killpg(process.pid, signal.SIGKILL)
                result.update(status='timeout', reason='420 second UIKit test budget reached')
except Exception as error:
    result.update(status='not-run', reason=str(error))
(logs / 'mist-uikit-result.json').write_text(json.dumps(result, indent=2) + '\n')
if (logs / 'MistLifecycle.xcresult').exists():
    # xcodebuild can use a cloned simulator and shut it down at test completion.
    # Export test attachments directly; do not pretend the requested UDID stayed booted.
    import shutil
    try:
        subprocess.run(['xcrun', 'xcresulttool', 'export', 'attachments',
                        '--path', str(logs / 'MistLifecycle.xcresult'),
                        '--output-path', str(logs / 'workbench-attachments')], check=True, timeout=45)
        base = pathlib.Path.home() / 'Library/Developer/CoreSimulator/Devices'
        for snapshots in base.glob('*/data/Containers/Data/Application/*/Documents/workbench-snapshots'):
            shutil.copytree(snapshots, logs / 'workbench-snapshots', dirs_exist_ok=True)
    except Exception as error:
        print('Snapshot export unavailable:', str(error))
print(json.dumps(result, indent=2))
if result['status'] != 'passed':
    print('::warning::UIKit lifecycle suite did not pass; Release IPA is built, NOT UIKit-validated. See diagnostics.')
