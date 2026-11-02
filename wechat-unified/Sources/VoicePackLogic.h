#import <Foundation/Foundation.h>
// Private account-local records; imported declarations never establish encoder provenance.
BOOL WUVoicePackMatches(NSDictionary *record, NSString *version);
@interface WUVoicePackStore : NSObject
- (instancetype)initWithRoot:(NSURL *)root account:(NSString *)account;
- (NSArray *)load:(NSError **)error;
// Legacy import remains unpaired; versioned import re-encodes and validates locally.
- (BOOL)importFile:(NSURL *)url name:(NSString *)name current:(BOOL (^)(void))current error:(NSError **)error;
- (BOOL)importFile:(NSURL *)url name:(NSString *)name version:(NSString *)version current:(BOOL (^)(void))current error:(NSError **)error;
- (NSData *)exportResource:(NSString *)identifier error:(NSError **)error;
- (BOOL)pair:(NSString *)identifier selectedData:(NSData *)data format:(NSNumber *)format version:(NSString *)version current:(BOOL (^)(void))current error:(NSError **)error;
- (BOOL)saveData:(NSData *)data format:(NSNumber *)format version:(NSString *)version name:(NSString *)name current:(BOOL (^)(void))current error:(NSError **)error;
- (BOOL)rename:(NSString *)identifier name:(NSString *)name current:(BOOL (^)(void))current error:(NSError **)error;
- (BOOL)remove:(NSString *)identifier current:(BOOL (^)(void))current error:(NSError **)error;
- (NSDictionary *)acquire:(NSString *)identifier error:(NSError **)error;
- (void)releaseResource:(NSString *)identifier;
@end
