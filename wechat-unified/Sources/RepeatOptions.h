#import <Foundation/Foundation.h>
static inline NSDictionary *WURepeatDefaults(void) {
    return @{@"imageButton":@YES,@"themeIcon":@YES,@"longDownload":@YES,@"onlyEmoticon":@YES,@"normalRepeat":@YES,@"menuRepeat":@NO,@"fileOnly":@NO,@"userIcon":@""};
}
static inline BOOL WUValidRepeatOptions(id options) {
    if(![options isKindOfClass:NSDictionary.class] || [options count]!=8) return NO;
    NSDictionary *defaults=WURepeatDefaults();
    for(NSString *key in defaults) {
        id value=options[key];
        if([key isEqual:@"userIcon"]) { if(![value isKindOfClass:NSString.class] || ([value length] && ![[NSUUID alloc] initWithUUIDString:value])) return NO; }
        else if(![value isKindOfClass:NSNumber.class] || ![@[@0,@1] containsObject:value]) return NO;
    }
    // No invented host file sender/menu hook: unsupported modes cannot become enabled via edited JSON.
    return [options[@"onlyEmoticon"] boolValue] && ![options[@"menuRepeat"] boolValue] && ![options[@"fileOnly"] boolValue];
}
