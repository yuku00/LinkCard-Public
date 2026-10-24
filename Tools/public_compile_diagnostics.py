#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Fail-closed compiler diagnostics: public source locations and known grammar only.
Never export source snippets, command lines, arbitrary log text or environment data.
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
# Dynamic text must be quoted and composed entirely of identifiers already in
# public Swift source (plus compiler language terminology), never arbitrary prose.
Q = r"'([A-Za-z0-9_ .,:?<>()[\]&=!+-]{1,180})'"
GRAMMAR = [
    r"the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions",
    r"unable to type-check this expression in reasonable time",
    r"cannot find " + Q + r" in scope",
    r"cannot find type " + Q + r" in scope",
    r"cannot infer contextual base in reference to member " + Q,
    r"generic parameter " + Q + r" could not be inferred",
    r"type of expression is ambiguous without a type annotation",
    r"ambiguous use of " + Q,
    r"invalid redeclaration of " + Q,
    r"value of type " + Q + r" has no member " + Q,
    r"type " + Q + r" has no member " + Q,
    r"cannot convert value of type " + Q + r" to expected argument type " + Q,
    r"cannot convert return expression of type " + Q + r" to return type " + Q,
    r"cannot assign value of type " + Q + r" to type " + Q,
    r"cannot assign to property: " + Q + r" is a get-only property",
    r"cannot assign to property: " + Q + r" setter is inaccessible",
    r"cannot use mutating member on immutable value: " + Q + r" is immutable",
    r"cannot call value of non-function type " + Q,
    r"cannot call value of non-function type " + Q + r"\?",
    r"cannot convert value of type " + Q + r" to closure result type " + Q,
    r"type " + Q + r" does not conform to protocol " + Q,
    r"return type of (?:property|instance method) " + Q + r" requires that " + Q + r" conform to " + Q,
    r"(?:instance method|initializer|referencing instance method|referencing initializer|static method) " + Q + r"(?: on " + Q + r")? requires (?:that (?:the types )?)?" + Q + r" (?:conform to|be equivalent to|inherit from) " + Q,
    r"missing argument for parameter " + Q + r" in call",
    r"extra argument " + Q + r" in call",
    r"extra arguments at positions #[0-9]+(?:, #[0-9]+)* in call",
    r"incorrect argument label(?:s)? in call \(have: " + Q + r", expected: " + Q + r"\)",
    r"argument " + Q + r" must precede argument " + Q,
    r"missing argument label " + Q + r" in call",
    r"extraneous argument label " + Q + r" in call",
    r"expected (?:expression|type|pattern|declaration|identifier|member name following " + Q + r")",
    r"expected " + Q + r" (?:in|after|to end) (?:expression|argument list|closure|parameter list|declaration|function call)",
    r"consecutive (?:statements|declarations) on a line must be separated by " + Q,
    r"closure containing a declaration cannot be used with result builder " + Q,
    r"closure containing control flow statement cannot be used with result builder " + Q,
    r"function declares an opaque return type, but (?:has no return statements in its body from which to infer an underlying type|the return statements in its body do not have matching underlying types)",
    r"cannot use explicit " + Q + r" statement in the body of result builder " + Q,
    Q + r" is (?:inaccessible due to " + Q + r" protection level|only available in iOS [0-9.]+ or newer|unavailable in iOS)",
    r"call to main actor-isolated (?:instance method|initializer|static method) " + Q + r" in a synchronous nonisolated context",
    r"main actor-isolated property " + Q + r" can not be referenced from a nonisolated context",
    r"result of call to " + Q + r" is unused",
    r"immutable value " + Q + r" was never used; consider replacing with " + Q + r" or removing it",
    r"variable " + Q + r" was never mutated; consider changing to " + Q + r" constant",
]
PATTERNS = [re.compile(p) for p in GRAMMAR]
BLOCKED = re.compile(r"(?:gh[pousr]_|github_pat_|Bearer\s|https?://|file:|://|/Users/|/home/|/private/|/var/|\\|[\x00-\x1f\x7f])", re.I)
WORDS = set('Swift SwiftUI Foundation UIKit View AnyView some any Self self Type Element Optional Never Void String Int Double Float Bool Binding State Published CGFloat CGPoint CGSize CGRect Sendable MainActor ViewBuilder private fileprivate internal public open let var return init buildExpression T V Content Label nil true false async throws inout get set _'.split())


def public_sources(root):
    result = subprocess.run(['git', 'ls-files', '-z', '--', 'LinkCard', 'LinkCardTests', 'LinkCardUITests', 'Reference'], cwd=root, capture_output=True, check=True)
    sources = {}
    for name in result.stdout.decode().split('\0'):
        path = root / name
        if name.endswith('.swift') and not path.is_symlink() and path.is_file():
            sources[name] = path.read_text()
    return sources


def extract(path, root, sources, environment):
    items, omitted = [], 0
    words = WORDS | set(re.findall(r'[A-Za-z_][A-Za-z_0-9]*', '\n'.join(sources.values())))
    values = [v for k, v in environment.items() if isinstance(v, str) and v and
              (len(v) >= 4 or re.search(r'token|secret|password|credential|key', k, re.I))]
    if path.is_symlink():
        return {'items': [], 'omitted': 0, 'read_status': 'rejected'}
    try:
        if path.stat().st_size > MAX_LOG:
            return {'items': [], 'omitted': 0, 'read_status': 'rejected'}
        with path.open(errors='replace') as stream:
            for raw in stream:
                if ': error:' not in raw and ': warning:' not in raw:
                    continue
                if len(raw) > MAX_LINE:
                    omitted += 1
                    continue
                match = re.fullmatch(r'(.+\.swift):([0-9]{1,7}):([0-9]{1,5}): (error|warning): (.+)\n?', raw.rstrip('\n'))
                if not match:
                    omitted += 1
                    continue
                filename, line, column, severity, message = match.groups()
                prefix = str(root.resolve()) + '/'
                relative = filename[len(prefix):] if filename.startswith(prefix) else filename
                accepted = relative in sources and not BLOCKED.search(relative) and not BLOCKED.search(message)
                accepted = accepted and 0 < int(line) <= len(sources.get(relative, '').splitlines()) and 0 < int(column) <= 4096
                accepted = accepted and len(message) <= MAX_MESSAGE and not any(v in message or v in relative for v in values)
                grammar = next((p.fullmatch(message) for p in PATTERNS if p.fullmatch(message)), None) if accepted else None
                accepted = accepted and grammar is not None
                if accepted:
                    for fragment in grammar.groups():
                        if fragment and not set(re.findall(r'[A-Za-z_][A-Za-z_0-9]*', fragment)) <= words:
                            accepted = False
                if not accepted:
                    omitted += 1
                    continue
                item = {'file': relative, 'line': int(line), 'column': int(column), 'severity': severity, 'message': message}
                if item not in items:
                    items.append(item)
    except OSError:
        return {'items': [], 'omitted': 0, 'read_status': 'missing'}
    # Errors take priority over warnings; at most twelve 640-character messages.
    items.sort(key=lambda item: item['severity'] != 'error')
    omitted += max(0, len(items) - MAX_ITEMS)
    return {'items': items[:MAX_ITEMS], 'omitted': min(omitted, 100000), 'read_status': 'read'}


def make_diagnostics(root, environment):
    sources = public_sources(root)
    logs = root / 'build/logs'
    stages = {}
    for stage, name in [('release', 'build-package.log'), ('unit', 'mist-uikit-tests.log'), ('fullApp', 'full-app-ui-tests.log')]:
        stages[stage] = extract(logs / name, root, sources, environment)
    return {'schema': 1, 'kind': 'minimal-compiler-diagnostics', 'stages': stages,
            'policy': 'Known compiler grammar and public Swift source locations only; unknown content omitted.'}


if __name__ == '__main__':
    output = Path('build/public')
    output.mkdir(parents=True, exist_ok=True)
    (output / 'compiler-diagnostics.json').write_text(json.dumps(make_diagnostics(Path.cwd(), os.environ), indent=2) + '\n')
