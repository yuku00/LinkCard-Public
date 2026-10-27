# Mail Rules 0.2.0

Experimental, default-off sender hiding for native Mail on iOS 16.6 build 20G75, RootHide arm64 + arm64e. Package identity remains `dev.mailrules.probe`, so this replaces 0.1.0 rather than installing alongside it. The production binary contains Rules.m + RuleCore.m only, not the old metadata probe.

## Supported scope

Exactly one real, non-smart inbox mailbox; a stable NSString accountIdentifier; non-threaded message list; not a search controller or active search. Unified inbox, smart mailboxes, threaded lists and other folders do not apply rules. The tweak never changes the user's thread setting. A navigation-bar “规则” button explains unsupported scopes.

Account activation and every newly added/edited rule default to OFF. Use the button to enter a complete ASCII email address, enable the rule, then explicitly enable the current account. Editing disables that rule until enabled again. Rules can be edited, toggled or deleted. Configuration is isolated by accountIdentifier in the independent CFPreferences domain dev.mailrules.rules. Only the domain portion is lowercased; +tags and dots are not removed. No display-name, quoted-local-part or IDN input support in this version.

## Native filtering and fail-closed predicate verification

All object/BOOL/method signatures in the scope and filter chain are checked against 20G75. Hooks are installed on MessageListViewController (not globally on NSObject/UIViewController), so its KVO subclass inherits them. No init method is replaced. Implementation uses MRC, scoped associations, and explicit teardown.

MessageListDataSource's global and section applyFilterPredicate:ignoreMessagesPredicate: methods preserve original filter and ignore arguments. The tweak adds `original AND NOT(native sender predicates)` only to the known owner data source; the original native filter pipeline handles loaded and future items. Nested global-to-section calls are guarded. Original arguments are retained for restoration, including section-specific calls. Scope setters, search presentation, reload and data-source replacement restore before transition. Returning to the list reevaluates rules. A disappearing list freezes its rule state while the message preview is open. Enabling changed filters exits multi-selection through the signature-checked native _exitMultiSelectionForce: method, never guessed index paths.

The native predicate factory's object parameter does NOT establish its accepted runtime value type. Before using any real rule, we try only the known synthetic NSString / ECEmailAddress representations. The returned predicate must be a comparison AST with exact equality, no options, only senderAddress / senderAddress.stringValue / senderAddress.emailAddressValue or ANY senderList, and a constant RHS. FUNCTION, SUBQUERY, arbitrary key paths, substring matching and case-folded comparisons are rejected before evaluation. Synthetic fixtures check exact positive match, prefixes, different domains, domain case, retained +tags/dots and missing senders. Each enabled address is checked again without logging it. Failure disables the account's filtering and shows an explicit reason in the menu; it never silently substitutes a wider predicate.

**The actual Email.framework factory cannot be executed by the macOS host tests. Its concrete predicate shape and device behavior are not yet verified on 20G75. If the factory emits a shape outside the strict whitelist, 0.2.0 will offer rule management but refuse hiding. This is an explicit experimental gate, not a claim of verified on-device hiding.**

## Privacy and non-goals

No network code, password/token access, message logging, metadata export, cell hiding, snapshot rewriting, global fetch interception, read/star/junk changes, mailbox creation or message movement. Selecting a message to create a rule is not implemented because no reliable itemID-to-sender result chain has been established. Only manual address entry is exposed; no placeholder move buttons.

Uninstall removes only dev.mailrules.rules.plist; upgrade keeps rules. Close Mail before uninstalling and reopen after installation/upgrade so no in-process preference cache or old injected dylib remains active. The package does not touch Mail's own preferences.

## Verification

Independent workflow `.github/workflows/mail-rules-roothide.yml` runs static production/privacy checks and executes the actual RuleCore.m against Foundation fixtures on macOS, then builds with RootHide Theos, checks package ID/version/architecture and verifies arm64 + arm64e dylib slices. Core fixtures cover scope combinations, address preservation, strict predicate AST rejection, filter composition/restoration, ignore preservation, new-arrival reevaluation and account isolation. These are host fixtures, not a substitute for device UI/lifecycle tests.

Source upload uses an explicit whitelist: this directory's production code, fixtures, package metadata, uninstall script and this README plus the independent workflow. No user reports, extracted research or mailbox addresses are uploaded.
