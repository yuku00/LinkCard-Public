#import <Foundation/Foundation.h>
// Call Start in the dylib constructor, before dispatching UI work. No restart-to-arm.
FOUNDATION_EXPORT void FPLifecycleStart(void);
FOUNDATION_EXPORT void FPLifecycleStop(void);
// Main-thread, argument-free observation of selection/hierarchy callbacks only.
FOUNDATION_EXPORT void FPLifecycleSetEventObserver(void (*observer)(id, const char *));
FOUNDATION_EXPORT NSString *FPLifecycleReport(void);
