# DateInfoProbe 0.4

SpringBoard-only, bounded diagnostic. It never reads user text, touch coordinates or URLs, never sends network requests, and does not hook global touch delivery. It inspects private recognizer target layout; inability to inspect or match means **unknown**, not absence of DateInfo behavior. It removes its targets at the end. The extra target and scans can affect timing or target iteration order. The package has not been validated on the user's physical device.

## What changed in 0.4

- The stored action selector is now **named on device** instead of inferred: the value is dereferenced only after `sel_isMapped` proves it is a real registered selector, otherwise it is reported as `unmapped`. Raw, stripped and pointer-authenticated comparisons are recorded beside it (`selector_match_raw` / `_stripped` / `_authenticated` / `_by_name`).
- A binding no longer requires the selector comparison to pass. The target class `DIClockTapTarget` is defined by `DateInfo.dylib`, so a class match already identifies the tweak's own gesture; such bindings are labelled `bound_by: target_class_only` rather than dropped. A 0.3 report where class matched 7 times but the selector never did therefore could not show whether a tap was delivered; 0.4 can.
- Each binding records hit-test evidence sampled at the gesture host centre with no live touch: which view would receive the tap, and whether it lies inside the tweak's own gesture host subtree (`hit_test_landing_inside_gesture_host`). A tap that lands on another view is a different fault than a tap that arrives and does nothing.
- The report adds a window inventory (class, level, hidden, alpha, frame, key flag, first root children) so a missing or covered floating capsule window is visible.
- The trigger file and output are `DateInfoProbe-v04.start` / `DateInfoProbe-v04.json`. A 0.3 report is never read, and the 0.4 run ignores the 0.3 trigger name.

## Start a single session

1. Install the RootHide package, respring, and unlock. An existing `/var/mobile/Library/Logs/DateInfoProbe-v04.json` prevents the new run from starting; first move or delete only your own earlier diagnostic output if you want another run. Never overwrite an unrelated file.
2. Within 10 minutes of injection, use Filza to create `/var/mobile/Library/Logs/DateInfoProbe-v04.start` as a **new, zero-byte regular file**, owned by mobile (UID 501), with a modification time later than injection. If an old start file exists, first move or delete it only if it is your own earlier trigger. The probe does not delete the trigger. If Filza creates files as root, set owner to mobile. Symlinks and non-empty files are rejected.
3. Switch from Filza back to the home screen immediately. The trigger is checked every 2 seconds; after detection there is a 20-second delay, then a 90-second sampling interval. Tap the DateInfo clock repeatedly during that interval — including one tap you are certain about. This is a file-triggered session, not an unlock trigger or a button.
4. After about 115 seconds from creating the trigger, open `/var/mobile/Library/Logs/DateInfoProbe-v04.json` in Filza. An empty, absent or invalid file means the session did not complete; do not treat it as a zero result. A `completed` record includes a unique UUID, UTC timestamps, per-scan window/foreground counts and stage observation deltas, final callback counts and removal attempts, the window inventory, and the binding records.
5. Stop future observation by uninstalling the diagnostic package and respringing; a respring during a session aborts it and may leave an empty or incomplete file. Save only the report you intend to share. The output is created exclusively and existing files are never replaced.

## Reading the result

- `recognizer_callback_total` above 0 with `last_callback_state` 3 means taps reach the recognizer's action. It still does not prove the original action or the capsule presentation ran.
- `recognizer_callback_total` 0 while `hit_test_landing_inside_gesture_host` is nonzero means the tap geometry reaches the tweak's own view but the recognizer never fires: look at `recognizer_enabled`, `number_of_taps_required`, `cancels_touches_in_view`, and whether a parent view cancels touches.
- `hit_test_landing_inside_gesture_host` 0 with samples taken means the centre of the hot zone is covered by another view or window: compare `hit_test_view_class`, `hit_test_superview_chain` and the window inventory.
- Counts are scan observations and can repeat; zero means unknown, not "no tap" and not "no matching gesture".

The probe samples main-thread view trees in small batches, at most one scan every 5 seconds, with a 10,000-view scan bound and at most 20 scan records. Long scans may take more than 5 seconds. Private UIKit layouts differ by iOS version, and DateInfo may not have loaded when the trigger is used.
