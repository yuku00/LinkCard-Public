#!/usr/bin/env python3
"""Four real UIApplication tests; fixed 1200s budget and default quiescence."""
from native_test_runner import NativeRunner

NativeRunner('fullApp', 1200, 'full-app-ui-result.json').run(
    ['-only-testing:LinkCardUITests'], 'FullApp.xcresult', 'full-app-ui-tests.log',
    'build/FullAppDerivedData')
# Tools/require_ui_gates.py still blocks publication on any failure or missing counts.
