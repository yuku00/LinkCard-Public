#import "ThemeCatalog.h"
#import "ThemePrimitives.h"
static NSString *Trim(NSString *s) { return [s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; }
static NSString *Color(NSString *text,BOOL xml) {
    text=Trim(text).lowercaseString;
    if(xml&&text.length==5&&[text hasPrefix:@"#"]) text=[NSString stringWithFormat:@"#%@%@",[text substringFromIndex:2],[text substringWithRange:NSMakeRange(1,1)]];
    if(xml&&text.length==9&&[text hasPrefix:@"#"]) text=[NSString stringWithFormat:@"#%@%@",[text substringFromIndex:3],[text substringWithRange:NSMakeRange(1,2)]];
    double c[4]; if(!WUParseRGBA(text.UTF8String,c)) {
        BOOL alpha=[text hasPrefix:@"rgba("]; if(!alpha&&![text hasPrefix:@"rgb("]) return nil;
        if(![text hasSuffix:@")"]) return nil;
        NSArray *parts=[[text substringWithRange:NSMakeRange(alpha?5:4,text.length-(alpha?6:5))] componentsSeparatedByString:@","];
        if(parts.count!=(alpha?4:3)) return nil; c[3]=1;
        for(NSUInteger i=0;i<parts.count;i++) { NSScanner *s=[NSScanner scannerWithString:Trim(parts[i])]; double n; if(![s scanDouble:&n]||!s.isAtEnd||!WUStyleNumber(n,0,i==3?1:255)) return nil; c[i]=i==3?n:n/255.0; }
    }
    return [NSString stringWithFormat:@"#%02x%02x%02x%02x",(unsigned)lround(c[0]*255),(unsigned)lround(c[1]*255),(unsigned)lround(c[2]*255),(unsigned)lround(c[3]*255)];
}
static NSString *Token(NSString *name) {
    NSString *s=Trim(name).lowercaseString; if([s hasPrefix:@"--weui-"]) s=[s substringFromIndex:7];
    if([s hasPrefix:@"weui-"]) s=[s substringFromIndex:5];
    if([s hasPrefix:@"weui_"]) s=[[s substringFromIndex:5] stringByReplacingOccurrencesOfString:@"_" withString:@"-"];
    return [@[@"bg-0",@"bg-1",@"bg-2",@"fg-0",@"fg-1",@"fg-2",@"fg-3",@"brand",@"link",@"red"] containsObject:s]?s:nil;
}
@interface WUColorXML : NSObject <NSXMLParserDelegate>
@property(nonatomic,strong) NSMutableDictionary *colors;
@property(nonatomic,strong) NSMutableString *text;
@property(nonatomic,copy) NSString *key;
@property(nonatomic,assign) BOOL bad;
@end
@implementation WUColorXML
- (void)parser:(NSXMLParser *)p didStartElement:(NSString *)name namespaceURI:(NSString *)uri qualifiedName:(NSString *)q attributes:(NSDictionary *)a {
    if([name isEqual:@"color"]) { if(self.key) { self.bad=YES; [p abortParsing]; return; } self.key=Token(a[@"name"]?:@""); self.text=[NSMutableString string]; }
    else if(![name isEqual:@"resources"]&&! [name isEqual:@"colors"]) { self.bad=YES; [p abortParsing]; }
}
- (void)parser:(NSXMLParser *)p foundCharacters:(NSString *)s { [self.text appendString:s]; }
- (void)parser:(NSXMLParser *)p didEndElement:(NSString *)name namespaceURI:(NSString *)uri qualifiedName:(NSString *)q {
    if([name isEqual:@"color"]) { if(self.key) { NSString *c=Color(self.text,YES); if(!c) self.bad=YES; else self.colors[self.key]=c; } self.key=nil; self.text=nil; }
}
@end
NSDictionary *WUThemeReadColors(NSData *data,NSString *ext,BOOL darkFile,NSError **error) {
    NSString *text=data.length<=512*1024?[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]:nil;
    NSMutableDictionary *light=[NSMutableDictionary dictionary],*dark=[NSMutableDictionary dictionary]; BOOL ok=text.length>0;
    if([ext.lowercaseString isEqual:@"xml"]&&ok) {
        ok=[text.uppercaseString rangeOfString:@"<!DOCTYPE"].location==NSNotFound&&[text.uppercaseString rangeOfString:@"<!ENTITY"].location==NSNotFound;
        WUColorXML *delegate=[WUColorXML new]; delegate.colors=[NSMutableDictionary dictionary];
        NSXMLParser *parser=[[NSXMLParser alloc] initWithData:data]; parser.shouldResolveExternalEntities=NO; parser.delegate=delegate;
        ok=ok&&[parser parse]&&!delegate.bad; [(darkFile?dark:light) addEntriesFromDictionary:delegate.colors];
    } else if([ext.lowercaseString isEqual:@"css"]&&ok) {
        // Literal custom-property declarations only, not a web engine. No @import, url(), scripts or network.
        NSString *lower=text.lowercaseString; ok=![lower containsString:@"@import"]&&![lower containsString:@"url("];
        NSRegularExpression *comments=[NSRegularExpression regularExpressionWithPattern:@"/\\*[\\s\\S]*?\\*/" options:0 error:NULL];
        text=[comments stringByReplacingMatchesInString:text options:0 range:NSMakeRange(0,text.length) withTemplate:@""];
        NSRegularExpression *tokens=[NSRegularExpression regularExpressionWithPattern:@"([^{}]*)\\{|\\}|(--weui-[a-zA-Z0-9-]+)\\s*:\\s*([^;{}]+);?" options:0 error:NULL];
        NSMutableArray *stack=[NSMutableArray array];
        for(NSTextCheckingResult *m in [tokens matchesInString:text options:0 range:NSMakeRange(0,text.length)]) {
            NSString *piece=[text substringWithRange:m.range];
            if([piece hasSuffix:@"{"]) { NSString *s=piece.lowercaseString; BOOL isDark=stack.count?[stack.lastObject boolValue]:darkFile; if([s containsString:@"dark"]) isDark=YES; if([s containsString:@"light"]) isDark=NO; [stack addObject:@(isDark)]; }
            else if([piece isEqual:@"}"]) { if(!stack.count) { ok=NO; break; } [stack removeLastObject]; }
            else if([m rangeAtIndex:2].location!=NSNotFound) {
                NSString *key=Token([text substringWithRange:[m rangeAtIndex:2]]); if(!key) continue;
                NSString *value=Color([text substringWithRange:[m rangeAtIndex:3]],NO); if(!value) { ok=NO; break; }
                NSMutableDictionary *palette=(stack.count?[stack.lastObject boolValue]:darkFile)?dark:light; palette[key]=value;
            }
        }
        if(stack.count) ok=NO;
    } else ok=NO;
    if(!ok||!(light.count+dark.count)) { if(error) *error=[NSError errorWithDomain:@"WeChatUnified.ThemeColors" code:1 userInfo:@{NSLocalizedDescriptionKey:@"色表须为可解析的WeUI字面色值：CSS --weui-BG/FG/BRAND/LINK/RED，或resources/color XML；不加载任意CSS布局或外部引用。"}]; return nil; }
    return @{@"light":light,@"dark":dark};
}
