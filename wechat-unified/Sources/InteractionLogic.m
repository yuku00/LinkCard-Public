#import "InteractionLogic.h"
BOOL WUSurfaceValueOwned(id current, id applied) { return applied && (current==applied || [current isEqual:applied]); }
NSUInteger WUInputEffect(BOOL border, BOOL pulse, BOOL visible, BOOL editing, BOOL active, BOOL reducedMotion) {
    if(!visible || !active) return 0;
    if(pulse && editing && !reducedMotion) return 2;
    return border?1:0;
}
@interface WUFileCardParser : NSObject <NSXMLParserDelegate>
@property(nonatomic,strong) NSMutableArray *path;
@property(nonatomic,strong) NSMutableString *type;
@property(nonatomic) NSUInteger count, appCount;
@property(nonatomic) BOOL invalid;
@end
@implementation WUFileCardParser
- (void)parser:(NSXMLParser *)p didStartElement:(NSString *)name namespaceURI:(NSString *)uri qualifiedName:(NSString *)q attributes:(NSDictionary *)a {
    [self.path addObject:name]; if(self.path.count>16) { self.invalid=YES; [p abortParsing]; }
    if([self.path isEqual:@[@"msg",@"appmsg"]]) self.appCount++;
    if([self.path isEqual:@[@"msg",@"appmsg",@"type"]]) { self.count++; self.type=[NSMutableString string]; }
    else if(self.path.count>3 && [self.path[0] isEqual:@"msg"] && [self.path[1] isEqual:@"appmsg"] && [self.path[2] isEqual:@"type"]) self.invalid=YES;
}
- (void)parser:(NSXMLParser *)p foundCharacters:(NSString *)text { if([self.path isEqual:@[@"msg",@"appmsg",@"type"]]) [self.type appendString:text]; }
- (void)parser:(NSXMLParser *)p foundCDATA:(NSData *)data { NSString *s=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]; if(s) [self parser:p foundCharacters:s]; else self.invalid=YES; }
- (void)parser:(NSXMLParser *)p didEndElement:(NSString *)name namespaceURI:(NSString *)uri qualifiedName:(NSString *)q { [self.path removeLastObject]; }
@end
NSString *WUCardRole(NSUInteger type, NSString *content) {
    if(type==47) return @"emoticonSurface";
    if(type!=49 || ![content isKindOfClass:NSString.class] || !content.length || content.length>65536) return nil;
    if([content rangeOfString:@"<!DOCTYPE" options:NSCaseInsensitiveSearch].location!=NSNotFound || [content rangeOfString:@"<!ENTITY" options:NSCaseInsensitiveSearch].location!=NSNotFound) return nil;
    WUFileCardParser *d=[WUFileCardParser new]; d.path=[NSMutableArray array];
    NSXMLParser *p=[[NSXMLParser alloc] initWithData:[content dataUsingEncoding:NSUTF8StringEncoding]]; p.shouldResolveExternalEntities=NO; p.delegate=d;
    return [p parse] && !d.invalid && d.appCount==1 && d.count==1 && [[d.type stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] isEqual:@"6"]?@"fileSurface":nil;
}
