#import "Diagnostics.h"
#import <objc/runtime.h>
static NSMutableArray *Events;
static BOOL Active;
void MRDiagnosticStart(void) { [Events release]; Events=[NSMutableArray new]; Active=YES; }
BOOL MRDiagnosticActive(void) { return Active; }
void MRDiagnosticRecord(NSString *event, NSDictionary *values) {
    if (!Active || Events.count>=60) return;
    [Events addObject:@{@"event":event,@"values":values}];
}
static NSDictionary *Expression(NSExpression *e) {
    NSMutableDictionary *d=[NSMutableDictionary dictionaryWithObject:@(e.expressionType) forKey:@"type"];
    if(e.expressionType==NSKeyPathExpressionType) {
        // Key paths can be data-derived. Export only explicitly known schema keys.
        NSString *key=e.keyPath;
        d[@"key"]=[@[@"senderAddress",@"senderAddress.stringValue",@"senderAddress.emailAddressValue",@"senderList",@"mailboxObjectIDs",@"accountIdentifier",@"read",@"flags.read",@"date",@"subject"] containsObject:key] ? key : @"<other-key>";
    }
    if(e.expressionType==NSConstantValueExpressionType) d[@"constant"]=@"<redacted>";
    return d;
}
static NSDictionary *Shape(NSPredicate *p,NSUInteger depth) {
    if(!p) return @{@"kind":@"nil"};
    if(depth>5) return @{@"kind":@"depth-limit"};
    if([p isKindOfClass:NSComparisonPredicate.class]) {
        NSComparisonPredicate *c=(id)p;
        return @{@"kind":@"comparison",@"operator":@(c.predicateOperatorType),@"modifier":@(c.comparisonPredicateModifier),@"options":@(c.options),@"left":Expression(c.leftExpression),@"right":Expression(c.rightExpression)};
    }
    if([p isKindOfClass:NSCompoundPredicate.class]) {
        NSCompoundPredicate *c=(id)p; NSMutableArray *a=[NSMutableArray array];
        for(NSPredicate *child in c.subpredicates) {if(a.count==8) break; [a addObject:Shape(child,depth+1)];}
        return @{@"kind":@"compound",@"type":@(c.compoundPredicateType),@"children":a};
    }
    return @{@"kind":@"opaque"};
}
NSDictionary *MRPredicateShape(NSPredicate *p) { @try {return Shape(p,0);} @catch(__unused NSException *e) {return @{@"kind":@"unavailable"};} }
NSString *MRDiagnosticExport(void) {
    Active=NO;
    NSMutableDictionary *declarations=[NSMutableDictionary dictionary];
    NSDictionary *targets=@{
        @"EMObjectID":@[@"serializedRepresentation",@"isEphemeral"],
        @"EMMessageTransferAction":@[@"initWithMessageListItems:destinationMailboxURL:copyMessages:",@"initWithMessageListItemSelection:destinationMailboxURL:copyMessages:"],
        @"EMCreateMailboxChangeAction":@[@"initWithMailboxName:parentMailbox:"],
        @"EMMailboxRepository":@[@"performMailboxChangeAction:"],
        @"EMMessageRepository":@[@"performMessageChangeAction:"],
        @"MessageListDataSource":@[@"messageListItemForItemID:",@"messagesInMessageListItem:",@"prepareSection:messageList:"]};
    for(NSString *name in targets) {
        NSMutableDictionary *methods=[NSMutableDictionary dictionary];
        for(NSString *sel in targets[name]) {Method m=class_getInstanceMethod(NSClassFromString(name),NSSelectorFromString(sel)); methods[sel]=m ? @(method_getTypeEncoding(m)) : @"absent";}
        declarations[name]=methods;
    }
    NSDictionary *report=@{@"version":@"0.3.0-targeted",@"events":Events ?: @[],@"declarations":declarations,@"limits":@"60 events; AST depth 5 / 8 children; memory only; constants redacted; no mailbox operations; submission/server completion not observed"};
    NSData *data=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:NULL];
    return [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
}
