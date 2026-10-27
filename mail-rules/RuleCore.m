#import "RuleCore.h"
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
static BOOL SafeShape(NSPredicate *p) {
    if (![p isKindOfClass:NSComparisonPredicate.class]) return NO;
    NSComparisonPredicate *c = (id)p;
    if (c.predicateOperatorType != NSEqualToPredicateOperatorType || c.options != 0) return NO;
    if (c.leftExpression.expressionType != NSKeyPathExpressionType || c.rightExpression.expressionType != NSConstantValueExpressionType) return NO;
    NSString *key = c.leftExpression.keyPath;
    if (c.comparisonPredicateModifier == NSDirectPredicateModifier)
        return [@[@"senderAddress", @"senderAddress.stringValue", @"senderAddress.emailAddressValue"] containsObject:key];
    return c.comparisonPredicateModifier == NSAnyPredicateModifier && [key isEqual:@"senderList"];
}
BOOL MRValidateSenderPredicate(NSPredicate *p, NSString *address, id (^object)(NSString *)) {
    // Inspect AST before evaluateWithObject:; no FUNCTION, SUBQUERY or unknown key paths are executed.
    if (!SafeShape(p)) return NO;
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
            NSDictionary *fixture = @{@"senderAddress":a, @"senderList":@[a]};
            if ([p evaluateWithObject:fixture] != (i == 0)) return NO;
        }
        if ([p evaluateWithObject:@{@"senderList":@[]}]) return NO;
        NSString *upperDomain=[NSString stringWithFormat:@"%@@%@",parts[0],[parts[1] uppercaseString]];
        id upper=object(upperDomain);
        if (!upper || ![p evaluateWithObject:@{@"senderAddress":upper,@"senderList":@[upper]}]) return NO;
        for (NSString *local in @[[parts[0] componentsSeparatedByString:@"+"].firstObject, [parts[0] stringByReplacingOccurrencesOfString:@"." withString:@""]]) {
            if ([local isEqual:parts[0]]) continue;
            id altered=object([NSString stringWithFormat:@"%@@%@",local,parts[1]]);
            if (!altered || [p evaluateWithObject:@{@"senderAddress":altered,@"senderList":@[altered]}]) return NO;
        }
    } @catch (__unused NSException *e) { return NO; }
    return YES;
}
