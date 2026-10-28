# Files DualPane 0.7.10 — optional read-only layout snapshot

This is a diagnostic increment over 0.7.9, **not a fix** for the ordinary-file title's right-side empty space. Prior host doubles did not reveal the actual device cell constraints. The existing width/geometry predicates, constants and setters are unchanged; `tests/check_0710.py` reverses observation-only additions and verifies the pinned 0.7.9 SHA256.

## One manual snapshot

1. Optionally install the RootHide package, then relaunch Files and enter the dual panes. No tool installs or collects on the device automatically.
2. In one pane, open a directory with **two ordinary files and one folder visible** in list mode. There is no need to select files, take screenshots, open documents or visit multiple directories. Keep the directory still during collection.
3. Tap that pane's header `…` → **采集当前列表布局** → **只读采集一次**. Cancellation does nothing. The first two visible regular files and first visible folder are preferred, not directory-wide enumeration.
4. The report is already captured before its sheet opens. Tap **复制** or **分享** only if you want to send its text. Send one complete text report.
5. **返回双栏** dismisses only the report navigation controller. **重开最近布局报告** (or the capture action again) reopens the in-memory report without another capture. Process exit clears it. A failed empty capture leaves retry available.

## Exact scope and privacy

- Main-thread view reads for at most 3 selected visible cells. To choose these, bounded discovery checks at most 64 controller-container views and up to 24 already-visible cells. File/folder/symlink resource flags are read on a background queue; no directory enumeration, content read, provider download or file coordination is requested.
- Unknown/unavailable type metadata is explicitly `unknown`; if fewer preferred categories are available, up to 3 unknown visible cells can fill the sample. Reused, moved or offscreen candidates are skipped after metadata returns. No automatic scrolling or navigation.
- Per cell: at most 100 full view records, 500 active constraints, 2,000 constraint inspections and 400 anonymous object references. Total full view/constraint limits are 300/1,500. Truncation and discovery limits are explicit. Getter/ancestor/connected constraint geometry comes first; not a depth-180 whole-tree dump.
- Reports include real runtime `class`/`isa`, actual ABI-checked getter status and returned object IDs, bounds/frame in cell coordinates, intrinsic size, margins, label typography, compression/hugging, stack allocation/custom spacing, relevant guide/constraint endpoint IDs, active equations and accessory/status view geometry where present in the bounded graph.
- All label text, including dates and attributed text, becomes only UTF-16 `length` and `containsEllipsis` (U+2026 or three dots). No title/date text, filename, path, URL string, account, image bytes, object address, error description or custom constraint identifier is exported. Only exact fixed UIKit constraint identifiers are allowlisted; other identifiers are `redacted`.
- IDs are local to each cell graph. `0` means nil or exhausted identity budget; `reference_only` means an endpoint identified but outside full geometry budget. See `budget.truncated` before treating missing detail as evidence of absence.
- No constraint setter, forced `layoutIfNeeded`, private ivar/Swift offset, selection change, data source change or home/seed logic in capture. No automatic upload, persistent report/log, clipboard write or screenshot. The only retained report is process memory.

## Decision evidence

`styleResult` distinguishes public/native/unsupported. `publicContent` identifies actual public configuration type and the public fit/matching gates. `lastNativeDecision` records fixed rejection enums at the **last ordinary styling event**, not a replayed styling pass during capture. `reasonMeanings` explains every code. `cache` specifies the early-return hit checks; `planDecision` preserves the original plan's rejection reasons across hits, rather than hiding them behind `cached_not_replanned`. Native saved geometry/trailing/pending and pending view IDs are separate. A trailing proof can reject an optional label while the whole plan succeeds; inspect the top-level plan status as well as the first rejected proof.

One bounded last-decision dictionary is retained per live cell (plus its one original plan on cache hits), without a recorder/history, text, paths or I/O. No extra layout event or retry is introduced. Cache results describe the last ordinary style event, not an assertion that a fresh solver pass ran at capture time.

## Validation boundaries

- Static checks cover privacy, bounded capture, background metadata/JSON encoding, capture-before-sheet ordering, safe confirmation/report dismissal, report reuse and exact observation-only delta.
- A macOS Foundation/CoreGraphics fixture executes the **production `FPLCell` and graph serializer** to test title/date anonymization, real returned getter identity/ABI handling on synthetic objects, relationship completeness, identifier allowlist, budget truncation, original proof retention across cache hits and zero writes during capture.
- Existing style/core/bridge/preview/location/state fixtures and real RootHide Theos arm64 + arm64e build/signature verification remain enabled.
- These fixtures do not establish the real device layout cause or validate actual UIKit presentation. The ordinary-file right-side whitespace remains unresolved until one optional actual-device snapshot supplies the missing constraints. No on-device collection or installation has been performed by the build tools.
