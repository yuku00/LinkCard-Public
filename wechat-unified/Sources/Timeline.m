#import "WU.h"
static IMP filter;
static BOOL Filter(id o,SEL s,id item) {
    BOOL original=((BOOL(*)(id,SEL,id))filter)(o,s,item);
    if(original || !WUEnabled(@"keywords") || !item) return original;
    SEL content=NSSelectorFromString(@"contentDesc");
    if(!WUMatches(class_getInstanceMethod([item class],content),"@",@[])) return original;
    id text;
    @try { text=((id(*)(id,SEL))objc_msgSend)(item,content); }
    @catch(NSException *exception) { (void)exception; return original; }
    if(![text isKindOfClass:NSString.class] || [text length]>65536) return original;
    NSString *words=WUValue(@"words");
    for(NSString *line in [words componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *word=[line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if(word.length && word.length<=128 && [text rangeOfString:word options:NSCaseInsensitiveSearch|NSDiacriticInsensitiveSearch].location!=NSNotFound) return YES;
    }
    return original;
}
void WUInstallTimeline(void) { WUHook(@"WCFacade",@"filterTimelineItem:",NO,@encode(BOOL),@[@"@"],(IMP)Filter,&filter); }
