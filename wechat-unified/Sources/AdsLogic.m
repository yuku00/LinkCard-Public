#import "AdsLogic.h"
#import <objc/runtime.h>
BOOL WUMomentsAdResult(BOOL original, BOOL enabled, id ad, id item) {
    if(!original || !enabled || !ad || !item) return original;
    Class timelineItem=NSClassFromString(@"WCDataItem");
    // Fail open for unknown models/subclasses; never infer ads from user text or URLs.
    if(!timelineItem || object_getClass(item)!=timelineItem) return original;
    return NO;
}
BOOL WUSplashAdResult(BOOL original, BOOL enabled) { return enabled ? NO : original; }
