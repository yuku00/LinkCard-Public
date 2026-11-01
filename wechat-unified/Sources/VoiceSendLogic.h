#import <Foundation/Foundation.h>
// Only snapshots of explicitly selected, existing type-34 / format-4 messages.
// No codec->host format inference for imported files.
NSData *WUVoiceSelectedData(id wrap);
uint32_t WUVoiceMeasuredMS(NSData *data);
BOOL WUVoiceExactSignature(id object, NSString *selector, const char *result, NSArray<NSString *> *arguments);
@interface WUVoiceForwardOperation : NSObject
@property(nonatomic,readonly,copy) NSString *status;
@property(nonatomic,readonly) uint32_t milliseconds;
// Construct on a worker queue: complete offline decode measures duration.
- (instancetype)initWithData:(NSData *)data account:(NSString *)account target:(NSString *)target;
- (NSString *)submitWithManager:(id)manager audioSender:(id)audio messageClass:(Class)messageClass current:(BOOL (^)(void))current;
@end
