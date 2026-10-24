#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Bounded, single-line diagnostics with public-path mapping and secret redaction.
No source snippets, continuation blocks, commands or environment dumps are exported.
"""
import json
import os
from pathlib import Path
import re
import subprocess

MAX_LOG = 16 * 1024 * 1024
MAX_LINE = 4096
MAX_MESSAGE = 640
MAX_ITEMS = 12
# Recognize diagnostic envelopes, not whole English sentences or source vocabulary.
TOOLS = {'xcodebuild', 'swiftc', 'swift-frontend', 'clang', 'clang++', 'ld',
         'actool', 'ibtool', 'codesign'}
SEVERITY = re.compile(r'(?:^|:)\s*(fatal error|error|warning):\s*')
DIAGNOSTIC = re.compile(r'^(?:(.+?):\s*)?(fatal error|error|warning):\s*(.*)$')
SENSITIVE_KEY = r'(?:[\w-]*(?:token|secret|password|passwd|credential|authorization|api[_-]?key|private[_-]?key|access[_-]?key|signing[_-]?key|ssh[_-]?key|cookie)[\w-]*|(?:[\w-]*[_-])?(?:key|auth|pass|pwd)(?:[_-][\w-]*)?)'
SECRET_KEY = re.compile(SENSITIVE_KEY, re.I)
URL = re.compile(r'\b[a-z][a-z0-9+.-]*://[^\s<>\'\"]+|\bfile:[^\s<>\'\"]+', re.I)
PATH = re.compile(r'''(?P<q>['"])(?P<quoted>(?:/|\./|\.\./|~/|[A-Za-z]:\\)[^'"\n]+)(?P=q)|(?<![\w])(?:[A-Za-z]:\\|~?/|\.{1,2}/)[^\s'"<>;,()]+|\b[\w.-]+(?:/[^\s'"<>;,()]+)+|\b[\w.-]+\.(?:swift|h|hpp|o|a|dylib|framework|xcodeproj|pbxproj)\b''')
CREDENTIAL = re.compile(r'\b' + SENSITIVE_KEY + r'''['"]?\s*[:=]\s*(?:"[^"]*"|'[^']*'|[^\s,;]+)''', re.I)
TOKEN = re.compile(r'''\b(?:gh[pousr]_[\w]+|github_pat_[\w]+|glpat-[\w-]+|xox[baprs]-[\w-]+|sk-(?:proj-)?[\w-]+|AKIA[A-Z0-9]{16}|eyJ[\w-]+\.[\w-]+\.[\w-]+)\b|\b(?:Bearer|Basic)\s+['"]?[\w.+/~=-]+['"]?''', re.I)
PERSONAL = re.compile(r'\b[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}\b|\b[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\b', re.I)
UNSAFE = re.compile(r'''[`\\\x00-\x1f\x7f\ufffd]|-----BEGIN |\b(?i:command|invocation|environment|snippet|source(?: code)?|user(?:name| name)?|profile|phone|address)['"]?\s*[:=]|\b(?:export|setenv)\s|\b[A-Z_][A-Z0-9_]*=|\b(?:swiftc|xcodebuild|clang(?:\+\+)?|codesign|curl|sh|bash)\s+-|\[(?:tool:[^]]+|sdk|external-path)\]\s+-|\b(?:let|var)\s+\w+\s*[:=]|\b(?:func\s+\w+\s*\(|(?:class|struct)\s+\w+\s*\{)''')
REASONS = ('unrecognized-location', 'unsafe-payload', 'line-limit', 'external-location',
           'redacted', 'truncated', 'duplicate', 'limit', 'log-symlink', 'log-limit', 'read-error')


def map_path(name, root, sources):
    """Resolve every parent symlink; never promote an external basename to public."""
    if '\\' in name or name.startswith('~'):
        return '[external-path]'
    resolved = None
    try:
        path = Path(name)
        resolved = (path if path.is_absolute() else root / path).resolve()
        relative = resolved.relative_to(root.resolve()).as_posix()
        if relative in sources:
            return relative
    except (OSError, ValueError, RuntimeError):
        pass
    # Fixed, anchored toolchain roots only, not arbitrary paths containing 'SDK'.
    if re.match(r'^/(?:Applications/Xcode[^/]*\.app/Contents/Developer/|Library/Developer/CommandLineTools/)', str(resolved or '')):
        return '[sdk]'
    if name in {'/usr/bin/' + tool for tool in TOOLS}:
        return '[tool:' + Path(name).name + ']'
    return '[external-path]'


def redact(text, root, sources, environment):
    # Map paths BEFORE secret replacement; fully sanitize BEFORE truncation.
    def replace_path(match):
        name = match.group('quoted') or match.group(0)
        mapped = map_path(name, root, sources)
        return (match.group('q') or '') + mapped + (match.group('q') or '')
    def mapped(value):
        return PATH.sub(replace_path, URL.sub('[url]', value))
    text = mapped(text)
    # Match all rules against the same mapped text, then merge spans. Sequential
    # replacement can erase a token's prefix or a multi-word secret's first word.
    values = {mapped(v) for k, v in environment.items() if isinstance(v, str) and v
              and SECRET_KEY.fullmatch(k)}
    patterns = [TOKEN, CREDENTIAL, PERSONAL]
    if values:
        patterns.append(re.compile('|'.join(re.escape(v) for v in sorted(values, key=len, reverse=True))))
    spans = sorted((m.start(), m.end()) for pattern in patterns for m in pattern.finditer(text))
    merged = []
    for start, end in spans:
        if merged and start <= merged[-1][1]:
            merged[-1][1] = max(end, merged[-1][1])
        else:
            merged.append([start, end])
    for start, end in reversed(merged):
        text = text[:start] + '[redacted]' + text[end:]
    return text


def location(prefix, root, sources):
    if not prefix:
        return '[compiler]', None, None
    if prefix in TOOLS:
        return '[tool:' + prefix + ']', None, None
    match = re.fullmatch(r'(.+?):([0-9]{1,7})(?::([0-9]{1,5}))?', prefix)
    name, line, column = (match.groups() if match else (prefix, None, None))
    if (line and int(line) == 0) or (column and int(column) == 0):
        return None
    if not (name in sources or '/' in name or '\\' in name or
            re.search(r'\.(?:swift|[chm]|mm|hpp|xcodeproj|xcworkspace|pbxproj|storyboard|xib)$', name)):
        return None
    return map_path(name, root, sources), int(line) if line else None, int(column) if column else None


def public_sources(root):
    """The tracked public trees are the allowlist; source contents are never read."""
    try:
        result = subprocess.run(['git', 'ls-files', '-z', '--', 'LinkCard', 'LinkCardTests',
                                 'LinkCardUITests', 'Reference', 'LinkCard.xcodeproj'],
                                cwd=root, capture_output=True, check=True)
    except (OSError, subprocess.CalledProcessError):
        return {}
    names = {name: None for name in result.stdout.decode().split('\0') if name}
    if 'LinkCard.xcodeproj/project.pbxproj' in names:
        names['LinkCard.xcodeproj'] = None
    return names


def extract(path, root, sources, environment):
    items, seen = [], set()
    result = {'items': [], 'omitted': 0, 'read_status': 'read',
              'candidates': {'error': 0, 'warning': 0}, 'retained': 0,
              'reasons': dict.fromkeys(REASONS, 0)}
    reasons = result['reasons']
    def reject(reason):
        reasons[reason] += 1
        result['omitted'] += 1
    try:
        # Reject symlinked log parents as well as symlinked log files.
        if any(p.is_symlink() for p in (path, *path.parents)):
            reasons['log-symlink'] += 1
            result['read_status'] = 'rejected'
            return result
        if path.stat().st_size > MAX_LOG:
            reasons['log-limit'] += 1
            result['read_status'] = 'rejected'
            return result
        with path.open(errors='replace') as stream:
            for raw in stream:
                text = raw.rstrip('\r\n').strip(' ')
                marker = SEVERITY.search(text)
                # Apple ld also emits errors without the literal 'error:'.
                implicit = bool(re.match(r'^ld: (?:library not found|framework .+ not found|symbol\(s\) not found|duplicate symbol|Undefined symbols|file not found|building for .+but linking)', text)) and not marker
                if not marker and not implicit:
                    continue
                severity = 'warning' if marker and marker.group(1) == 'warning' else 'error'
                result['candidates'][severity] += 1
                if len(raw) > MAX_LINE:
                    reject('line-limit')
                    continue
                match = DIAGNOSTIC.fullmatch(text)
                if implicit:
                    prefix, message = 'ld', text[4:]
                elif match:
                    prefix, _, message = match.groups()
                else:
                    reject('unrecognized-location')
                    continue
                loc = location(prefix, root, sources)
                if loc is None:
                    reject('unrecognized-location')
                    continue
                filename, line, column = loc
                if filename == '[external-path]':
                    reasons['external-location'] += 1
                clean = redact(message, root, sources, environment)
                clean_file = redact(filename, root, sources, environment)
                if clean != message or clean_file != filename:
                    reasons['redacted'] += 1
                if not clean.strip() or UNSAFE.search(clean):
                    reject('unsafe-payload')
                    continue
                if len(clean) > MAX_MESSAGE:
                    reasons['truncated'] += 1
                    clean = clean[:MAX_MESSAGE - 1] + '…'
                item = {'file': clean_file, 'line': line, 'column': column,
                        'severity': severity, 'message': clean}
                # Dedup on the final public representation, including truncation.
                key = tuple(item.values())
                if key in seen:
                    reasons['duplicate'] += 1
                    continue
                seen.add(key)
                items.append(item)
    except OSError:
        result['read_status'] = 'missing'
        reasons['read-error'] += 1
        return result
    items.sort(key=lambda item: item['severity'] != 'error')
    reasons['limit'] = max(0, len(items) - MAX_ITEMS)
    result['omitted'] += reasons['limit']
    result['items'] = items[:MAX_ITEMS]
    result['retained'] = len(result['items'])
    return result


def make_diagnostics(root, environment):
    sources = public_sources(root)
    logs = root / 'build/logs'
    stages = {}
    for stage, name in [('release', 'build-package.log'), ('unit', 'mist-uikit-tests.log'), ('fullApp', 'full-app-ui-tests.log')]:
        stages[stage] = extract(logs / name, root, sources, environment)
    # One publication budget for the complete report, not twelve per stage.
    # Reserve it for errors across all stages before retaining any warnings.
    ranked = sorted(((name, index, item) for name, report in stages.items()
                     for index, item in enumerate(report['items'])),
                    key=lambda entry: entry[2]['severity'] != 'error')
    retained = {(name, index) for name, index, _ in ranked[:MAX_ITEMS]}
    for name, report in stages.items():
        items = [item for index, item in enumerate(report['items']) if (name, index) in retained]
        removed = len(report['items']) - len(items)
        report['reasons']['limit'] += removed
        report['omitted'] += removed
        report['items'] = items
        report['retained'] = len(items)
    return {'schema': 1, 'kind': 'minimal-compiler-diagnostics', 'stages': stages,
            'policy': 'Single-line diagnostics; public paths mapped, other paths and credentials redacted before limits; no context exported.'}


if __name__ == '__main__':
    output = Path('build/public')
    output.mkdir(parents=True, exist_ok=True)
    (output / 'compiler-diagnostics.json').write_text(json.dumps(make_diagnostics(Path.cwd(), os.environ), indent=2) + '\n')
