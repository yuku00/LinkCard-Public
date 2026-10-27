# Mail 0.5.0 — native sender rules and explicit organization

Experimental RootHide tweak for **iOS 16.6 build 20G75**, arm64 + arm64e. Package ID remains `dev.mailrules.probe`. **This is an implemented client adapter, not a claim of device acceptance.** Host tests/CI are separate from real Mail/daemon/server testing.

## User flow

1. Open a native mailbox list → **插件**. Appearance is independently switchable.
2. Add a rule from the sender of one natively selected message, or enter an exact ASCII email address. Select the owning account/mailbox; choose this mailbox or this account's mailboxes. Edit, enable/disable and delete are available under rule management.
3. The **global hiding switch defaults off**. Rules do not move mail. Enable it explicitly to hide matching messages from supported current mailbox queries. Address comparison follows the native ANY/equality/case-insensitive predicate, preserving dots and +tags. No display-name/substring matching. Non-ASCII addresses need their ASCII/punycode representation.
4. To organize mail, select a rule → **打开同发件人整理预览**. This is a separate, exact inclusion query, even if hiding is disabled. The source is the selected account's mailbox(es) already present in the current list, not a silently expanded all-account search.
5. Optionally choose **在此账号新建邮箱…**. The real Mail `MailboxEditingController` is initialized with a single valid legacy account and no existing mailbox. The user saves in native UI; Mail validates the name/parent and submits through its own operation queue. Closing that UI is not a server-success receipt. Wait for the mailbox to appear in the native destination chooser.
6. Choose **预览已加载邮件并选择移动…**. The confirmation states sender, source and exact loaded count. Unresolved futures are not waited on synchronously or silently counted. Native stable item IDs are selected, then Mail's existing non-predictive move picker opens. Choosing a same-account destination is the actual native move action. Cross-account, same-source destination, mailbox-wide selections, mixed-thread objects, changed owner/scope or unmatched messages are rejected before execution. It does not move unloaded server history or auto-move future messages.
7. End organization to rebuild the current owner's normal query. Disable hiding for the original unfiltered plugin view. No saved predicate or model is replayed into another account.

## Production architecture

Only `Native.m`, `NativeCore.m`, `Theme.m` are linked. `Rules.m`, `RuleCore.m`, `Safety.m`, probe/diagnostic modules are historical, not loaded.

The synchronous `_reloadDataSource` call establishes a thread-local owner context with an immutable per-call frame; nested/unsupported owners mask that frame and `@finally` restores it. Only that owner's `EMMessageList.simpleMessageListForMailboxes:...transformPredicate:...` factory call gets a wrapped predicate transform. It explicitly copies the typed original transform and wrapper under MRC, preserves all factory arguments, and ANDs the original mailbox scope with per-mailbox sender conditions. Outside that call context the factory is unchanged. Native system filters are applied by Mail afterward; their filter/ignore arguments are not intercepted or replayed.

**When rules or organization apply, the affected owner displays native individual messages, not grouped threads.** This is deliberate: filtering/moving a whole mixed-sender thread would be incorrect. The original stable message IDs, native data source, selection model and reading path remain in use. The system's thread preference is not written; it resumes when the local rule query is removed. Unified lists are supported when their supplied mailboxes have stable physical identities; each exclusion branch belongs only to its originating mailbox/account. Search controllers and smart/nonphysical scopes retain their original models.

Native sender factories are verified on freshly allocated synthetic EMMessage objects with populated senderList, including positive/negative ANY, case, prefix/domain, +tag/dot, empty and mixed arrays. The returned AST must be equality with case-insensitive options and an identifier-only key path. Derived getters need not be ObjC declared properties (the old gate wrongly assumed that). A failed contract leaves that list's original query unchanged; it never falls back to hiding cells or entire threads. This runtime self-test is not a claim that an actual device passed it.

Organization uses the existing selection model and `_showTransferPickerForNonPredictiveMoveOfMessages:`. A local stamp on each move interaction retains the expected owner/rule/scope. The actual `MFMoveMessageTriageInteraction` execution is guarded against repeated submission, and its native `(interaction, didPerform)` completion is forwarded once even on a repeated/reentrant callback. Unstable selection configuration and late status updates for another preview are rejected. Statuses distinguish handoff, not performed and performed/pending synchronization. No per-item server success is invented. Native errors/permissions and synchronization remain Mail's responsibility. There are no guessed RPCs, new credentials, direct repository transfer/create actions or custom copy+delete implementation.

## Isolation and appearance

Configuration is independent: `dev.mailrules.native5` (stable serialized object identities; no migration of old data). Appearance uses `dev.mailrules.theme`. Mail's own preferences, favorites, account order, global mailbox picker, badges and message HTML are not written. No mailbox setter/data-source setter/filter-apply/section-prepare hook is installed. Native appearance changes are scoped to home, list and reading chrome and restored by Theme.m. No row-count or data-source substitution.

Close and reopen Mail after upgrade/uninstall because injected code cannot be hot-unloaded. Old 0.3.x configuration is preserved but not read. The uninstall script does not reset Mail data/preferences. The application-specific ABI gate does not broaden support to other OS builds.

## Verification and remaining acceptance

`python3 tests/check_native.py` checks the actual production manifest, forbidden global/replay/RPC APIs, native interaction wiring and appearance scope. The independent GitHub Actions workflow compiles and executes the actual **production NativeCore.m** with Foundation native-shaped models in both ARC and production MRC modes under AddressSanitizer (including deferred transforms, all factory arguments, and reentrant callbacks), then builds both iOS slices and verifies package identity and linked functionality. Fixtures cover multiple accounts, no-rule owner transitions, same-thread different senders, derived native getters, ANY/case, original filters/scope, stable IDs, new arrivals, disable/restore, failure-with-no-submit and pending-sync vs completion.

Host fixtures cannot execute system Email.framework or UIKit on an iOS device. Real-device acceptance is still required for runtime predicate self-test, injected UI, native list/reading/selection consistency, account-provider mapping, mailbox creation permissions, destination picker behavior and server synchronization. This release implements those client flows; it does not certify that they have succeeded on a user's private mailbox.

Public upload is an explicit source/test/config/workflow whitelist. IPA, extracted binaries/disassembly, screenshots, private runtime reports and local handoffs are excluded. No mail is accessed or modified during development.
