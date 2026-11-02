#import "WUArticleImageFetch.h"
static const NSUInteger ByteLimit=20*1024*1024;
static NSURLComponents *HTTPS(NSURL *url) {
    if(![url isKindOfClass:NSURL.class] || url.absoluteString.length>8192 || !url.absoluteString.length) return nil;
    NSURLComponents *c=[NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    if(![c.scheme.lowercaseString isEqual:@"https"] || !c.host.length || c.user!=nil || c.password!=nil || (c.port && ![c.port isEqual:@443])) return nil;
    if([url.absoluteString rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound || [c.percentEncodedHost containsString:@"%"] || [c.host hasSuffix:@"."]) return nil;
    return c;
}
BOOL WUArticleURL(NSURL *url) {
    NSURLComponents *c=HTTPS(url);
    return [c.host.lowercaseString isEqual:@"mp.weixin.qq.com"] && ([c.path isEqual:@"/s"] || ([c.path hasPrefix:@"/s/"] && c.path.length>3));
}
BOOL WUArticleImageURL(NSURL *url, NSURL *article) {
    NSURLComponents *c=HTTPS(url);
    return WUArticleURL(article) && c && c.fragment==nil && [@[@"mmbiz.qpic.cn",@"mmbiz.qlogo.cn",@"mp.weixin.qq.com"] containsObject:c.host.lowercaseString];
}
@interface WUArticleImageFetch ()
@property(nonatomic,strong) NSURLSession *session;
@property(nonatomic,strong) NSURLSessionDataTask *task;
@property(nonatomic,strong) NSMutableData *bytes;
@property(nonatomic,copy) NSURL *article;
@property(nonatomic,copy) BOOL (^current)(void);
@property(nonatomic,copy) void (^completion)(NSData *);
@property(nonatomic) NSUInteger redirects;
@property(nonatomic) BOOL started, done, accepted;
@property(nonatomic) NSTimeInterval deadline;
@property(nonatomic,strong) NSTimer *watch;
@end
@implementation WUArticleImageFetch
+ (NSURLSessionConfiguration *)configuration {
    NSURLSessionConfiguration *c=NSURLSessionConfiguration.ephemeralSessionConfiguration;
    c.HTTPCookieStorage=nil; c.HTTPShouldSetCookies=NO; c.URLCredentialStorage=nil; c.URLCache=nil;
    c.HTTPAdditionalHeaders=@{}; c.requestCachePolicy=NSURLRequestReloadIgnoringLocalCacheData;
    c.timeoutIntervalForRequest=8; c.timeoutIntervalForResource=15; c.HTTPMaximumConnectionsPerHost=1;
    return c;
}
- (NSMutableURLRequest *)request:(NSURL *)url {
    NSMutableURLRequest *r=[NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:8];
    r.HTTPMethod=@"GET"; r.HTTPBody=nil; r.HTTPShouldHandleCookies=NO; r.mainDocumentURL=nil;
    r.allHTTPHeaderFields=@{@"Accept":@"image/png,image/jpeg",@"Accept-Encoding":@"identity"};
    return r;
}
- (BOOL)live {
    BOOL (^predicate)(void)=[self.current copy];
    if(self.done || NSProcessInfo.processInfo.systemUptime>=self.deadline || !predicate) return NO;
    BOOL valid=predicate(); return valid && !self.done;
}
- (void)finish:(NSData *)data notify:(BOOL)notify {
    if(self.done) return;
    BOOL allowed=notify && [self live]; self.done=YES;
    void (^completion)(NSData *)=self.completion;
    self.completion=nil; self.current=nil; self.bytes=nil; self.article=nil;
    [self.watch invalidate]; self.watch=nil; [self.task cancel]; self.task=nil;
    [self.session invalidateAndCancel]; self.session=nil;
    if(notify && completion) completion(allowed?data:nil);
}
- (void)cancel { [self finish:nil notify:NO]; }
- (BOOL)startURL:(NSURL *)url article:(NSURL *)article confirmed:(BOOL)confirmed current:(BOOL (^)(void))current completion:(void (^)(NSData *))completion {
    if(!NSThread.isMainThread || self.started || self.done || !confirmed || !current || !current() || self.done || !completion || !WUArticleImageURL(url,article)) return NO;
    self.started=YES; self.article=article; self.current=current; self.completion=completion;
    self.deadline=NSProcessInfo.processInfo.systemUptime+15; self.bytes=[NSMutableData data];
    self.session=[NSURLSession sessionWithConfiguration:[self.class configuration] delegate:self delegateQueue:NSOperationQueue.mainQueue];
    self.task=[self.session dataTaskWithRequest:[self request:url]];
    __weak WUArticleImageFetch *weak=self;
    self.watch=[NSTimer timerWithTimeInterval:0.2 repeats:YES block:^(NSTimer *timer){ WUArticleImageFetch *op=weak; if(![op live]) [op finish:nil notify:YES]; }];
    [NSRunLoop.mainRunLoop addTimer:self.watch forMode:NSRunLoopCommonModes];
    [self.task resume]; return YES;
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completionHandler {
    if(![self live] || task!=self.task || ++self.redirects>2 || !WUArticleImageURL(request.URL,self.article) || !WUArticleImageURL(response.URL,self.article) || ![@[@301,@302,@303,@307,@308] containsObject:@(response.statusCode)]) {
        completionHandler(nil); [self finish:nil notify:YES]; return;
    }
    // Never carry forwarded headers, body, cookies or credentials across redirects.
    completionHandler([self request:request.URL]);
}
- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler {
    if([challenge.protectionSpace.authenticationMethod isEqual:NSURLAuthenticationMethodServerTrust] && [self live]) completionHandler(NSURLSessionAuthChallengePerformDefaultHandling,nil);
    else { completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge,nil); [self finish:nil notify:YES]; }
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler {
    [self URLSession:session didReceiveChallenge:challenge completionHandler:completionHandler];
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    NSHTTPURLResponse *http=[response isKindOfClass:NSHTTPURLResponse.class]?(id)response:nil;
    NSString *encoding=[http valueForHTTPHeaderField:@"Content-Encoding"];
    BOOL ok=[self live] && task==self.task && http.statusCode==200 && WUArticleImageURL(http.URL,self.article) && [@[@"image/png",@"image/jpeg"] containsObject:http.MIMEType.lowercaseString] && response.expectedContentLength!=0 && response.expectedContentLength<=(long long)ByteLimit && (!encoding.length || [encoding.lowercaseString isEqual:@"identity"]);
    self.accepted=ok; completionHandler(ok?NSURLSessionResponseAllow:NSURLSessionResponseCancel);
    if(!ok) [self finish:nil notify:YES];
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    if(![self live] || task!=self.task || !self.accepted || data.length>ByteLimit-self.bytes.length) { [self finish:nil notify:YES]; return; }
    [self.bytes appendData:data];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    NSData *result=(!error && task==self.task && self.accepted && self.bytes.length)?[self.bytes copy]:nil;
    [self finish:result notify:YES];
}
@end
