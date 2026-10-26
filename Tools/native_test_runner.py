#!/usr/bin/env python3
"""Bounded native runner. Raw diagnostics stay local; public progress is allowlisted."""
import json
import os
from pathlib import Path
import re
import signal
import shutil
import subprocess
import time

PHASES = {'not-started', 'inventory', 'create', 'simulator-launch', 'boot', 'bootstatus',
          'readiness', 'build', 'test-startup', 'testing', 'results', 'cleanup', 'complete'}
BOOT_PHASES = {'not-started', 'inventory', 'create', 'simulator-launch', 'boot', 'bootstatus',
               'readiness', 'ready', 'failed', 'waiting-backboard', 'waiting-data-migration',
               'waiting-system-app', 'waiting-boot'}
PROCESS_STATES = {'not-started', 'running', 'exited', 'terminated', 'killed', 'unknown'}


def public_methods(root=Path('.'), suite=None):
    """Only identifiers declared in the two versioned public test sources."""
    methods = set()
    for target, filename in [('unit', 'LinkCardTests/FrameCodecTests.swift'),
                             ('fullApp', 'LinkCardUITests/LinkCardFullAppTouchTests.swift')]:
        if suite and suite != target:
            continue
        try:
            text = (root / filename).read_text()
        except OSError:
            continue
        cls = None
        for line in text.splitlines():
            m = re.search(r'^final class ([A-Za-z0-9_]+Tests): XCTestCase', line)
            if m:
                cls = m[1]
            m = re.search(r'\bfunc (test[A-Za-z0-9_]+)\(', line)
            if cls and m:
                methods.add(cls + '/' + m[1])
    return methods


def safe_progress(raw, allowed):
    """No free text, process names/arguments, paths, UUIDs or environment values."""
    raw = raw if type(raw) is dict else {}
    out = {}
    for key, values, default in [
        ('phase', PHASES, 'not-started'), ('timeout_at', PHASES | {'none'}, 'none'),
        ('simulator_boot_phase', BOOT_PHASES, 'not-started'),
        ('runner_process_state', PROCESS_STATES, 'unknown'),
        ('cleanup', {'not-started', 'complete', 'failed'}, 'not-started')]:
        value = raw.get(key)
        out[key] = value if type(value) is str and value in values else default
    for key in ['simulator_startup_seconds', 'elapsed_seconds']:
        value = raw.get(key)
        out[key] = round(value, 2) if type(value) in (int, float) and 0 <= value <= 3600 else None
    for key in ['tests_started', 'tests_completed']:
        value = raw.get(key)
        out[key] = value if type(value) is int and 0 <= value <= 100000 else None
    last = raw.get('last_public_test')
    out['last_public_test'] = last if type(last) is str and last in allowed else None
    return out


class Progress:
    def __init__(self, allowed):
        self.allowed = allowed
        self.started = set()
        self.completed = set()
        self.data = {'phase': 'not-started', 'timeout_at': 'none',
                     'simulator_boot_phase': 'not-started', 'runner_process_state': 'not-started',
                     'tests_started': 0, 'tests_completed': 0, 'last_public_test': None,
                     'cleanup': 'not-started'}

    def consume(self, line):
        # Match XCTest's two public output formats; never preserve the input line.
        m = re.search(r"Test Case '-\[(?:\w+\.)?(\w+) (test\w+)\]' (started|passed|failed|skipped)", line)
        if not m:
            m = re.search(r"Test case '(?:\w+\.)?(\w+)\.(test\w+)\(\)' (started|passed|failed|skipped)", line)
        if m:
            identifier = m[1] + '/' + m[2]
            if identifier in self.allowed:
                self.data['phase'] = 'testing'
                self.data['last_public_test'] = identifier
                self.started.add(identifier)
                if m[3] != 'started':
                    self.completed.add(identifier)
                self.data.update(tests_started=len(self.started), tests_completed=len(self.completed))
        elif re.search(r'Test Suite .* started|Testing started|\*\* TEST EXECUTE', line):
            if self.data['phase'] != 'testing':
                self.data['phase'] = 'test-startup'
        elif line.startswith(('CompileSwift', 'SwiftCompile', 'CompileC', 'Ld ', 'CodeSign ', 'SwiftEmitModule')):
            if not self.started:
                self.data['phase'] = 'build'


def reap_group(process):
    """Reap parent AND same-session descendants, including after parent exits."""
    state = 'exited'
    try:
        os.killpg(process.pid, signal.SIGTERM)
        state = 'terminated'
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        state = 'killed'
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    process.wait(timeout=5)
    return state


def boot_wait_phase(output):
    """Read only known simctl status phrases, returning no other log content."""
    if isinstance(output, bytes):
        output = output.decode('utf-8', errors='replace')
    last = 'waiting-boot'
    for line in (output or '').splitlines():
        for phrase, phase in [('Waiting on BackBoard', 'waiting-backboard'),
                              ('Waiting on Data Migration', 'waiting-data-migration'),
                              ('Waiting on System App', 'waiting-system-app')]:
            if phrase in line:
                last = phase
    return last


class BudgetExceeded(Exception):
    pass


class NativeRunner:
    def __init__(self, suite, budget, filename):
        self.suite, self.budget = suite, budget
        self.logs = Path('build/logs')
        self.logs.mkdir(parents=True, exist_ok=True)
        self.path = self.logs / filename
        self.progress = Progress(public_methods(suite=suite))
        self.result = {'status': 'not-run', 'suite': 'LinkCardTests' if suite == 'unit' else 'LinkCardUITests',
                       'runtime_downloaded': False}
        if suite == 'fullApp':
            self.result['scope'] = 'fullApp'
        self.started = time.monotonic()
        self.deadline = self.started + budget
        self.udid = None
        self.process = None

    def save(self):
        self.progress.data['elapsed_seconds'] = round(time.monotonic() - self.started, 2)
        self.result['runner'] = safe_progress(self.progress.data, self.progress.allowed)
        self.path.write_text(json.dumps(self.result, indent=2) + '\n')

    def command(self, command, cap=60, cleanup=False):
        remaining = cap if cleanup else min(cap, self.deadline - time.monotonic())
        if remaining <= 0:
            raise BudgetExceeded()
        p = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
        try:
            out, _ = p.communicate(timeout=remaining)
        except subprocess.TimeoutExpired as error:
            if command[:3] == ['xcrun', 'simctl', 'bootstatus']:
                self.progress.data['simulator_boot_phase'] = boot_wait_phase(error.output)
            reap_group(p)
            raise BudgetExceeded() from None
        if p.returncode:
            raise RuntimeError('native-command-failed')
        return out

    def boot(self):
        boot_start = time.monotonic()
        def phase(name):
            self.progress.data.update(phase=name, simulator_boot_phase=name)
            self.save()
        try:
            phase('inventory')
            inventory = json.loads(self.command(['xcrun', 'simctl', 'list', '--json'], 30))
            choices = [(runtime, d) for runtime, group in inventory['devices'].items()
                       if '.iOS-' in runtime for d in group
                       if d.get('isAvailable') and d['name'].startswith('iPhone') and d.get('deviceTypeIdentifier')]
            choices.sort(key=lambda x: (tuple(int(n) for n in re.findall(r'\d+', x[0])), x[1]['name']))
            if not choices:
                raise RuntimeError('no-installed-runtime')
            runtime, device = choices[0]
            phase('create')
            self.udid = self.command(['xcrun', 'simctl', 'create', 'LinkCard-' + self.suite,
                                      device['deviceTypeIdentifier'], runtime], 30).decode().strip()
            if not re.fullmatch(r'[A-Fa-f0-9-]{36}', self.udid):
                self.udid = None
                raise RuntimeError('invalid-created-device')
            # simctl boots the specified device headlessly. Opening Simulator.app
            # here may independently start its default device and compete for boot resources.
            phase('boot')
            self.command(['xcrun', 'simctl', 'boot', self.udid], 30)
            phase('bootstatus')
            self.command(['xcrun', 'simctl', 'bootstatus', self.udid, '-b'], 90)
            # bootstatus -b is simctl's blocking boot-readiness contract. Additional
            # list/spawn probes repeatedly timed out after it succeeded. Actual
            # executable readiness is verified by XCTest, within the same budget;
            # neither a booted device nor this flag alone can pass the release gate.
            self.progress.data['simulator_boot_phase'] = 'ready'
        finally:
            self.progress.data['simulator_startup_seconds'] = round(time.monotonic() - boot_start, 2)
            self.save()

    def execute(self, command, logfile):
        if time.monotonic() >= self.deadline:
            raise BudgetExceeded()
        with (self.logs / logfile).open('a') as output, (self.logs / logfile).open() as reader:
            reader.seek(0, os.SEEK_END)
            self.process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
            self.progress.data['runner_process_state'] = 'running'
            while True:
                for line in reader:
                    self.progress.consume(line)
                self.save()
                code = self.process.poll()
                if code is not None:
                    for line in reader:
                        self.progress.consume(line)
                    break
                if time.monotonic() >= self.deadline:
                    raise BudgetExceeded()
                time.sleep(0.5)
            self.progress.data['runner_process_state'] = 'exited'
            reap_group(self.process)
            self.process = None
        return code

    def prepare_products(self, derived, logfile):
        # Compile once while no test simulator is running. Copy immutable build
        # products into the fullApp's separate directory; never share live state.
        self.progress.data['phase'] = 'build'
        self.save()
        products = Path(derived) / 'Build/Products'
        if self.suite == 'unit':
            architecture = os.uname().machine
            assert architecture in {'arm64', 'x86_64'}
            command = ['xcodebuild', 'build-for-testing', '-project', 'LinkCard.xcodeproj',
                       '-scheme', 'LinkCard', '-configuration', 'Debug', '-sdk', 'iphonesimulator',
                       '-destination', 'generic/platform=iOS Simulator', '-derivedDataPath', derived,
                       'ARCHS=' + architecture, 'ONLY_ACTIVE_ARCH=YES',
                       'CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO',
                       'CODE_SIGN_IDENTITY=', 'DEVELOPMENT_TEAM=']
            if self.execute(command, logfile) != 0:
                raise RuntimeError('test-build-failed')
        else:
            source = Path('build/UnitDerivedData/Build/Products')
            assert (self.logs / 'native-products-ready').is_file()
            assert source.is_dir() and not products.exists()
            shutil.copytree(source, products, symlinks=True)
        plans = list(products.glob('*.xctestrun'))
        assert len(plans) == 1
        if self.suite == 'unit':
            (self.logs / 'native-products-ready').touch()
        return plans[0]

    def run(self, selections, bundle, logfile, derived):
        try:
            self.save()
            plan = self.prepare_products(derived, logfile)
            self.boot()
            self.progress.data['phase'] = 'test-startup'
            command = ['xcodebuild', 'test-without-building', '-xctestrun', str(plan),
                       '-destination', 'platform=iOS Simulator,id=' + self.udid, '-destination-timeout', '90',
                       '-parallel-testing-enabled', 'NO', '-maximum-concurrent-test-simulator-destinations', '1',
                       *selections, '-resultBundlePath', str(self.logs / bundle),
                       'CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO', 'CODE_SIGN_IDENTITY=', 'DEVELOPMENT_TEAM=']
            code = self.execute(command, logfile)
            self.result.update(status='passed' if code == 0 else 'failed', exit_code=code)
            self.progress.data['phase'] = 'results'
            summary = json.loads(self.command(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary',
                                              '--path', str(self.logs / bundle)], 30))
            keys = ['passedTests', 'failedTests', 'skippedTests', 'totalTestCount']
            counts = {key: summary.get(key) for key in keys}
            self.result['test_counts'] = counts
            expected = len(self.progress.allowed)
            if any(type(v) is not int for v in counts.values()) or counts != dict(zip(keys, [expected, 0, 0, expected])):
                self.result['status'] = 'failed'
        except BudgetExceeded:
            self.progress.data['timeout_at'] = self.progress.data['phase']
            self.result['status'] = 'timeout'
        except Exception:
            # Never forward exception text: simctl frequently includes local paths and UUIDs.
            self.result['status'] = 'failed'
        finally:
            last_phase = self.progress.data['phase']
            self.progress.data['phase'] = 'cleanup'
            self.save()
            clean = True
            if self.process is not None:
                try:
                    self.progress.data['runner_process_state'] = reap_group(self.process)
                except Exception:
                    self.progress.data['runner_process_state'] = 'unknown'
                    clean = False
            if self.udid:
                try:
                    self.command(['xcrun', 'simctl', 'shutdown', self.udid], 20, cleanup=True)
                except Exception:
                    # Already-shutdown is fine only if deletion succeeds below.
                    pass
                try:
                    self.command(['xcrun', 'simctl', 'delete', self.udid], 20, cleanup=True)
                except Exception:
                    clean = False
            self.progress.data['cleanup'] = 'complete' if clean else 'failed'
            self.progress.data['phase'] = 'complete' if self.result['status'] == 'passed' and clean else last_phase
            if not clean:
                self.result['status'] = 'failed'
            self.save()
        print(json.dumps(self.result, indent=2))
        return self.result
