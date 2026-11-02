#import <Foundation/Foundation.h>
// Only the single URL selected by a native article gesture, after explicit consent.
BOOL WUArticleURL(NSURL *url);
BOOL WUArticleImageURL(NSURL *url, NSURL *article);
@interface WUArticleImageFetch : NSObject <NSURLSessionDataDelegate>
- (BOOL)startURL:(NSURL *)url article:(NSURL *)article confirmed:(BOOL)confirmed current:(BOOL (^)(void))current completion:(void (^)(NSData *data))completion;
- (void)cancel;
@end
