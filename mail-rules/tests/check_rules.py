from pathlib import Path
p=Path(__file__).resolve().parents[1]
code=(p/'Rules.m').read_text(); core=(p/'RuleCore.m').read_text(); make=(p/'Makefile').read_text()
assert 'MailRules_FILES = Rules.m RuleCore.m Diagnostics.m' in make
assert 'serializedRepresentation' in code and 'isEphemeral' in code
assert 'NSString *account=EditingAccount(owner)' in code
assert 'MRReadAddress(a)' in code and 'methodSignatureForSelector:' in core
assert 'addSelection:' not in code and '[self scope:' not in code
assert '- (void)diagnostics {' in code and 'MRDiagnosticExport()' in code
assert 'Probe.m' not in make and 'Metadata.m' not in make
assert 'Version: 0.3.1' in (p/'control').read_text()
for forbidden in ['NSURLSession', 'NSLog(', 'senderAddress description', 'setHidden:', 'deleteItemsAtIndexPaths:', 'applySnapshot:', 'EMMessageTransferAction', 'EMCreateMailboxChangeAction', 'synchronizeSettings']:
    assert forbidden not in code, forbidden
for expected in ['currentFilterPredicate','currentMessagesToIgnorePredicate','_exitMultiSelectionForce:','OBJC_ASSOCIATION_ASSIGN','class_addMethod','[s restore]','MRValidateNativeSenderPredicate','CFPreferencesSetAppValue','accountIdentifier']:
    assert expected in code, expected
assert 'NSKeyPathExpressionType' in core and 'NSConstantValueExpressionType' in core
assert 'predicateOperatorType != NSEqualToPredicateOperatorType' in core
assert 'c.options != 0' in core
assert 'remove|purge)' in (p/'layout/DEBIAN/postrm').read_text()
assert 'MRCombineSection(p,s->exclude,section)' in code
assert 'objc_getAssociatedObject(ds,&SourceOwnerKey)!=owner' in code
assert 'PrepareSectionHook' in code and 'PrepareSection(ds,cmd,section,messageList)' in code
assert code.index('[s restore];\n    PrepareSection') > code.index('static void PrepareSectionHook')
assert '==self && ContextMatches(self)' in code
assert 'boundMailbox=[Boxes(owner).firstObject retain]' in code
assert 'UITableViewStyleInsetGrouped' in code and '_account=[account copy]' in code
assert 'class_getProperty' in core and 'DeclaredPath' in core
assert 'CanEdit(self,account)' in code and 'Load()[account] ?: @{} isEqual:config' in code
print('PASS: production source exclusion, account/mailbox ownership, native-model validation, grouped UI and no mail writes')
