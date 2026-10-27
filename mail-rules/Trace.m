#import "Trace.h"
#import <objc/runtime.h>
#import <CommonCrypto/CommonHMAC.h>
#import <CommonCrypto/CommonDigest.h>
static unsigned char AccountKey[32];
static NSObject *Lock;
static BOOL Active,AllowSubmit;
static NSUInteger Generation,Sequence,Dropped;
static NSTimeInterval Began;
static NSMutableArray *Ring,*Critical;
static NSMutableDictionary *Totals,*Last,*Accounts;
static NSMapTable *Objects;
static NSString *Tag,*Started;
static NSMutableArray *InstallFacts; // bounded non-personal ABI declarations, not a recording session
static void Init(void);
void MRDDeclare(NSString *stage,NSString *selector,const char *expected,const char *actual,BOOL installed) {
 Init();@synchronized(Lock){
 if(!InstallFacts) InstallFacts=[NSMutableArray new];
 if(InstallFacts.count<32)[InstallFacts addObject:@{@"stage":stage,@"status":installed?@"success":@"skipped",@"fields":MRDABIFields(selector,expected,actual)}];
 }
}
static NSArray *Stages(void) {
 return @[@"session",@"tag",@"install.bundle",@"install.build",@"install.query",@"install.move",@"install.create",@"install.ui",@"install.theme",@"abi",@"ui.entry",@"ui.click",@"ui.transition",@"ui.lifecycle",@"scope.resolve",@"sender.factory",@"sender.ast",@"sender.selftest",@"rule.edit",@"rule.manage",@"rule.save",@"rule.toggle",@"rule.delete",@"reload.request",@"reload.enter",@"reload.local",@"reload.exit",@"thread.path",@"factory.hit",@"factory.transform",@"query.generated",@"list.refresh",@"selection.map",@"selection.item",@"preview.begin",@"preview.end",@"move.open",@"move.delegate",@"move.validate",@"move.perform",@"move.completion",@"create.open",@"create.commit",@"create.completion",@"theme.toggle",@"theme.apply",@"theme.section",@"share.lifecycle",@"error"];
}
static void Init(void) {static dispatch_once_t once;dispatch_once(&once,^{Lock=[NSObject new];});}
static NSString *Token(NSString *x,NSArray *allow) {return [allow containsObject:x]?x:@"redacted";}
static NSString *ReasonToken(NSString *x) {
 return Token(x,@[@"ok",@"entered",@"not_available",@"abi_mismatch",@"method_missing",@"build_mismatch",@"bundle_mismatch",@"guard",@"busy",@"search",@"scope_invalid",@"scope_changed",@"disabled",@"no_rules",@"model_contract",@"exception",@"cache",@"string_arg",@"address_arg",@"invalid_input",@"sync_failed",@"readback_mismatch",@"original_returned",@"no_tls",@"context_mismatch",@"off_main",@"subclass",@"future_pending",@"no_items",@"invalid_items",@"same_account",@"cross_account",@"diagnostic_dry_run",@"explicit_test_only",@"native_handoff",@"pending_sync",@"not_performed",@"user_cancel",@"user_submit",@"presentation_busy",@"not_visible",@"transition_cancelled",@"started",@"stopped",@"cleared",@"cap",@"unknown",@"native_exception",@"only_loaded",@"not_observed",@"user_tag",@"test",@"observed_snapshot"]);
}
static NSString *Type(id object) {
 NSString *name=object?NSStringFromClass([object class]):@"nil";
 return Token(name,@[@"nil",@"MessageListViewController",@"MailboxPickerOutlineController",@"ConversationViewController",@"EMMailbox",@"EMMessage",@"EMMessageList",@"MFMoveMessageTriageInteraction",@"MailboxEditingController",@"ECEmailAddress",@"NSComparisonPredicate",@"NSCompoundPredicate",@"UIAlertController",@"UIActivityViewController",@"UINavigationController",@"NSCollectionLayoutSection",@"NSObject"]);
}
static BOOL Syntax(NSString *s,NSString *characters,NSUInteger limit) {
 return [s isKindOfClass:NSString.class] && s.length<=limit && [s rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:characters].invertedSet].location==NSNotFound;
}
static NSDictionary *Fields(NSDictionary *raw) {
 NSMutableDictionary *out=[NSMutableDictionary dictionary];
 NSArray *numeric=@[@"accountID",@"targetAccountID",@"sameAccount",@"count",@"matched",@"enabled",@"ready",@"moveReady",@"createReady",@"hasLocal",@"hasTLS",@"ownerMatches",@"boxesMatch",@"selectionValid",@"sourceMatches",@"targetDifferent",@"resultPresent",@"isMain",@"section",@"operator",@"modifier",@"options",@"leftType",@"rightType",@"errorCode",@"saved",@"expectedCount",@"actualCount",@"generation",@"performed",@"safeMode",@"presentation",@"requested",@"filterMatches",@"schema"];
 for(NSString *key in raw) {
  id value=raw[key];
  if([numeric containsObject:key] && [value isKindOfClass:NSNumber.class]) out[key]=value;
  else if([@[@"expectedABI",@"actualABI"] containsObject:key]) {
   BOOL build=[raw[@"interface"] isEqual:@"kern.osversion"];
   BOOL validBuild=build && [value isKindOfClass:NSString.class] && [value rangeOfString:@"^[0-9]{2}[A-Z][0-9]{1,5}[a-z]?$" options:NSRegularExpressionSearch].location!=NSNotFound;
   // Only scalar/object/block encodings at these targeted boundaries; no quoted class/struct names.
   out[key]=([value isEqual:@"missing"] || validBuild || (!build && Syntax(value,@"v@#:?^BcCsSiIlLqQfdD0123456789 +-[]{}=()",160)))?value:@"redacted";
  }
  else if([key isEqual:@"interface"]) out[key]=Token(value,@[@"kern.osversion",@"_reloadDataSource",@"isThreaded",@"simpleMessageListForMailboxes:withRepository:shouldTrackOldestItems:shouldUpdateDisplayDate:sortDescriptor:transformPredicate:ignoreMessageAdditionsPredicate:",@"setDelegate:",@"performInteractionWithCompletion:",@"_applyChangesAndDismissView",@"viewDidAppear:",@"viewWillAppear:",@"viewWillDisappear:",@"traitCollectionDidChange:",@"_configuredSectionForSection:layoutEnvironment:",@"isEphemeral",@"serializedRepresentation",@"objectID",@"isSmartMailbox",@"accountIdentifier",@"mailboxes",@"emailAddressWithString:",@"emailAddressValue",@"stringValue",@"predicateForMessagesWithSender:",@"setSenderList:",@"predicateForMessagesInMailboxes:",@"isSearchViewController",@"isSearching",@"itemID",@"name",@"account",@"messageListSelectionModel",@"currentMessageListItemSelection",@"messageListItems",@"displayMessage",@"resultIfAvailable",@"senderAddress",@"clearAll",@"disableSelectAll",@"dataSource",@"snapshot",@"itemIDs",@"itemIdentifiers",@"messageListItemForItemID:",@"selectItemWithItemID:",@"_showTransferPickerForNonPredictiveMoveOfMessages:",@"isSelectAll",@"accountsProvider",@"legacyMailAccountForObjectID:",@"initWithMailbox:account:validAccounts:",@"collectionView",@"delegate",@"messageListItemSelection",@"isSelectionValid",@"isPerformingDataSourceUpdates",@"itemIDsPendingConfiguration",@"itemIDsMissingMessageListItem",@"selectionWithMessageListItems:mailboxes:",@"targetMailbox"]);
  else if([key isEqual:@"keyPath"]) out[key]=Token(value,@[@"derivedSenders.stringValue",@"senderList",@"senderList.emailAddressValue",@"senderList.stringValue",@"senderList.emailAddressValue.stringValue",@"senderAddress",@"sender",@"emailAddressValue",@"stringValue"]);
  else if([key isEqual:@"path"]) out[key]=Token(value,@[@"input",@"selected",@"mailbox",@"account",@"toggle",@"delete",@"save",@"cancel",@"stop",@"share",@"view",@"start",@"clear",@"theme",@"rules",@"preview",@"move",@"create",@"main",@"background"]);
  else if([key isEqual:@"action"]) out[key]=Token(value,@[@"diagnostics",@"start",@"stop",@"report",@"clear",@"selected_sender",@"input_sender",@"manage",@"hide_off",@"hide_on",@"move_loaded",@"create",@"preview_end",@"edit",@"preview",@"delete",@"rule_off",@"rule_on",@"save_mailbox",@"save_account",@"move_picker",@"theme_off",@"theme_on",@"safe_mode",@"request_submit",@"allow_submit",@"cancel",@"choice"]);
  else if([key isEqual:@"errorDomain"]) out[key]=Token(value,@[NSCocoaErrorDomain,NSPOSIXErrorDomain,NSOSStatusErrorDomain,NSURLErrorDomain,@"other"]);
 }
 return out;
}
BOOL MRDActive(void) {Init();@synchronized(Lock){return Active;}}
NSUInteger MRDSession(void) {Init();@synchronized(Lock){return Active?Generation:0;}}
BOOL MRDCanSubmit(void) {Init();@synchronized(Lock){return !Active || AllowSubmit;}}
BOOL MRDRequireSubmit(NSString *stage,id object,BOOL stampedDryRun) {
 Init();@synchronized(Lock){
  if(stampedDryRun || (Active && !AllowSubmit)) {
   MRD(stage,@"blocked_by_diagnostic",@"diagnostic_dry_run",object,@{@"safeMode":@YES});return NO;
  }
  return YES;
 }
}
void MRDAllowTestSubmit(BOOL allow) {Init();@synchronized(Lock){if(Active) AllowSubmit=allow;} MRD(@"session",@"success",allow?@"explicit_test_only":@"diagnostic_dry_run",nil,@{@"safeMode":@(!allow)});}
void MRDClear(void) {Init();@synchronized(Lock){memset(AccountKey,0,sizeof(AccountKey));Active=NO;AllowSubmit=NO;[Ring release];Ring=nil;[Critical release];Critical=nil;[Totals release];Totals=nil;[Last release];Last=nil;[Accounts release];Accounts=nil;[Objects release];Objects=nil;[Tag release];Tag=nil;[Started release];Started=nil;Sequence=0;Dropped=0;}}
void MRDStart(void) {Init();@synchronized(Lock){MRDClear();arc4random_buf(AccountKey,sizeof(AccountKey));Generation++;Began=NSProcessInfo.processInfo.systemUptime;Ring=[NSMutableArray new];Critical=[NSMutableArray new];Totals=[NSMutableDictionary new];Last=[NSMutableDictionary new];Accounts=[NSMutableDictionary new];Objects=[[NSMapTable mapTableWithKeyOptions:NSPointerFunctionsWeakMemory|NSPointerFunctionsObjectPointerPersonality valueOptions:NSPointerFunctionsStrongMemory] retain];Started=[[NSDate date].description copy];Tag=[@"rules" copy];Active=YES;MRD(@"session",@"success",@"started",nil,@{@"safeMode":@YES,@"generation":@(Generation)});for(NSDictionary *fact in InstallFacts)MRD(fact[@"stage"],fact[@"status"],[fact[@"status"] isEqual:@"success"]?@"ok":([fact[@"stage"] isEqual:@"install.build"]?@"build_mismatch":@"abi_mismatch"),nil,fact[@"fields"]);}}
void MRDStop(void) {Init();@synchronized(Lock){if(!Active)return;MRD(@"session",@"success",@"stopped",nil,nil);Active=NO;AllowSubmit=NO;[Accounts removeAllObjects];[Objects removeAllObjects];}}
void MRDTag(NSString *tag) {Init();@synchronized(Lock){if(!Active)return;[Tag release];Tag=[Token(tag,@[@"rules",@"preview",@"move",@"create",@"theme"]) copy];MRD(@"tag",@"success",@"user_tag",nil,nil);}}
NSNumber *MRDAccount(NSString *identity) {Init();@synchronized(Lock){if(!Active || !identity.length || identity.length>4096)return @0;const char *bytes=identity.UTF8String;unsigned char digest[CC_SHA256_DIGEST_LENGTH];CCHmac(kCCHmacAlgSHA256,AccountKey,sizeof(AccountKey),bytes,strlen(bytes),digest);NSData *key=[NSData dataWithBytes:digest length:sizeof(digest)];NSNumber *n=Accounts[key];if(!n && Accounts.count<128){n=@(Accounts.count+1);Accounts[key]=n;}return n?:@0;}}
void MRDAt(NSUInteger session,NSString *stage,NSString *status,NSString *reason,id object,NSDictionary *fields) {
 Init();@synchronized(Lock){if(!Active || !session || session!=Generation)return;
 if(![Stages() containsObject:stage])return;
 status=Token(status,@[@"success",@"failed",@"skipped",@"pending",@"cancelled",@"blocked_by_diagnostic",@"userSubmitted"]);
 NSNumber *oid=object?[Objects objectForKey:object]:@0;
 if(object && !oid && Objects.count<512){oid=@(++Sequence);[Objects setObject:oid forKey:object];}
 NSMutableDictionary *e=[NSMutableDictionary dictionaryWithDictionary:@{@"seq":@(++Sequence),@"ms":@((NSUInteger)((NSProcessInfo.processInfo.systemUptime-Began)*1000)),@"stage":stage,@"status":status,@"reason":ReasonToken(reason),@"thread":NSThread.isMainThread?@"main":@"background",@"objectID":oid?:@0,@"type":Type(object),@"tag":Tag?:@"rules",@"fields":Fields(fields?:@{})}];
 Totals[stage]=@([Totals[stage] unsignedIntegerValue]+1);Last[stage]=e;
 if(Ring.count==600){[Ring removeObjectAtIndex:0];Dropped++;}[Ring addObject:e];
 if([status isEqual:@"failed"] || [status isEqual:@"blocked_by_diagnostic"] || [status isEqual:@"cancelled"] || [status isEqual:@"userSubmitted"] || [stage hasPrefix:@"install."] || [stage isEqual:@"session"]) {if(Critical.count==256)[Critical removeObjectAtIndex:128];[Critical addObject:e];}
 }}
void MRD(NSString *stage,NSString *status,NSString *reason,id object,NSDictionary *fields) {MRDAt(MRDSession(),stage,status,reason,object,fields);}
NSDictionary *MRDABIFields(NSString *selector,const char *expected,const char *actual) {
 return @{@"interface":selector?:@"unknown",@"expectedABI":expected?[NSString stringWithUTF8String:expected]:@"missing",@"actualABI":actual?[NSString stringWithUTF8String:actual]:@"missing"};
}
NSDictionary *MRDError(NSError *error) {return @{@"errorDomain":Token(error.domain?:@"other",@[NSCocoaErrorDomain,NSPOSIXErrorDomain,NSOSStatusErrorDomain,NSURLErrorDomain,@"other"]),@"errorCode":@(error.code)};}
void MRDAST(NSPredicate *p) {
 if(!MRDActive())return;
 if(![p isKindOfClass:NSComparisonPredicate.class]){MRD(@"sender.ast",@"failed",@"model_contract",p,nil);return;}
 NSComparisonPredicate *c=(id)p;
 MRD(@"sender.ast",@"success",@"ok",p,@{@"operator":@(c.predicateOperatorType),@"modifier":@(c.comparisonPredicateModifier),@"options":@(c.options),@"leftType":@(c.leftExpression.expressionType),@"rightType":@(c.rightExpression.expressionType),@"keyPath":c.leftExpression.expressionType==NSKeyPathExpressionType?c.leftExpression.keyPath:@"redacted"});
}
NSDictionary *MRDSnapshot(void) {Init();@synchronized(Lock){
 NSMutableDictionary *events=[NSMutableDictionary dictionary];for(NSDictionary *e in Ring)events[e[@"seq"]]=e;for(NSDictionary *e in Critical)events[e[@"seq"]]=e;
 NSArray *sorted=[[events allValues] sortedArrayUsingComparator:^NSComparisonResult(id a,id b){return [a[@"seq"] compare:b[@"seq"]];}];
 return @{@"schema":@1,@"version":MRD_VERSION,@"build":MRD_BUILD,@"filterExpected":@"com.apple.mobilemail",@"filterInstallation":@"not independently observed; install.bundle means dylib executing in Mail",@"start":Started?:@"not started",@"active":@(Active),@"generation":@(Generation),@"ringCap":@600,@"criticalCap":@256,@"dropped":@(Dropped),@"stages":Stages(),@"last":[[Last copy] autorelease]?:@{},@"totals":[[Totals copy] autorelease]?:@{},@"events":sorted?:@[]};
}}
NSString *MRDText(NSDictionary *snapshot) {
 NSMutableString *out=[NSMutableString stringWithFormat:@"Mail %@ / %@\nschema=1; session=%@; start=%@; active=%@\nFilter expected=com.apple.mobilemail; %@\nPrivacy: no addresses, content, real identifiers, predicate constants, paths, credentials or error descriptions.\nSafety: default dry-run; blocked_by_diagnostic means NOT submitted; cancelled means user/native cancellation, neither is a feature failure. Native didPerform is NOT server completion.\nMemory: ring=600, critical=256, evicted=%@. Object/account IDs are session-only; 0 means unavailable/capped.\n\nSTAGE SUMMARY (last observed; absent = not reached)\n",snapshot[@"version"],snapshot[@"build"],snapshot[@"generation"],snapshot[@"start"],snapshot[@"active"],snapshot[@"filterInstallation"],snapshot[@"dropped"]];
 for(NSString *stage in snapshot[@"stages"]){NSDictionary *e=snapshot[@"last"][stage];NSString *status=e?e[@"status"]:@"not reached";if([stage hasPrefix:@"install."] && [status isEqual:@"success"])status=@"installed";[out appendFormat:@"%@ | %@ | %@ | hits=%@\n",stage,status,e?e[@"reason"]:@"not_observed",snapshot[@"totals"][stage]?:@0];}
 [out appendString:@"\nDETAIL EVENTS (JSON lines; main/background, anonymous IDs, typed values, exact ABI only at targeted boundaries)\n"];
 for(NSDictionary *e in snapshot[@"events"]){NSData *data=[NSJSONSerialization dataWithJSONObject:e options:NSJSONWritingSortedKeys error:NULL];if(data)[out appendFormat:@"%@\n",[[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease]];}
 return out;
}
void MRDControl(NSString *status,NSString *reason,NSString *path) {
 Init();@synchronized(Lock){if(!Ring)return;BOOL was=Active;Active=YES;MRD(@"share.lifecycle",status,reason,nil,@{@"path":path});Active=was;}
}
void MRDShareError(NSError *error) {if(!error)return;Init();@synchronized(Lock){if(!Ring)return;BOOL was=Active;Active=YES;MRD(@"error",@"failed",@"native_exception",nil,MRDError(error));Active=was;}}
h":path});Active=was;}
}
void MRDShareError(NSError *error) {if(!error)return;Init();@synchronized(Lock){if(!Ring)return;BOOL was=Active;Active=YES;MRD(@"error",@"failed",@"native_exception",nil,MRDError(error));Active=was;}}
