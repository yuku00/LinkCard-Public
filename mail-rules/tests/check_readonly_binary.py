#!/usr/bin/env python3
"""Inspect the actual Mach-O bytes, not source-only claims."""
from pathlib import Path
import sys
b=Path(sys.argv[1]).read_bytes()
forbidden=[
 'MR5State','MRState','MR5SenderContract','MR5And','MRDStart','MRDClear','MRTheme',
 'dev.mailrules.native5','dev.mailrules.rules','mail051-trace-r2','diagnostic_dry_run',
 'query.generated','install.query','install.move','install.create','install.theme',
 'applyFilterPredicate:','filteredMessageListWithPredicate:',
 '_showTransferPickerForNonPredictiveMoveOfMessages:','initWithMailbox:account:validAccounts:',
 'performInteractionWithCompletion:','_applyChangesAndDismissView',
 'Mail 规则与整理','输入发件人添加规则','从选中邮件的发件人添加','保存：此邮箱',
 '此列表规则未通过原生合成模型自检','请先在原生列表选择一封邮件',
 '地址校验失败','请选择邮件','开启简洁外观','关闭隐藏，恢复原始列表',
 'senderAddress','serializedRepresentation','valueForKey:',
 'CFPreferences','NSUserDefaults','NSURLSession','NSURLConnection','localizedDescription',
]
for item in forbidden:
 assert item.encode() not in b and item.encode('utf-16le') not in b, 'Forbidden binary string: '+item
required=['ROEntry','ROSession','ROViewer','ROButton','ROInstallObserver','ROGraph',
 'production modules: readonly/Entry.m','query mutation hooks:none; rule engine absent',
 'mailbox-picker-not-message-list','开始只读采集','停止分享','只读采集0.5.2']
for item in required:
 assert item.encode() in b or item.encode('utf-16le') in b, 'Required binary string missing: '+item
print('PASS: actual binary excludes old rule/native/theme prompts, functions, sensitive getters, preference/network APIs')
print('PASS: read-only entry, graph, session, observer and production declaration present')
