#import <Foundation/Foundation.h>
// Private local records only; no imported declaration is a trusted host pairing.
BOOL WUVoicePackMatches(NSDictionary *record, NSString *version);
@interface WUVoicePackStore : NSObject
- (instancetype)initWithRoot:(NSURL *)root account:(NSString *)account;
- (NSArray *)load:(NSError **)error;
- (BOOL)saveData:(NSData *)data format:(NSNumber *)format version:(NSString *)version name:(NSString *)name current:(BOOL (^)(void))current error:(NSError **)error;
- (BOOL)rename:(NSString *)identifier name:(NSString *)name current:(BOOL (^)(void))current error:(NSError **)error;
- (BOOL)remove:(NSString *)identifier current:(BOOL (^)(void))current error:(NSError **)error;
- (NSDictionary *)acquire:(NSString *)identifier error:(NSError **)error;
- (void)releaseResource:(NSString *)identifier;
@end
