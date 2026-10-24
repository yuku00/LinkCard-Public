#!/usr/bin/env python3
"""Real UIApplication UI tests on the oldest already-installed iPhone runtime. No downloads."""
import json, pathlib, re, subprocess, os, signal, time
logs=pathlib.Path('build/logs'); logs.mkdir(parents=True,exist_ok=True)
result={'status':'not-run','suite':'LinkCardUITests','scene':'actual App/WindowGroup','runtime_downloaded':False}
sidebar_only = os.environ.get('LINKCARD_UI_SCOPE') == 'sidebar'
expected_count = 1 if sidebar_only else 4
result['scope'] = 'sidebar-diagnostic' if sidebar_only else 'fullApp'
try:
    inventory=subprocess.check_output(['xcrun','simctl','list','--json'],timeout=30)
    (logs/'installed-simulators.json').write_bytes(inventory)
    devices=json.loads(inventory)['devices']
    choices=[(runtime,d) for runtime,group in devices.items() if '.iOS-' in runtime for d in group if d.get('isAvailable') and d['name'].startswith('iPhone')]
    choices.sort(key=lambda x:(tuple(int(n) for n in re.findall(r'\d+',x[0])), 0 if x[1]['name']=='iPhone 14' else 1, x[1]['name']))
    if not choices: result['reason']='No installed iPhone runtime; downloading is not authorized'
    else:
        runtime,device=choices[0]
        result.update(runtime=runtime,device=device['name'],udid=device['udid'])
        cmd=['xcodebuild','test','-project','LinkCard.xcodeproj','-scheme','LinkCard','-configuration','Debug','-sdk','iphonesimulator','-destination','platform=iOS Simulator,id='+device['udid'],'-destination-timeout','90','-parallel-testing-enabled','NO','-maximum-concurrent-test-simulator-destinations','1','-only-testing:LinkCardUITests','-derivedDataPath','build/UIKitDerivedData','-resultBundlePath','build/logs/FullApp.xcresult','CODE_SIGNING_ALLOWED=NO','CODE_SIGNING_REQUIRED=NO','CODE_SIGN_IDENTITY=','DEVELOPMENT_TEAM=']
        if sidebar_only:
            cmd[cmd.index('-only-testing:LinkCardUITests')] = '-only-testing:LinkCardUITests/LinkCardFullAppTouchTests/testSidebarActionsTabsSettingsAndSafety'
        started = time.monotonic()
        with (logs/'full-app-ui-tests.log').open('w') as output:
            output.write(f'FULLAPP runner: default animation/quiescence waiting; {expected_count} real UI tests; 1200s budget\n')
            output.flush()
            p=subprocess.Popen(cmd,stdout=output,stderr=subprocess.STDOUT,start_new_session=True)
            try:
                code=p.wait(timeout=1200);result.update(status='passed' if code==0 else 'failed',exit_code=code)
            except subprocess.TimeoutExpired:
                os.killpg(p.pid,signal.SIGTERM)
                try:p.wait(timeout=15)
                except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL)
                result.update(status='timeout',reason='1200s full-App UI test budget')
        result['elapsed_seconds'] = round(time.monotonic() - started, 2)
        if result['status'] != 'passed':
            # Capture the actual simulator without replacing the application root.
            diagnostics = [
                ['xcrun','simctl','io',device['udid'],'screenshot',str(logs/'full-app-failure.png')],
                ['xcrun','simctl','spawn',device['udid'],'log','show','--last','2m','--style','compact','--predicate','process == "LinkCard"']]
            with (logs/'full-app-failure-diagnostics.log').open('w') as output:
                for command in diagnostics:
                    try:
                        p = subprocess.run(command,capture_output=True,text=True,timeout=20)
                        output.write(p.stdout[-40000:] + p.stderr[-4000:])
                    except Exception as error: output.write(str(error)+'\n')
except Exception as e:result.update(status='not-run',reason=str(e))
(logs/'full-app-ui-result.json').write_text(json.dumps(result,indent=2)+'\n')
if (logs/'FullApp.xcresult').exists():
    # Xcode tears down its test simulator before returning. Read the captured
    # app stdout from xcresult, not log show against a dead simulator domain.
    try:
        import tempfile
        with tempfile.TemporaryDirectory(prefix='linkcard-audit-') as tmp:
            export = subprocess.run(['xcrun','xcresulttool','export','diagnostics','--path',str(logs/'FullApp.xcresult'),'--output-path',tmp],capture_output=True,text=True,timeout=60)
            audit_lines = []
            for path in pathlib.Path(tmp).rglob('StandardOutputAndStandardError-org.example.LinkCard.txt'):
                audit_lines.extend(line for line in path.read_text(errors='replace').splitlines() if '[DRAWER-AUDIT]' in line)
            (logs/'drawer-click-audit.log').write_text('\n'.join(audit_lines)+'\n')
            if export.returncode: print('Audit export failed:', export.returncode)
    except Exception as error: print('Audit export:', error)
    for command in [
        ['xcrun','xcresulttool','export','attachments','--path',str(logs/'FullApp.xcresult'),'--output-path',str(logs/'full-app-attachments')],
        ['xcrun','xcresulttool','get','test-results','summary','--path',str(logs/'FullApp.xcresult')]]:
        try:
            p=subprocess.run(command,capture_output=True,text=True,timeout=60)
            if 'summary' in command:
                (logs/'full-app-summary.json').write_text(p.stdout)
                summary = json.loads(p.stdout)
                counts = {key: summary.get(key) for key in ['passedTests','failedTests','skippedTests','totalTestCount']}
                result['test_counts'] = counts
                if result['status'] == 'passed':
                    if counts != {'passedTests':expected_count,'failedTests':0,'skippedTests':0,'totalTestCount':expected_count}:
                        result.update(status='failed',reason=f'All {expected_count} selected full-App tests must execute and pass, none skipped')
            with (logs/'full-app-evidence-export.log').open('a') as output:
                output.write(' '.join(command[1:])+'\n'+p.stderr+'\n')
        except Exception as e:
            print('Evidence export:',e)
            if 'summary' in command and result['status'] == 'passed':
                result.update(status='failed',reason='Could not verify full-App test counts: '+str(e))
elif result['status'] == 'passed':
    result.update(status='failed',reason='Missing full-App xcresult; cannot verify executed test counts')
(logs/'full-app-ui-result.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))
# Workflow explicitly gates both files before allowing IPA artifact publication.
