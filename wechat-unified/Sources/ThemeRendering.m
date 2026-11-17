#import "WU.h"
#import "ThemeRendering.h"
#import "ThemeCatalog.h"
#import <ImageIO/ImageIO.h>
#import <sys/stat.h>
static NSMutableDictionary *catalogs;
static NSString *catalogRoot;
static Method SVGMethod(void) { return class_getClassMethod(NSClassFromString(@"WCSVGImage"),NSSelectorFromString(@"imageWithContentsOfFile:size:color:alpha:rotate:")); }
static BOOL SVGAvailable(void) { return WUMatches(SVGMethod(),"@",@[@"@",[NSString stringWithUTF8String:@encode(CGSize)],@"@",[NSString stringWithUTF8String:@encode(CGFloat)],[NSString stringWithUTF8String:@encode(CGFloat)]]); }
BOOL WUThemeValidImage(NSData *d) {
    if(!d.length||d.length>8*1024*1024) return NO;
    CGImageSourceRef src=CGImageSourceCreateWithData((__bridge CFDataRef)d,NULL); if(!src) return NO;
    NSDictionary *p=CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(src,0,NULL));
    NSUInteger w=[p[(id)kCGImagePropertyPixelWidth] unsignedIntegerValue],h=[p[(id)kCGImagePropertyPixelHeight] unsignedIntegerValue];
    BOOL valid=w&&h&&w<=4096&&h<=4096&&w*h<=8*1024*1024;
    CGImageRef im=valid?CGImageSourceCreateImageAtIndex(src,0,NULL):NULL; valid=im!=NULL; if(im) CGImageRelease(im); CFRelease(src); return valid;
}
@interface WULocalSVG : NSObject <NSXMLParserDelegate>
@property(nonatomic,assign) BOOL valid;
@property(nonatomic,assign) NSUInteger elements;
@end
@implementation WULocalSVG
- (void)parser:(NSXMLParser *)p didStartElement:(NSString *)name namespaceURI:(NSString *)uri qualifiedName:(NSString *)q attributes:(NSDictionary *)attrs {
    // Keep ordinary vector geometry; never pass external loads, scripts or HTML to the host SVG decoder.
    NSSet *allowed=[NSSet setWithArray:@[@"svg",@"g",@"path",@"rect",@"circle",@"ellipse",@"line",@"polyline",@"polygon",@"defs",@"linearGradient",@"radialGradient",@"stop",@"clipPath",@"mask",@"title",@"desc",@"use"]];
    if(![allowed containsObject:name]||++self.elements>10000) self.valid=NO;
    for(NSString *k in attrs) { NSString *v=[attrs[k] lowercaseString];
        NSRegularExpression *local=[NSRegularExpression regularExpressionWithPattern:@"url\\(\\s*#[a-z0-9_.:-]+\\s*\\)" options:0 error:NULL];
        NSString *withoutLocal=[local stringByReplacingMatchesInString:v options:0 range:NSMakeRange(0,v.length) withTemplate:@""];
        if([k.lowercaseString hasPrefix:@"on"]||[withoutLocal containsString:@"url("]||[v containsString:@"javascript:"]||(([k.lowercaseString hasSuffix:@"href"])&&![v hasPrefix:@"#"])) self.valid=NO;
    }
    if(!self.valid) [p abortParsing];
}
@end
BOOL WUThemeValidateResource(NSString *p,NSData *d,NSString **failure) {
    NSString *ext=p.pathExtension.lowercaseString; BOOL valid=NO;
    if([@[@"png",@"jpg",@"jpeg",@"heic",@"webp"] containsObject:ext]) valid=WUThemeValidImage(d);
    else if([ext isEqual:@"svg"]) {
        NSString *s=d.length<=1024*1024?[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding]:nil;
        if(s.length&&[s.uppercaseString rangeOfString:@"<!DOCTYPE"].location==NSNotFound&&[s.uppercaseString rangeOfString:@"<!ENTITY"].location==NSNotFound&&SVGAvailable()) {
            WULocalSVG *delegate=[WULocalSVG new]; delegate.valid=YES; NSXMLParser *parser=[[NSXMLParser alloc] initWithData:d]; parser.shouldResolveExternalEntities=NO; parser.delegate=delegate;
            valid=[parser parse]&&delegate.valid&&delegate.elements>0;
        }
        if(!valid&&failure) *failure=@"SVG需宿主WCSVGImage的已核对签名；仅本地无脚本矢量子集。当前文件或渲染器不可用，未导入。";
    } else if([ext isEqual:@"car"]) valid=d.length>=8&&!memcmp(d.bytes,"BOMStore",8);
    else if([@[@"xml",@"css"] containsObject:ext]) { NSError *e=nil; valid=WUThemeReadColors(d,ext,NO,&e)!=nil; if(!valid&&failure) *failure=e.localizedDescription; }
    else if([p.lastPathComponent.lowercaseString isEqual:@"wu-theme.json"]) { NSError *e=nil; valid=WUThemeReadDescriptor(d,&e)!=nil; if(!valid&&failure) *failure=e.localizedDescription; }
    else { if(failure) *failure=[NSString stringWithFormat:@"未支持的资源：%@（没有静默导入后不显示）",p]; return NO; }
    if(!valid&&failure&&!*failure) *failure=[NSString stringWithFormat:@"无法解码或不支持的资源：%@",p]; return valid;
}
UIImage *WUThemeRenderFile(NSString *path,CGSize size,CGFloat scale,UIColor *color) {
    if([path.pathExtension.lowercaseString isEqual:@"svg"]) {
        if(!SVGAvailable()||!NSThread.isMainThread) return nil;
        if(size.width<=0||size.height<=0) size=CGSizeMake(64,64);
        @try { id result=((id(*)(id,SEL,id,CGSize,id,CGFloat,CGFloat))method_getImplementation(SVGMethod()))(NSClassFromString(@"WCSVGImage"),NSSelectorFromString(@"imageWithContentsOfFile:size:color:alpha:rotate:"),path,size,color?:UIColor.labelColor,1,0); return [result isKindOfClass:UIImage.class]?result:nil; } @catch(NSException *e) { return nil; }
    }
    NSData *data=[NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:NULL]; if(!WUThemeValidImage(data)) return nil;
    NSString *n=path.stringByDeletingPathExtension.lowercaseString; CGFloat fileScale=[n hasSuffix:@"@3x"]?3:([n hasSuffix:@"@2x"]?2:1);
    UIImage *image=[UIImage imageWithData:data scale:fileScale];
    if(image&&size.width>0&&size.height>0&&!CGSizeEqualToSize(size,image.size)) {
        UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat defaultFormat]; format.scale=scale; format.opaque=NO;
        image=[[[UIGraphicsImageRenderer alloc] initWithSize:size format:format] imageWithActions:^(UIGraphicsImageRendererContext *c){ [image drawInRect:(CGRect){CGPointZero,size}]; }];
    } return image;
}
UIImage *WUThemeRenderCatalog(NSString *path,NSString *name,UITraitCollection *traits) {
    @synchronized(NSProcessInfo.processInfo) {
        if(!catalogs) catalogs=[NSMutableDictionary dictionary];
        NSBundle *bundle=catalogs[path];
        if(!bundle) {
            if(catalogs.count>=32) WUThemeClearRenderCache();
            if(!catalogRoot) { catalogRoot=[NSTemporaryDirectory() stringByAppendingPathComponent:[@"wu-catalogs-" stringByAppendingString:NSUUID.UUID.UUIDString]]; [NSFileManager.defaultManager createDirectoryAtPath:catalogRoot withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:NULL]; }
            NSString *folder=[catalogRoot stringByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"bundle"]];
            if(![NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:NULL]) return nil;
            NSDictionary *info=@{@"CFBundleIdentifier":[@"org.wechatunified.resources." stringByAppendingString:NSUUID.UUID.UUIDString],@"CFBundleName":@"LocalTheme",@"CFBundlePackageType":@"BNDL",@"CFBundleVersion":@"1"};
            BOOL ok=[info writeToFile:[folder stringByAppendingPathComponent:@"Info.plist"] atomically:YES]&&[NSFileManager.defaultManager copyItemAtPath:path toPath:[folder stringByAppendingPathComponent:@"Assets.car"] error:NULL];
            if(ok) bundle=[NSBundle bundleWithPath:folder]; if(!bundle) { [NSFileManager.defaultManager removeItemAtPath:folder error:NULL]; return nil; } catalogs[path]=bundle;
        }
        // Public UIKit catalog decoding, not guessed CUICatalog signatures. Own bundle is excluded by Themes' hook.
        @try { return [UIImage imageNamed:name inBundle:bundle compatibleWithTraitCollection:traits]; } @catch(NSException *e) { return nil; }
    }
}
void WUThemeClearRenderCache(void) {
    @synchronized(NSProcessInfo.processInfo) { [catalogs removeAllObjects]; if(catalogRoot) [NSFileManager.defaultManager removeItemAtPath:catalogRoot error:NULL]; catalogRoot=nil; }
}
