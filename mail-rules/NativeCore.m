#import "NativeCore.h"
#import "Trace.h"
NSString *MR5Address(NSString *value) {
    if (![value isKindOfClass:NSString.class]) return nil;
    NSString *s=[value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSArray *p=[s componentsSeparatedByString:@"@"];
    if(p.count!=2 || ![p[0] length] || ![p[1] length]) return nil;
    NSCharacterSet *local=[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.!#$%&'*+-/=?^_`{|}~"];
    NSCharacterSet *domain=[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-"];
    if([p[0] rangeOfCharacterFromSet:local.invertedSet].location!=NSNotFound || [p[1] rangeOfCharacterFromSet:domain.invertedSet].location!=NSNotFound) return nil;
    if([p[0] hasPrefix:@"."] || [p[0] hasSuffix:@"."] || [p[0] containsString:@".."]) return nil;
    for(NSString *part in [p[1] componentsSeparatedByString:@"."]) if(!part.length || [part hasPrefix:@"-"] || [part hasSuffix:@"-"]) return nil;
    // Native Mail's case-insensitive equality; never strip dots or +tags.
    return s.lowercaseString;
}
NSString *MR5Identity(id x) {
    if([x isKindOfClass:NSData.class]) return [x length] ? [@"d:" stringByAppendingString:[x base64EncodedStringWithOptions:0]] : nil;
    if([x isKindOfClass:NSString.class]) return [x length] ? [@"s:" stringByAppendingString:x] : nil;
    if([x isKindOfClass:NSNumber.class]) return [@"n:" stringByAppendingString:[x stringValue]];
    if([x isKindOfClass:NSArray.class] || [x isKindOfClass:NSDictionary.class]) {
        NSMutableString *out=[NSMutableString stringWithString:[x isKindOfClass:NSArray.class]?@"a:":@"m:"];
        NSArray *keys=[x isKindOfClass:NSArray.class]?x:[[x allKeys] sortedArrayUsingSelector:@selector(compare:)];
        for(id key in keys) {
            NSString *a=MR5Identity(key), *b=[x isKindOfClass:NSArray.class]?@"":MR5Identity(x[key]);
            if(!a || !b) return nil;
            [out appendFormat:@"%lu:%@%lu:%@",(unsigned long)a.length,a,(unsigned long)b.length,b];
        }
        return keys.count?out:nil;
    }
    return nil;
}
NSPredicate *MR5And(NSPredicate *a, NSPredicate *b) {
    if(!a) return b;
    return b?[NSCompoundPredicate andPredicateWithSubpredicates:@[a,b]]:a;
}
NSPredicate *MR5Transform(NSPredicate *base, NSPredicate *(^original)(NSPredicate *), NSPredicate *local) {
    NSPredicate *native=original?original(base):base;
    if(!local) return native;
    // Preserve original native transforms AND the original mailbox scope.
    return MR5And(MR5And(native,base),local);
}
id MR5InvokeFactory(MR5ListFactory factory,id cls,SEL selector,id boxes,id repository,BOOL oldest,BOOL display,id sort,MR5PredicateTransform transform,id ignore,NSPredicate *local) {
    if(!local) return factory(cls,selector,boxes,repository,oldest,display,sort,transform,ignore);
    NSUInteger traceSession=MRDSession();
    // A captured id only retains a stack block under MRC; use a typed copied block.
    MR5PredicateTransform original=[transform copy];
    MR5PredicateTransform wrapped=[^NSPredicate *(NSPredicate *base) {
        MRDAt(traceSession,@"factory.transform",@"success",@"entered",nil,@{@"hasLocal":@(local!=nil)});
        NSPredicate *query=MR5Transform(base,original,local);
        MRDAt(traceSession,@"query.generated",query?@"success":@"failed",query?@"ok":@"model_contract",nil,@{@"resultPresent":@(query!=nil)});
        return query;
    } copy];
    @try {return factory(cls,selector,boxes,repository,oldest,display,sort,wrapped,ignore);}
    @finally {
#if !__has_feature(objc_arc)
        [wrapped release];[original release];
#endif
    }
}
BOOL MR5Context(id owner,id expectedOwner,NSArray *boxes,NSArray *expectedBoxes) {
    return owner && owner==expectedOwner && boxes.count && [boxes isEqual:expectedBoxes];
}
NSArray *MR5RulesForBox(NSArray *rules,NSString *account,NSString *mailbox) {
    if(!account.length || !mailbox.length) return @[];
    NSMutableArray *result=[NSMutableArray array];
    for(id rule in rules) {
        if(![rule isKindOfClass:NSDictionary.class] || ![rule[@"enabled"] boolValue] || ![rule[@"account"] isEqual:account] || !MR5Address(rule[@"sender"])) continue;
        if([rule[@"scope"] isEqual:@"account"] || ([rule[@"scope"] isEqual:@"mailbox"] && [rule[@"mailbox"] isEqual:mailbox])) [result addObject:rule];
    }
    return result;
}
BOOL MR5SenderContract(NSPredicate *p,NSString *address,id (^makeAddress)(NSString *),id (^makeMessage)(NSArray *)) {
    if(![p isKindOfClass:NSComparisonPredicate.class]) return NO;
    NSComparisonPredicate *c=(id)p;
    if(c.comparisonPredicateModifier!=NSAnyPredicateModifier || c.predicateOperatorType!=NSEqualToPredicateOperatorType || c.options!=NSCaseInsensitivePredicateOption || c.leftExpression.expressionType!=NSKeyPathExpressionType || c.rightExpression.expressionType!=NSConstantValueExpressionType) return NO;
    NSArray *path=[c.leftExpression.keyPath componentsSeparatedByString:@"."];
    // The actual factory path may be a derived getter, not an ObjC property.
    // Only identifier-only paths are evaluated, exclusively on fresh synthetic models.
    if(!path.count || path.count>4) return NO;
    NSCharacterSet *safe=[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"];
    for(NSString *key in path) if(!key.length || [key rangeOfCharacterFromSet:safe.invertedSet].location!=NSNotFound) return NO;
    NSString *s=MR5Address(address); if(!s) return NO;
    NSArray *parts=[s componentsSeparatedByString:@"@"];
    NSArray *samples=@[s,s.uppercaseString,[@"x" stringByAppendingString:s],[NSString stringWithFormat:@"%@+other@%@",parts[0],parts[1]],[NSString stringWithFormat:@"%@.x@%@",parts[0],parts[1]],[s stringByAppendingString:@".invalid"],@"other@fixture.invalid"];
    @try {
        for(NSUInteger i=0;i<samples.count;i++) {
            id a=makeAddress(samples[i]); if(!a) return NO;
            id message=makeMessage(@[a]); if(!message || [p evaluateWithObject:message]!=(i<2)) return NO;
        }
        id exact=makeAddress(s), other=makeAddress(@"other@fixture.invalid");
        if(!exact || !other || ![p evaluateWithObject:makeMessage(@[other,exact])] || [p evaluateWithObject:makeMessage(@[])] || [p evaluateWithObject:makeMessage(@[other])]) return NO;
        for(NSString *local in @[[parts[0] componentsSeparatedByString:@"+"].firstObject,[parts[0] stringByReplacingOccurrencesOfString:@"." withString:@""]]) {
            if([local isEqual:parts[0]]) continue;
            id a=makeAddress([NSString stringWithFormat:@"%@@%@",local,parts[1]]);
            if(!a || [p evaluateWithObject:makeMessage(@[a])]) return NO;
        }
    } @catch(__unused NSException *e) { return NO; }
    return YES;
}
BOOL MR5Batch(NSArray *items,NSArray *expectedIDs,NSString *account,NSSet *sourceBoxes,NSPredicate *sender,id (^read)(id,NSString *)) {
    if(![items isKindOfClass:NSArray.class] || !items.count || items.count!=expectedIDs.count || !account.length || !sourceBoxes.count || !sender) return NO;
    NSSet *expected=[NSSet setWithArray:expectedIDs];
    if(expected.count!=items.count) return NO;
    NSMutableSet *seen=[NSMutableSet set];
    @try {
        for(id item in items) {
            if(![read(item,@"isMessage") boolValue] || ![sender evaluateWithObject:item]) return NO;
            id itemID=read(item,@"itemID");
            if(!itemID || ![expected containsObject:itemID] || [seen containsObject:itemID]) return NO;
            [seen addObject:itemID];
            NSArray *boxes=read(item,@"boxes"); BOOL hasSource=NO;
            if(![boxes isKindOfClass:NSArray.class] || !boxes.count) return NO;
            for(NSDictionary *box in boxes) {
                if(![box[@"account"] isEqual:account] || ![box[@"mailbox"] length]) return NO;
                if([sourceBoxes containsObject:box[@"mailbox"]]) hasSource=YES;
            }
            if(!hasSource) return NO;
        }
    } @catch(__unused NSException *e) { return NO; }
    return YES;
}
void MR5Perform(BOOL allowed,id interaction,void (^native)(void (^)(id,BOOL)),void (^report)(NSString *),void (^completion)(id,BOOL)) {
    if(!allowed) {report(@"blocked");if(completion) completion(interaction,NO);return;}
    report(@"handedOff");
    NSObject *lock=[NSObject new];
#if !__has_feature(objc_arc)
    [lock autorelease];
#endif
    __block BOOL finished=NO;
    native(^(id result,BOOL performed){
        @synchronized(lock) {if(finished) return;finished=YES;}
        report(performed?@"pendingSync":@"notPerformed");
        if(completion) completion(result,performed);
    });
}
