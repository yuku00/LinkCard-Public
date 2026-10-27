#import "RuleCore.h"
#import <objc/message.h>
#import <objc/runtime.h>
static id ConvertibleGet(id object, NSString *name) {
    SEL sel=NSSelectorFromString(name);
    NSMethodSignature *sig=[object methodSignatureForSelector:sel];
    if (!sig || sig.numberOfArguments!=2 || strcmp(sig.methodReturnType,@encode(id))!=0) return nil;
    return ((id(*)(id,SEL))objc_msgSend)(object,sel);
}
NSString *MRReadAddress(id convertible) {
    @try {
        id address=ConvertibleGet(convertible,@"emailAddressValue");
        return MRNormalize(ConvertibleGet(address ?: convertible,@"stringValue"));
    } @catch (__unused NSException *e) { return nil; }
}
NSString *MRIdentityKey(id representation, NSMutableDictionary *identities) {
    if (!representation || ![NSPropertyListSerialization propertyList:representation isValidForFormat:NSPropertyListBinaryFormat_v1_0]) return nil;
    if ([representation respondsToSelector:@selector(length)] && ![representation length]) return nil;
    if ([representation respondsToSelector:@selector(count)] && ![representation count]) return nil;
    NSString *match=nil;
    for (id key in identities) if ([identities[key] isEqual:representation]) {
        if (![key isKindOfClass:NSString.class] || ![key hasPrefix:@"object:"] || match) return nil; // Ambiguous/corrupt mappings never choose a first account.
        match=key;
    }
    if (match) return match;
    NSString *key = [@"object:" stringByAppendingString:NSUUID.UUID.UUIDString];
    identities[key] = representation;
    return key;
}
NSString *MRNormalize(NSString *input) {
    if (![input isKindOfClass:NSString.class]) return nil;
    NSString *s = [input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSArray *parts = [s componentsSeparatedByString:@"@"];
    if (parts.count != 2 || ![parts[0] length] || ![parts[1] length]) return nil;
    // shortcut: ASCII addr-spec only; display names/quoted local parts/IDNs are not accepted in v0.2.
    NSCharacterSet *local = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.!#$%&'*+-/=?^_`{|}~"];
    NSCharacterSet *domain = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-"];
    if ([parts[0] rangeOfCharacterFromSet:local.invertedSet].location != NSNotFound || [parts[1] rangeOfCharacterFromSet:domain.invertedSet].location != NSNotFound) return nil;
    if ([parts[0] hasPrefix:@"."] || [parts[0] hasSuffix:@"."] || [parts[0] containsString:@".."]) return nil;
    for (NSString *label in [parts[1] componentsSeparatedByString:@"."]) if (!label.length || [label hasPrefix:@"-"] || [label hasSuffix:@"-"]) return nil;
    return [NSString stringWithFormat:@"%@@%@", parts[0], [parts[1] lowercaseString]];
}
BOOL MRScope(BOOL inbox, BOOL smart, NSUInteger count, BOOL threaded, BOOL search) {
    return inbox && !smart && count == 1 && !threaded && !search;
}
NSPredicate *MRCombine(NSPredicate *original, NSPredicate *exclude) {
    if (!exclude) return original;
    return original ? [NSCompoundPredicate andPredicateWithSubpredicates:@[original, exclude]] : exclude;
}
NSPredicate *MRCombineSection(NSPredicate *original, NSPredicate *exclude, NSString *section) {
    return MRCombine(original, [section isEqual:@"MessageListSectionRecent"] ? exclude : nil);
}
BOOL MRContextMatches(id owner, id sourceOwner, id source, id currentSource, NSString *account, NSString *currentAccount, id mailbox, id currentMailbox) {
    return owner && owner == sourceOwner && source && source == currentSource && account.length && [account isEqual:currentAccount] && mailbox && mailbox == currentMailbox;
}
static BOOL SafeShape(NSPredicate *p, BOOL nativeModel) {
    if (![p isKindOfClass:NSComparisonPredicate.class]) return NO;
    NSComparisonPredicate *c = (id)p;
    if (c.predicateOperatorType != NSEqualToPredicateOperatorType) return NO;
    if (c.options != 0 && c.options != NSCaseInsensitivePredicateOption) return NO;
    if (c.leftExpression.expressionType != NSKeyPathExpressionType || c.rightExpression.expressionType != NSConstantValueExpressionType) return NO;
    NSString *key = c.leftExpression.keyPath;
    if (c.comparisonPredicateModifier == NSDirectPredicateModifier)
        return c.options == 0 && [@[@"senderAddress", @"senderAddress.stringValue", @"senderAddress.emailAddressValue"] containsObject:key];
    // Only the EMMessage senderList collection and documented address conversions.
    // No arbitrary KVC traversal, collection operators, display names or other fields.
    // The factory's actual path must also pass native-model fixtures before use.
    if (nativeModel && c.comparisonPredicateModifier == NSAnyPredicateModifier) return YES; // Declared getters are checked on synthetic native models below.
    return c.comparisonPredicateModifier == NSAnyPredicateModifier &&
        [@[@"senderList", @"senderList.emailAddressValue", @"senderList.stringValue",
           @"senderList.simpleAddress", @"senderList.emailAddressValue.stringValue",
           @"senderList.emailAddressValue.simpleAddress"] containsObject:key];
}
// Walk only declared object properties, never arbitrary KVC or collection operators.
// This is used exclusively on freshly allocated synthetic native-model fixtures.
static BOOL DeclaredPath(id value, NSArray *parts, NSUInteger index) {
    if (index == parts.count) return [value isKindOfClass:NSString.class] || [value isKindOfClass:NSArray.class] || value != nil;
    if ([value isKindOfClass:NSArray.class]) {
        if (![value count]) return NO;
        for (id item in value) if (!DeclaredPath(item,parts,index)) return NO;
        return YES;
    }
    NSString *key=parts[index];
    NSCharacterSet *letters=[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"];
    if (!key.length || [key rangeOfCharacterFromSet:letters.invertedSet].location!=NSNotFound) return NO;
    objc_property_t prop=class_getProperty([value class],key.UTF8String);
    if (!prop || strncmp(property_getAttributes(prop),"T@",2)!=0) return NO;
    NSMethodSignature *sig=[value methodSignatureForSelector:NSSelectorFromString(key)];
    if (!sig || sig.numberOfArguments!=2 || strcmp(sig.methodReturnType,@encode(id))) return NO;
    return DeclaredPath(ConvertibleGet(value,key),parts,index+1);
}
static BOOL Validate(NSPredicate *p, NSString *address, id (^object)(NSString *), id (^message)(NSArray *), BOOL nativeModel) {
    // Inspect AST before evaluateWithObject:; no FUNCTION, SUBQUERY or unchecked key paths.
    if (!SafeShape(p,nativeModel)) return NO;
    if (nativeModel) {
        @try {
            NSArray *path=[((NSComparisonPredicate *)p).leftExpression.keyPath componentsSeparatedByString:@"."];
            id sender=object(address);
            if (!sender || path.count>4 || !DeclaredPath(message(@[sender]),path,0)) return NO;
        } @catch (__unused NSException *e) { return NO; }
    }
    NSArray *parts = [address componentsSeparatedByString:@"@"];
    if (parts.count != 2) return NO;
    NSArray *samples = @[address,
        [NSString stringWithFormat:@"x%@@%@",parts[0],parts[1]],
        [NSString stringWithFormat:@"%@+tag@%@",parts[0],parts[1]],
        [NSString stringWithFormat:@"%@.x@%@",parts[0],parts[1]],
        [NSString stringWithFormat:@"%@@x%@",parts[0],parts[1]],
        [NSString stringWithFormat:@"%@@%@.invalid",parts[0],parts[1]],
        @"other@fixture.invalid"];
    @try {
        for (NSUInteger i=0; i<samples.count; i++) {
            id a = object(samples[i]);
            if (!a) return NO;
            id fixture = message(@[a]);
            if (!fixture || [p evaluateWithObject:fixture] != (i == 0)) return NO;
        }
        id mixed=message(@[object(@"other@fixture.invalid"),object(address)]);
        if (((NSComparisonPredicate *)p).comparisonPredicateModifier == NSAnyPredicateModifier && (!mixed || ![p evaluateWithObject:mixed])) return NO;
        id nonmatching=message(@[object(@"other@fixture.invalid"),object(@"prefix@fixture.invalid")]);
        if (!nonmatching || [p evaluateWithObject:nonmatching]) return NO;
        id empty=message(@[]);
        if (!empty || [p evaluateWithObject:empty]) return NO;
        NSString *upperDomain=[NSString stringWithFormat:@"%@@%@",parts[0],[parts[1] uppercaseString]];
        id upper=object(upperDomain);
        id upperMessage=upper ? message(@[upper]) : nil;
        if (!upperMessage || ![p evaluateWithObject:upperMessage]) return NO;
        if (((NSComparisonPredicate *)p).options == NSCaseInsensitivePredicateOption) {
            id upperAll=object([address uppercaseString]);
            id upperAllMessage=upperAll ? message(@[upperAll]) : nil;
            if (!upperAllMessage || ![p evaluateWithObject:upperAllMessage]) return NO;
        }
        for (NSString *local in @[[parts[0] componentsSeparatedByString:@"+"].firstObject, [parts[0] stringByReplacingOccurrencesOfString:@"." withString:@""]]) {
            if ([local isEqual:parts[0]]) continue;
            id altered=object([NSString stringWithFormat:@"%@@%@",local,parts[1]]);
            id alteredMessage=altered ? message(@[altered]) : nil;
            if (!alteredMessage || [p evaluateWithObject:alteredMessage]) return NO;
        }
    } @catch (__unused NSException *e) { return NO; }
    return YES;
}
BOOL MRValidateNativeSenderPredicate(NSPredicate *p, NSString *address, id (^object)(NSString *), id (^message)(NSArray *)) {
    return Validate(p,address,object,message,YES);
}
BOOL MRValidateSenderPredicateWithModel(NSPredicate *p, NSString *address, id (^object)(NSString *), id (^message)(NSArray *)) {
    return Validate(p,address,object,message,NO);
}
BOOL MRValidateSenderPredicate(NSPredicate *p, NSString *address, id (^object)(NSString *)) {
    return MRValidateSenderPredicateWithModel(p,address,object,^id(NSArray *senders){
        return senders.count ? @{@"senderList":senders,@"senderAddress":senders.firstObject} : @{@"senderList":@[]};
    });
}
