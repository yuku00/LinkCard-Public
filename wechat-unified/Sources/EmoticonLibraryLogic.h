#import <Foundation/Foundation.h>
// Entire library is an account-bound, bounded binary plist; data is original encoded bytes.
@interface WUEmoticonLibraryStore : NSObject
- (instancetype)initWithRoot:(NSURL *)root account:(NSString *)account;
- (NSDictionary *)load:(NSError **)error;
- (BOOL)importData:(NSData *)data name:(NSString *)name group:(NSString *)group current:(BOOL (^)(void))current error:(NSError **)error;
// Called only after explicit confirmation; current also rechecks the selected message.
- (BOOL)importSelectedPath:(NSString *)path md5:(NSString *)md5 GIFOnly:(BOOL)GIFOnly name:(NSString *)name group:(NSString *)group current:(BOOL (^)(void))current error:(NSError **)error;
- (BOOL)importFile:(NSURL *)url name:(NSString *)name group:(NSString *)group current:(BOOL (^)(void))current error:(NSError **)error;
- (BOOL)createGroup:(NSString *)name current:(BOOL (^)(void))current error:(NSError **)error;
- (BOOL)rename:(NSString *)identifier group:(BOOL)group name:(NSString *)name current:(BOOL (^)(void))current error:(NSError **)error;
- (BOOL)move:(NSString *)identifier group:(BOOL)group to:(NSUInteger)index current:(BOOL (^)(void))current error:(NSError **)error;
- (BOOL)assign:(NSString *)identifier group:(NSString *)group current:(BOOL (^)(void))current error:(NSError **)error;
- (BOOL)remove:(NSString *)identifier group:(BOOL)group current:(BOOL (^)(void))current error:(NSError **)error;
- (NSDictionary *)resource:(NSString *)identifier error:(NSError **)error;
@end
NSArray<NSDictionary *> *WUEmoticonLibraryRows(NSDictionary *state, NSString *group);
NSString *WUEmoticonDigest(NSData *data);
