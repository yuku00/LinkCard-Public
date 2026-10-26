#!/usr/bin/env python3
"""Four real UIApplication tests; fixed 1200s budget and default quiescence."""
import os
from native_test_runner import NativeRunner

runner = NativeRunner('fullApp', 1200, 'full-app-ui-result.json')
selections = ['-only-testing:LinkCardUITests']
if os.environ.get('LINKCARD_UI_SCOPE') == 'sidebar':
    runner.result['scope'] = 'sidebar-diagnostic'
    selections = ['-only-testing:LinkCardUITests/LinkCardFullAppTouchTests/testSidebarActionsTabsSettingsAndSafety']
runner.run(
    selections, 'FullApp.xcresult', 'full-app-ui-tests.log',
    'build/FullAppDerivedData')
# Tools/require_ui_gates.py still blocks publication on any failure or missing counts.
