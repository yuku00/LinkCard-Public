#import <Foundation/Foundation.h>
// No UIImage conversion: validated original bytes only.
NSData *WUEmoticonRead(NSString *path);
NSString *WUEmoticonType(NSData *data);
typedef void (^WUEmoticonPermission)(void (^reply)(BOOL allowed));
typedef void (^WUEmoticonWriter)(NSData *data, NSString *uti, void (^reply)(BOOL success));
@interface WUEmoticonSave : NSObject
@property(nonatomic,readonly) BOOL started;
- (BOOL)startData:(NSData *)data current:(BOOL (^)(void))current permission:(WUEmoticonPermission)permission writer:(WUEmoticonWriter)writer completion:(void (^)(NSString *result))completion;
@end
