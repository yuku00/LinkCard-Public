#import <Foundation/Foundation.h>
#import "VoiceDisplayPolicy.h"
@interface WUVoiceDisplay : NSObject
@property(nonatomic,copy) WUVoiceDisplayIdentity (^identity)(void);
@property(nonatomic,copy) BOOL (^enabled)(void);
@property(nonatomic,copy) BOOL (^carry)(void);
@property(nonatomic,readonly) BOOL layoutObserved, layoutConsumedDuration;
- (BOOL)applyModel:(id)model message:(id)message milliseconds:(double)ms;
- (void)clear;
- (void)layout:(void (^)(void))original;
- (NSString *)originalText:(id)model;
@end
void WUInstallVoiceDisplay(void);
void WUVoiceDisplayLayout(WUVoiceDisplay *display, void (^original)(void));
/* Metadata only, called on the existing decode queue, never the main thread. */
NSString *WUVoiceDisplaySourceVersion(NSString *path);
