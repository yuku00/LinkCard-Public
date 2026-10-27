# Mail 0.4.0 — safety isolation + native appearance

**Sender hiding is unavailable in this release. Same-account mailbox creation and batch movement are also not implemented. This is not a complete rules release.**

Production links **Safety.m + Theme.m only**. Rules.m, RuleCore.m and Diagnostics.m remain historical source, not executable production modules. There are no data-source, mailbox setter, filter apply, section prepare, replay or identity hooks in this build. Existing rule data is neither read nor changed. No attempt is made to reset or reconstruct Mail favorites, account ordering, badges or messages.

The independent Theme module is restricted to com.apple.mobilemail, iOS 16.6 build 20G75, and the statically verified MailboxPickerOutlineController, MessageListViewController and ConversationViewController classes. Home gets native section side spacing (minimum 12 pt, preserving its original section and header); home/list get semantic grouped collection backgrounds; all three surfaces get consistent per-navigation-item standard/compact/scroll-edge appearances and semantic toolbars. Native title fonts follow Dynamic Type and system colors follow light/dark mode. Existing cells, swipe handlers, row counts/heights, flags, titles, account order, toolbar actions and message HTML are not replaced. The list is NOT rebuilt as a new inset-grouped data source.

The list's additional **插件** button describes the isolation status and offers an immediate theme toggle. The only preference write is themeEnabled in dev.mailrules.theme; no defaults are written at install. No Mail user setting is changed. Original appearance snapshots and weak toolbar ownership support restoration on page exit or disabling. Uninstall/upgrade requires closing and reopening Mail: loaded injected code is not hot-unloaded. The uninstall script preserves old rules and does not touch any preferences or mail data.

Verification: tests/check_safety.py checks the actual production manifest, forbidden APIs, visual scope, synthetic original-call sequences, multi-owner restoration and a reduced counterexample for old global replay. Model fixtures are not real-device proof. CI separately runs historical Foundation rule tests (not shipped), compiles both production architectures and verifies the package. No native visual/runtime acceptance is claimed without running on a compatible device.

The supplied decrypted IPA was inspected statically only. Email.framework is an external system dependency, not bundled source. No guarantee is made that a safe native sender-query contract has been established. A replacement implementation would require a per-owner original-query boundary, exact sender semantics, correct thread/search/unified-account ownership, new-message updates and count consistency; until then this release has no fallback to global filter replay. Real mailbox creation/movement remains a separate unimplemented repository-action transaction, not a simulated UI operation.

Source publication is limited to a whitelist of source, tests, metadata and workflow; excludes IPA, screenshots, extracted binaries, private reports and audit handoffs.

---

## Historical 0.3.1 documentation — NOT current functionality

Everything below describes the retired, unlinked implementation and is retained only for audit. Its restoration/safety claims are superseded by the 0.4.0 isolation above.


Experimental, default-off sender hiding for native Mail on iOS 16.6 build 20G75, RootHide arm64 + arm64e. Package identity remains `dev.mailrules.probe`, so this replaces 0.1.0 rather than installing alongside it. The production binary contains Rules.m + RuleCore.m + Diagnostics.m only, not the old metadata probe.

## Supported scope

Exactly one real, non-smart inbox mailbox; a persistent EMObjectID accountIdentifier (legacy NSString also accepted); non-threaded message list; not a search controller or active search. EMObjectID uses signature-checked isEphemeral and serializedRepresentation, with a persisted property-list representation-to-UUID map. No object description or memory address is used as identity. Unified inbox, smart mailboxes, threaded lists and other folders do not apply rules. The tweak never changes the user's thread setting. Rule management uses a separate account gate: rules remain editable when filtering is unsupported, if an original mailbox account can be identified. Unified lists expose only accounts actually supplied by their mailbox objects; no account inference is attempted.

Account activation and every newly added/edited rule default to OFF. Use the button to enter a complete ASCII email address, enable the rule, then explicitly enable the current account. Editing disables that rule until enabled again. Rules can be edited, toggled or deleted. Configuration is isolated by accountIdentifier in the independent CFPreferences domain dev.mailrules.rules. Only the domain portion is lowercased; +tags and dots are not removed. No display-name, quoted-local-part or IDN input support in this version.

## Native filtering and fail-closed predicate verification

All object/BOOL/method signatures in the scope and filter chain are checked against 20G75. Hooks are installed on MessageListViewController (not globally on NSObject/UIViewController), so its KVO subclass inherits them. No init method is replaced. Implementation uses MRC, scoped associations, and explicit teardown.

MessageListDataSource's global and section applyFilterPredicate:ignoreMessagesPredicate: methods preserve original filter and ignore arguments. The tweak adds `original AND NOT(native sender predicates)` only to the known owner data source; the original native filter pipeline handles loaded and future items. Nested global-to-section calls are guarded. Original arguments are retained for restoration, including section-specific calls. Scope setters, search presentation, reload and data-source replacement restore before transition. Returning to the list reevaluates rules. A disappearing list restores its original filter; returning reevaluates the current context. Enabling changed filters exits multi-selection through the signature-checked native _exitMultiSelectionForce: method, never guessed index paths.

The native predicate factory's object parameter does NOT establish its accepted runtime value type. Before using any real rule, we try only synthetic NSString / ECEmailAddress representations. Exact equality (operator 4), ANY (modifier 2), and case-insensitive options 1 are supported, with constant RHS. Direct comparisons retain the strict sender-address whitelist and options 0. For ANY, the key comes from the native returned AST, not a guessed VIP/emailAddresses field. On freshly allocated EMMessage objects populated only through signature-checked setSenderList:, each path component must be a declared object property with a zero-argument object getter; at most four components and no collection operators are allowed. Only then do synthetic fixtures prove its dependency on senderList and exact positive/negative behavior. FUNCTION, SUBQUERY, unchecked paths, substring matching and other options are rejected. Fixtures cover mixed sender arrays, nonmatching arrays, missing senders, case, prefixes, domains and retained +tags/dots. Each enabled address is rechecked against the same key/options without logging it. A failure pauses hiding with an explicit status; no wider predicate is substituted.

**The actual Email.framework factory cannot be executed by macOS host tests and is not bundled in the supplied Mail IPA. Static client VIP emailAddresses calls do not prove the sender predicate's field. Device diagnostics establish ANY/equality/case-insensitive options, but the key was redacted. 0.3.1 validates the native returned key on synthetic EMMessage models at runtime; it does not claim device validation has already passed. If metadata or fixtures fail, rule management remains available and hiding is paused.**

## Account ownership and native UI

A filter is bound to controller, dataSource, stable account key and the exact mailbox object. A separate dataSource-owner association survives turning filtering off, so an old controller cannot reclaim a source transferred to a new controller with no active rules. The signature-checked prepareSection:messageList: hook restores and detaches the old Recent binding before the original method replaces that section. Restoration requires all these to still match and the source association to still belong to that state. A reused source cannot receive another account/mailbox's saved predicate. Global native updates stay global; exclusions apply only to MessageListSectionRecent, preserving ignore arguments. Before known scope/source changes and list disappearance, restore the original filter. On an already changed context, discard stale restoration rather than replaying it into the new mailbox. Empty or ambiguous persisted identity mappings are rejected, never assigned to the first account.

The native inset-grouped management page copies its selected account, shows account name when verifiable plus a stable local suffix, account switch, individual rule state, and explicit unsupported/paused reasons. Rule counts are not message counts. Every mutation checks that the selected account still belongs to the originating controller; rule actions compare the current account snapshot and reload the all-accounts dictionary before saving, avoiding stale writes over other accounts. Editing a rule disables it. Dynamic Type, native semantic colors and SF Symbols are used. The UI never changes message ownership or location.

## Privacy and non-goals

No network code, password/token access, message logging, real-message metadata export, cell hiding, snapshot rewriting, global fetch interception, read/star/junk changes, mailbox creation or message movement. Selecting a message to create a rule is not implemented because no reliable itemID-to-sender result chain has been established. Only manual address entry is exposed; no placeholder move buttons.

The manual targeted-diagnostic action runs synthetic sender fixtures once, exports redacted predicate shapes and runtime method encodings through an explicit share sheet, then stops. It does not fetch messages or invoke mailbox creation / transfer actions. Constants and unknown key paths are redacted; 60-event, depth-5 and 8-child limits apply. This is not the original probe/report. Dynamic ECEmailAddress getters are validated using method signatures rather than only class method tables, supporting forwarding.

Not thread-safe: controller/filter state and diagnostic buffers assume Mail's serialized UI/filter lifecycle; concurrent callbacks are not supported or verified. Threaded/conversation filtering, unified inbox filtering, selected-message rule creation, custom folder scope, mailbox creation and message movement remain unimplemented.

Uninstall removes only dev.mailrules.rules.plist; upgrade keeps rules. Close Mail before uninstalling and reopen after installation/upgrade so no in-process preference cache or old injected dylib remains active. The package does not touch Mail's own preferences.

## Verification

Independent workflow `.github/workflows/mail-rules-roothide.yml` runs static production/privacy checks and executes the actual RuleCore.m against Foundation fixtures on macOS, then builds with RootHide Theos, checks package ID/version/architecture and verifies arm64 + arm64e dylib slices. Core fixtures cover scope combinations, address preservation, strict predicate AST rejection, filter composition/restoration, ignore preservation, new-arrival reevaluation and account isolation. These are host fixtures, not a substitute for device UI/lifecycle tests.

Source upload uses an explicit whitelist: this directory's production code, fixtures, package metadata, uninstall script and this README plus the independent workflow. No user reports, extracted research or mailbox addresses are uploaded.
