#!/usr/bin/env python3
"""Complete native unit suite; fixed 420s budget includes simulator readiness."""
from native_test_runner import NativeRunner

selections = [
    '-only-testing:LinkCardTests/MistEffectLifecycleTests',
    '-only-testing:LinkCardTests/BLEConnectionPresentationTests',
    '-only-testing:LinkCardTests/MistBlurStoreTests',
    '-only-testing:LinkCardTests/WorkbenchPresentationTests',
    '-only-testing:LinkCardTests/FrameCodecTests',
    '-only-testing:LinkCardTests/FusionPresentationTests',
    '-only-testing:LinkCardTests/PN532IdentifyTests',
]
result = NativeRunner('unit', 420, 'mist-uikit-result.json').run(
    selections, 'MistLifecycle.xcresult', 'mist-uikit-tests.log', 'build/UnitDerivedData')
# No second simulator may start if cleanup could not be verified.
if result['runner']['cleanup'] != 'complete':
    raise SystemExit(1)
