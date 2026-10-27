#import <Foundation/Foundation.h>
// Call Start in the dylib constructor, before dispatching UI work. No restart-to-arm.
FOUNDATION_EXPORT void FPLifecycleStart(void);
FOUNDATION_EXPORT void FPLifecycleStop(void);
FOUNDATION_EXPORT NSString *FPLifecycleReport(void);
