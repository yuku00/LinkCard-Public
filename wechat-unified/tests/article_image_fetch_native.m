// Real Foundation URLSession, ALL URLs intercepted by this synthetic NSURLProtocol.
#import <Foundation/Foundation.h>
#import "../Sources/WUArticleImageFetch.m"
static int checks, requests;
#define CHECK(x) do { checks++; if(!(x)) { fprintf(stderr,"FAILED line %d: %s\n",__LINE__,#x); abort(); } } while(0)
static NSMutableArray<NSURLRequest *> *seen;
static NSData *Payload(void) { return [@"synthetic image bytes, decoder is tested separately" dataUsingEncoding:NSUTF8StringEncoding]; }
@interface ArticleChallengeSender : NSObject <NSURLAuthenticationChallengeSender> @end
@implementation ArticleChallengeSender
- (void)useCredential:(NSURLCredential *)credential forAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {}
- (void)continueWithoutCredentialForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {}
- (void)cancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {}
- (void)performDefaultHandlingForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {}
- (void)rejectProtectionSpaceAndContinueWithChallenge:(NSURLAuthenticationChallenge *)challenge {}
@end
@interface ArticleProtocol : NSURLProtocol @end
@implementation ArticleProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return YES; } // Catch every URL; NEVER fall through to actual network.
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    @synchronized(seen) { requests++; [seen addObject:self.request]; }
    NSString *path=self.request.URL.path;
    if([path isEqual:@"/wait"]) return;
    if([path isEqual:@"/redirect"] || [path isEqual:@"/evil"]) {
        NSURL *target=[NSURL URLWithString:[path isEqual:@"/evil"]?@"https://example.invalid/private":@"https://mmbiz.qlogo.cn/ok"];
        NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:target];
        request.allHTTPHeaderFields=@{@"Cookie":@"synthetic=must-not-forward",@"Authorization":@"synthetic",@"Referer":@"synthetic"};
        NSHTTPURLResponse *response=[[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:302 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Location":target.absoluteString}];
        [self.client URLProtocol:self wasRedirectedToRequest:request redirectResponse:response]; return;
    }
    NSString *mime=[path isEqual:@"/gif"]?@"image/gif":@"image/png";
    NSMutableDictionary *headers=[@{@"Content-Type":mime,@"Set-Cookie":@"synthetic=ignored; Secure"} mutableCopy];
    if([path isEqual:@"/announced"]) headers[@"Content-Length"]=@"20971521";
    if([path isEqual:@"/encoded"]) headers[@"Content-Encoding"]=@"gzip";
    NSHTTPURLResponse *response=[[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:[path isEqual:@"/status"]?403:200 HTTPVersion:@"HTTP/1.1" headerFields:headers];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    NSData *bytes=[path isEqual:@"/overflow"]?[NSMutableData dataWithLength:20*1024*1024+1]:Payload();
    [self.client URLProtocol:self didLoadData:bytes];
    [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end
@interface SyntheticFetch : WUArticleImageFetch @end
@implementation SyntheticFetch
+ (NSURLSessionConfiguration *)configuration {
    NSURLSessionConfiguration *c=[super configuration]; c.protocolClasses=@[ArticleProtocol.class]; return c;
}
@end
static NSURL *Article(void) { return [NSURL URLWithString:@"https://mp.weixin.qq.com/s/synthetic#rd"]; }
static NSURL *Image(NSString *path) { return [NSURL URLWithString:[@"https://mmbiz.qpic.cn" stringByAppendingString:path]]; }
static void Drain(void) { [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]]; }
static void Wait(BOOL (^done)(void)) { NSDate *end=[NSDate dateWithTimeIntervalSinceNow:5]; while(!done() && end.timeIntervalSinceNow>0) Drain(); CHECK(done()); }
static NSData *Run(NSString *path) {
    __block BOOL done=NO; __block NSData *out=nil;
    SyntheticFetch *fetch=[SyntheticFetch new];
    CHECK([fetch startURL:Image(path) article:Article() confirmed:YES current:^BOOL { return YES; } completion:^(NSData *bytes){ out=bytes; done=YES; }]);
    Wait(^BOOL { return done; }); CHECK(fetch.done && fetch.bytes==nil && fetch.completion==nil && fetch.current==nil && fetch.session==nil); return out;
}
int main(void) { @autoreleasepool {
    seen=[NSMutableArray array];
    CHECK(WUArticleURL(Article())); CHECK(!WUArticleURL([NSURL URLWithString:@"https://mp.weixin.qq.com/other"]));
    for(NSString *url in @[@"http://mmbiz.qpic.cn/a",@"https://mmbiz.qpic.cn.evil.invalid/a",@"https://user:secret@mmbiz.qpic.cn/a",@"https://mmbiz.qpic.cn:444/a",@"https://mmbiz.qpic.cn./a",@"https://127.0.0.1/a",@"https://mmbiz.qpic.cn/a#part",@"file:///tmp/a",@"https://example.invalid/a"])
        CHECK(!WUArticleImageURL([NSURL URLWithString:url],Article()));
    CHECK(WUArticleImageURL([NSURL URLWithString:@"https://mp.weixin.qq.com/synthetic.png"],Article()));
    NSURLSessionConfiguration *configuration=[SyntheticFetch configuration];
    CHECK(configuration.HTTPCookieStorage==nil && !configuration.HTTPShouldSetCookies && configuration.URLCredentialStorage==nil && configuration.URLCache==nil);
    CHECK(configuration.timeoutIntervalForRequest==8 && configuration.timeoutIntervalForResource==15 && configuration.HTTPAdditionalHeaders.count==0);
    SyntheticFetch *gate=[SyntheticFetch new];
    CHECK(![gate startURL:Image(@"/ok") article:Article() confirmed:NO current:^BOOL{return YES;} completion:^(NSData *b){abort();}]);
    CHECK(![gate startURL:Image(@"/ok") article:Article() confirmed:YES current:^BOOL{return NO;} completion:^(NSData *b){abort();}]);
    CHECK(requests==0);
    SyntheticFetch *reentrant=[SyntheticFetch new];
    CHECK(![reentrant startURL:Image(@"/ok") article:Article() confirmed:YES current:^BOOL{[reentrant cancel];return YES;} completion:^(NSData *b){abort();}]);
    CHECK(reentrant.done && reentrant.session==nil && requests==0);
    CHECK([Run(@"/ok") isEqual:Payload()]);
    CHECK(Run(@"/gif")==nil); CHECK(Run(@"/status")==nil); CHECK(Run(@"/announced")==nil); CHECK(Run(@"/overflow")==nil); CHECK(Run(@"/encoded")==nil);
    CHECK([Run(@"/redirect") isEqual:Payload()]); CHECK(Run(@"/evil")==nil);
    for(NSURLRequest *request in seen) {
        CHECK([request.HTTPMethod isEqual:@"GET"] && request.HTTPBody==nil && !request.HTTPShouldHandleCookies);
        CHECK(![request valueForHTTPHeaderField:@"Cookie"] && ![request valueForHTTPHeaderField:@"Authorization"] && ![request valueForHTTPHeaderField:@"Referer"]);
        CHECK(WUArticleImageURL(request.URL,Article()));
    }
    __block int completions=0;
    SyntheticFetch *pending=[SyntheticFetch new];
    CHECK([pending startURL:Image(@"/wait") article:Article() confirmed:YES current:^BOOL{return YES;} completion:^(NSData *b){completions++;}]);
    NSURLSession *old=pending.session; NSURLSessionDataTask *task=pending.task;
    [pending cancel];
    [pending URLSession:old dataTask:task didReceiveData:Payload()];
    [pending URLSession:old task:task didCompleteWithError:nil]; Drain();
    CHECK(completions==0 && pending.done && pending.bytes==nil);
    CHECK(![pending startURL:Image(@"/ok") article:Article() confirmed:YES current:^BOOL{return YES;} completion:^(NSData *b){abort();}]);
    __block BOOL current=YES;
    pending=[SyntheticFetch new];
    CHECK([pending startURL:Image(@"/wait") article:Article() confirmed:YES current:^BOOL{return current;} completion:^(NSData *b){CHECK(b==nil);completions++;}]);
    current=NO; [pending.watch fire]; CHECK(completions==1 && pending.done);
    pending=[SyntheticFetch new];
    CHECK([pending startURL:Image(@"/wait") article:Article() confirmed:YES current:^BOOL{return YES;} completion:^(NSData *b){CHECK(b==nil);completions++;}]);
    pending.deadline=NSProcessInfo.processInfo.systemUptime-1; [pending.watch fire]; CHECK(pending.done && completions==2);
    // Exercise redirect admission deterministically as well as the URLProtocol redirect above.
    pending=[SyntheticFetch new];
    CHECK([pending startURL:Image(@"/wait") article:Article() confirmed:YES current:^BOOL{return YES;} completion:^(NSData *b){CHECK(b==nil);}]);
    NSHTTPURLResponse *redirect=[[NSHTTPURLResponse alloc] initWithURL:Image(@"/wait") statusCode:302 HTTPVersion:@"HTTP/1.1" headerFields:@{}];
    NSMutableURLRequest *dirty=[NSMutableURLRequest requestWithURL:Image(@"/ok")]; dirty.allHTTPHeaderFields=@{@"Cookie":@"synthetic",@"Authorization":@"synthetic"};
    for(int i=0;i<3;i++) {
        __block NSURLRequest *forward=nil;
        [pending URLSession:pending.session task:pending.task willPerformHTTPRedirection:redirect newRequest:dirty completionHandler:^(NSURLRequest *r){forward=r;}];
        if(i<2) CHECK(forward && ![forward valueForHTTPHeaderField:@"Cookie"] && ![forward valueForHTTPHeaderField:@"Authorization"]);
        else CHECK(forward==nil && pending.done);
    }
    pending=[SyntheticFetch new];
    CHECK([pending startURL:Image(@"/wait") article:Article() confirmed:YES current:^BOOL{return YES;} completion:^(NSData *b){CHECK(b==nil);}]);
    NSURLProtectionSpace *space=[[NSURLProtectionSpace alloc] initWithHost:@"mmbiz.qpic.cn" port:443 protocol:@"https" realm:@"synthetic" authenticationMethod:NSURLAuthenticationMethodHTTPBasic];
    NSURLAuthenticationChallenge *challenge=[[NSURLAuthenticationChallenge alloc] initWithProtectionSpace:space proposedCredential:nil previousFailureCount:0 failureResponse:nil error:nil sender:[ArticleChallengeSender new]];
    __block BOOL cancelled=NO;
    [pending URLSession:pending.session didReceiveChallenge:challenge completionHandler:^(NSURLSessionAuthChallengeDisposition d,NSURLCredential *credential){cancelled=d==NSURLSessionAuthChallengeCancelAuthenticationChallenge && credential==nil;}];
    CHECK(cancelled && pending.done);
    printf("article-fetch: %d synthetic assertions; NSURLProtocol only; no external requests\n",checks);
} return 0; }
