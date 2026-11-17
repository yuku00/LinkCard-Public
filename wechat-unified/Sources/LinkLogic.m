#import "LinkLogic.h"
NSURL *WULinkSafeURL(NSString *text) {
    if(![text isKindOfClass:NSString.class] || !text.length || text.length>4096) return nil;
    if([text rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location!=NSNotFound) return nil;
    NSString *decoded=text.stringByRemovingPercentEncoding;
    if(!decoded || [decoded rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound) return nil;
    NSURLComponents *c=[NSURLComponents componentsWithString:text];
    if(![@[@"http",@"https"] containsObject:c.scheme.lowercaseString] || !c.host.length || c.user.length || c.password.length) return nil;
    if(c.user!=nil || c.password!=nil) return nil; // Also reject empty user-info, not just credentials.
    if(c.port && (c.port.integerValue<1 || c.port.integerValue>65535)) return nil;
    NSCharacterSet *unsafe=[NSCharacterSet characterSetWithCharactersInString:@"\u200e\u200f\u202a\u202b\u202c\u202d\u202e\u2066\u2067\u2068\u2069\\"];
    if([decoded rangeOfCharacterFromSet:unsafe].location!=NSNotFound) return nil;
    return c.URL;
}
static BOOL RiskHost(NSString *host) { return [host.lowercaseString isEqual:@"weixin110.qq.com"]; }
NSDictionary *WULinkDestination(NSURL *url) {
    NSURL *safe=WULinkSafeURL(url.absoluteString); if(!safe) return @{@"error":@"不是可用的 HTTP(S) 地址。"};
    NSURLComponents *c=[NSURLComponents componentsWithURL:safe resolvingAgainstBaseURL:NO];
    BOOL wrapper=RiskHost(c.host) || ([c.host.lowercaseString isEqual:@"mp.weixin.qq.com"] && [c.path isEqual:@"/mp/wapredirect"]);
    if(!wrapper) return @{@"url":safe,@"risk":@NO};
    BOOL known=([c.host.lowercaseString isEqual:@"weixin110.qq.com"] && [c.path isEqual:@"/cgi-bin/mmspamsupport-bin/newredirectconfirmcgi"]) || ([c.host.lowercaseString isEqual:@"mp.weixin.qq.com"] && [c.path isEqual:@"/mp/wapredirect"]);
    NSMutableArray *targets=[NSMutableArray array];
    if(known) for(NSURLQueryItem *item in c.queryItems) if([item.name isEqual:@"url"] && item.value) [targets addObject:item.value];
    // NSURLComponents decodes one query level. No repeated unescaping, HTML crawling or guessing.
    NSURL *target=targets.count==1?WULinkSafeURL(targets.firstObject):nil;
    if(!target || RiskHost(target.host) || ([target.host.lowercaseString isEqual:@"mp.weixin.qq.com"] && [target.path isEqual:@"/mp/wapredirect"]))
        return @{@"error":@"风险提示地址没有唯一、明确的原始 HTTP(S) 目标，已拒绝。不会抓取页面、猜测地址或宣称解除封禁。"};
    return @{@"url":target,@"risk":@YES,@"wrapper":safe};
}
@interface WULinkXML : NSObject <NSXMLParserDelegate>
@property(nonatomic,strong) NSMutableArray<NSString *> *stack;
@property(nonatomic,strong) NSMutableArray<NSString *> *urls;
@property(nonatomic,strong) NSMutableString *text;
@property(nonatomic) BOOL invalid;
@end
@implementation WULinkXML
- (void)parser:(NSXMLParser *)p didStartElement:(NSString *)name namespaceURI:(NSString *)ns qualifiedName:(NSString *)q attributes:(NSDictionary *)attrs {
    if(self.stack.count>=16) { self.invalid=YES; [p abortParsing]; return; }
    if(self.text) { self.invalid=YES; [p abortParsing]; return; }
    [self.stack addObject:name];
    if([[self.stack componentsJoinedByString:@"/"] isEqual:@"msg/appmsg/url"]) self.text=[NSMutableString string];
}
- (void)parser:(NSXMLParser *)p foundCharacters:(NSString *)s { if(self.text) [self.text appendString:s]; }
- (void)parser:(NSXMLParser *)p foundCDATA:(NSData *)data { if(self.text) { NSString *s=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]; if(!s) { self.invalid=YES; [p abortParsing]; } else [self.text appendString:s]; } }
- (void)parser:(NSXMLParser *)p didEndElement:(NSString *)name namespaceURI:(NSString *)ns qualifiedName:(NSString *)q {
    if([[self.stack componentsJoinedByString:@"/"] isEqual:@"msg/appmsg/url"] && self.text) {
        [self.urls addObject:[self.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]]; self.text=nil;
    }
    [self.stack removeLastObject];
}
- (NSData *)parser:(NSXMLParser *)p resolveExternalEntityName:(NSString *)name systemID:(NSString *)systemID { self.invalid=YES; [p abortParsing]; return nil; }
@end
NSArray<NSDictionary *> *WULinkCandidates(NSArray<NSDictionary *> *messages) {
    if(![messages isKindOfClass:NSArray.class] || !messages.count || messages.count>20) return @[];
    NSMutableArray *out=[NSMutableArray array]; NSMutableSet *seen=[NSMutableSet set]; NSUInteger total=0,index=0;
    NSDataDetector *detector=[NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeLink error:NULL];
    for(NSDictionary *m in messages) {
        index++; if(![m isKindOfClass:NSDictionary.class] || ![m[@"type"] isKindOfClass:NSNumber.class]) return @[];
        NSString *text=m[@"content"]; if(![text isKindOfClass:NSString.class] || text.length>8192 || (total+=text.length)>65536) return @[];
        NSMutableArray<NSURL *> *urls=[NSMutableArray array]; NSString *source=nil;
        if([m[@"type"] unsignedIntegerValue]==1) {
            source=[NSString stringWithFormat:@"消息 %lu · 文本",(unsigned long)index];
            for(NSTextCheckingResult *r in [detector matchesInString:text options:0 range:NSMakeRange(0,text.length)]) { NSURL *u=WULinkSafeURL(r.URL.absoluteString); if(u) [urls addObject:u]; }
        } else if([m[@"type"] unsignedIntegerValue]==49) {
            // Only the card's exact URL element. Descriptions, thumbnails, attachment URLs and XML attributes are excluded.
            source=[NSString stringWithFormat:@"消息 %lu · 卡片 msg/appmsg/url",(unsigned long)index];
            if([text rangeOfString:@"<!DOCTYPE" options:NSCaseInsensitiveSearch].location!=NSNotFound || [text rangeOfString:@"<!ENTITY" options:NSCaseInsensitiveSearch].location!=NSNotFound) continue;
            WULinkXML *delegate=[WULinkXML new]; delegate.stack=[NSMutableArray array]; delegate.urls=[NSMutableArray array];
            NSXMLParser *parser=[[NSXMLParser alloc] initWithData:[text dataUsingEncoding:NSUTF8StringEncoding]]; parser.shouldResolveExternalEntities=NO; parser.delegate=delegate;
            if([parser parse] && !delegate.invalid && delegate.urls.count==1) { NSURL *u=WULinkSafeURL(delegate.urls.firstObject); if(u) [urls addObject:u]; }
        }
        for(NSURL *url in urls) if(![seen containsObject:url.absoluteString]) { [seen addObject:url.absoluteString]; [out addObject:@{@"url":url,@"source":source}]; if(out.count==10) return [out copy]; }
    }
    return [out copy];
}
