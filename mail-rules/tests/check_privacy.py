#!/usr/bin/env python3
import pathlib, plistlib, re, runpy, sys
root=pathlib.Path(__file__).resolve().parents[1]
if 'TWEAK_NAME = MailRules' in (root/'Makefile').read_text():
    runpy.run_path(str(root/'tests/check_rules.py'),run_name='__main__')
    production='\n'.join((root/n).read_text() for n in ['Rules.m','RuleCore.m','Diagnostics.m'])
    for token in ['NSURLSession','NSURLConnection','sqlite3','NSLog(','writeToFile:','writeToURL:','UIPasteboard']:
        assert token not in production, token
    assert plistlib.loads((root/'MailRules.plist').read_bytes())=={'Filter':{'Bundles':['com.apple.mobilemail']}}
    print('PASS: production privacy and Mail-only injection (legacy probe checks not applicable)')
    sys.exit(0)
source='\n'.join((root/n).read_text() for n in ['Probe.m','Metadata.m','Metadata.h'])
for token in ['objc_copyClassList(', 'objc_getClassList(', 'object_getIvar(', 'class_copyIvarList(', 'ivar_getOffset(', 'valueForKey:', 'valueForKeyPath:', 'performSelector:', 'method_exchangeImplementations(', 'method_setImplementation(', 'class_addMethod(', 'MSHook', '%hook', 'NSLog(', 'NSFileManager', 'NSUserDefaults', 'NSURLSession', 'NSURLConnection', 'sqlite3', 'writeToFile:', 'writeToURL:', 'UIPasteboard', 'NSTimer', 'dispatch_source_create', 'dlopen(', 'dlsym(']:
    assert token not in source, token
for expr in [r'\.(senderAddress|subject|body|account|mailbox|messageList|repository|query|selection|text|title|accessibilityLabel)\b(?!\s*=)', r'\[\w+\s+(senderAddress|subject|body|account|mailbox|repository|query|description|debugDescription)\]']:
    assert not re.search(expr,source), expr
assert 'sysctlbyname("kern.osversion"' in source
assert 'com.apple.mobilemail' in source and '20G75' in source
assert 'class_getSuperclass(c)' in source and 'protocol_copyProtocolList' in source
assert 'protocol_copyMethodDescriptionList' in source and 'protocol_copyPropertyList2' in source
assert 'object_getClass(c)' in source and 'method_copyArgumentType' in source
assert 'viewIfLoaded' in source and 'tableDataSource' in source and 'collectionDataSource' in source
assert 'capture:(UIButton *)button' in source and 'UIControlEventTouchUpInside' in source
assert 'window.isKeyWindow' in source and 'UIWindowLevelNormal' in source
assert '-fobjc-arc' in (root/'Makefile').read_text()
assert plistlib.loads((root/'MailProbe.plist').read_bytes())=={'Filter':{'Bundles':['com.apple.mobilemail']}}
assert '#define MP_VERSION @"0.1.0"' in source
for n in ['EMMessage','EMMessageListItem','EMConversation','EMCreateMailboxChangeAction','EMMessageListItemPredicates','EMMessageRepositoryInterface','EMMailboxRepositoryInterface','EMUndoMessageAction']:
    assert '@"'+n+'"' in source,n
print('PASS: static privacy/scope/entry/ABI/package identity checks (not a device test)')
