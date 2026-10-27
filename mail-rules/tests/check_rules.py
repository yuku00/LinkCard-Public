from pathlib import Path
p=Path(__file__).resolve().parents[1]
code=(p/'Rules.m').read_text(); core=(p/'RuleCore.m').read_text(); make=(p/'Makefile').read_text()
assert 'MailRules_FILES = Rules.m RuleCore.m' in make
assert 'Probe.m' not in make and 'Metadata.m' not in make
assert 'Version: 0.2.0' in (p/'control').read_text()
for forbidden in ['NSURLSession', 'NSLog(', 'senderAddress description', 'setHidden:', 'deleteItemsAtIndexPaths:', 'applySnapshot:', 'EMMessageTransferAction', 'EMCreateMailboxChangeAction', 'synchronizeSettings']:
    assert forbidden not in code, forbidden
for expected in ['currentFilterPredicate','currentMessagesToIgnorePredicate','_exitMultiSelectionForce:','OBJC_ASSOCIATION_ASSIGN','class_addMethod','[s restore]','MRValidateSenderPredicate','CFPreferencesSetAppValue','accountIdentifier']:
    assert expected in code, expected
assert 'NSKeyPathExpressionType' in core and 'NSConstantValueExpressionType' in core
assert 'predicateOperatorType != NSEqualToPredicateOperatorType' in core
assert 'c.options != 0' in core
assert 'remove|purge)' in (p/'layout/DEBIAN/postrm').read_text()
print('PASS: production source exclusion, default-off/account scope, native-filter-only static checks')
