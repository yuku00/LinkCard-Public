#import "MessageLogic.h"
#import <limits.h>
@interface WURevokeParser : NSObject <NSXMLParserDelegate>
@property(nonatomic,strong) NSMutableArray *path;
@property(nonatomic,strong) NSMutableDictionary *fields;
@property(nonatomic,strong) NSMutableString *text;
@property(nonatomic) BOOL invalid;
@end
@implementation WURevokeParser
- (void)parser:(NSXMLParser *)p didStartElement:(NSString *)n namespaceURI:(NSString *)u qualifiedName:(NSString *)q attributes:(NSDictionary *)a {
    if(self.text) self.invalid=YES; // Identity fields must contain text/CDATA only.
    [self.path addObject:n];
    if(self.path.count>12) { self.invalid=YES; [p abortParsing]; }
    if(self.path.count==1 && (![n isEqual:@"sysmsg"] || ![a[@"type"] isEqual:@"revokemsg"])) self.invalid=YES;
    if([n isEqual:@"session"] || [n isEqual:@"newmsgid"]) {
        if(![self.path isEqual:@[@"sysmsg",@"revokemsg",n]] || self.fields[n]) self.invalid=YES;
        self.text=[NSMutableString string];
    }
}
- (void)parser:(NSXMLParser *)p foundCharacters:(NSString *)s { [self.text appendString:s]; }
- (void)parser:(NSXMLParser *)p foundCDATA:(NSData *)d { NSString *s=[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding]; if(!s) self.invalid=YES; else [self.text appendString:s]; }
- (void)parser:(NSXMLParser *)p didEndElement:(NSString *)n namespaceURI:(NSString *)u qualifiedName:(NSString *)q {
    if([n isEqual:@"session"] || [n isEqual:@"newmsgid"]) { self.fields[n]=self.text ?: @""; self.text=nil; }
    [self.path removeLastObject];
}
@end
NSDictionary *WURevokeFields(NSString *xml) {
    if(![xml isKindOfClass:NSString.class] || xml.length>65536 || [xml rangeOfString:@"<!DOCTYPE" options:NSCaseInsensitiveSearch].location!=NSNotFound || [xml rangeOfString:@"<!ENTITY" options:NSCaseInsensitiveSearch].location!=NSNotFound) return nil;
    WURevokeParser *d=[WURevokeParser new]; d.path=[NSMutableArray array]; d.fields=[NSMutableDictionary dictionary];
    NSXMLParser *p=[[NSXMLParser alloc] initWithData:[xml dataUsingEncoding:NSUTF8StringEncoding]]; p.delegate=d; p.shouldResolveExternalEntities=NO;
    if(![p parse] || d.invalid) return nil;
    NSString *s=d.fields[@"session"], *n=d.fields[@"newmsgid"];
    if(!s.length || s.length>256 || !n.length || n.length>19) return nil;
    unsigned long long value=0;
    for(NSUInteger i=0;i<n.length;i++) { unichar c=[n characterAtIndex:i]; if(c<'0'||c>'9'||value>((unsigned long long)LLONG_MAX-(c-'0'))/10) return nil; value=value*10+c-'0'; }
    return value?@{@"session":s,@"id":@(value)}:nil;
}
BOOL WUOwnMessage(NSString *a, NSString *s, NSString *f, NSString *r) {
    return a.length && s.length && ([f isEqual:a] || ([s hasSuffix:@"@chatroom"] && [r isEqual:a]));
}
BOOL WURevokeEligible(NSString *a, NSString *s, NSDictionary *m, NSTimeInterval now) {
    if(!WUOwnMessage(a,s,m[@"from"],m[@"real"]) || ![m[@"id"] unsignedLongLongValue]) return NO;
    double time=[m[@"time"] doubleValue]; unsigned type=[m[@"type"] unsignedIntValue];
    // Conservative local gate, not a promise about the server's recall window.
    return type>0 && type<10000 && time>0 && time<=now && now-time<=120;
}
BOOL WUGroupAdjacent(NSDictionary *a, NSDictionary *b) {
    if(![a[@"session"] length] || ![a[@"sender"] length] || ![a[@"session"] isEqual:b[@"session"]] || ![a[@"sender"] isEqual:b[@"sender"]]) return NO;
    double x=[a[@"time"] doubleValue], y=[b[@"time"] doubleValue];
    return ![a[@"separator"] boolValue] && ![b[@"separator"] boolValue] && x>0 && y>=x && y-x<300;
}
