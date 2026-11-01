#import "RepositoryLogic.h"
#import <objc/runtime.h>
#include <string.h>
static BOOL Text(id x, NSUInteger n) { return [x isKindOfClass:NSString.class] && [x length] && [x length]<=n; }
static BOOL RepoUInt(id x) { return [x isKindOfClass:NSNumber.class] && [x doubleValue]>=0 && [x doubleValue]<=(double)UINT32_MAX && [x doubleValue]==[x unsignedIntValue]; }
static BOOL Part(id p) {
    if(![p isKindOfClass:NSDictionary.class]) return NO;
    if([p[@"kind"] isEqual:@"text"]) return [p count]==2 && Text(p[@"text"],10000);
    if(![p[@"kind"] isEqual:@"reference"] || [p count]!=2) return NO;
    id m=p[@"identity"];
    if(![m isKindOfClass:NSDictionary.class] || [m count]!=7) return NO;
    for(NSString *key in @[@"from",@"to",@"real"]) if(![m[key] isKindOfClass:NSString.class] || [m[key] length]>256) return NO;
    return Text(m[@"from"],256) && Text(m[@"to"],256) && RepoUInt(m[@"local"]) && [m[@"local"] unsignedIntValue]>0 && RepoUInt(m[@"type"]) && RepoUInt(m[@"time"]) && [m[@"id"] isKindOfClass:NSNumber.class] && [m[@"id"] doubleValue]>=0;
}
BOOL WURepositoryValid(id items) {
    if(![items isKindOfClass:NSArray.class] || [items count]>200) return NO;
    NSMutableSet *ids=[NSMutableSet set];
    for(id item in items) {
        if(![item isKindOfClass:NSDictionary.class] || [item count]!=3 || !Text(item[@"id"],36) || ![[NSUUID alloc] initWithUUIDString:item[@"id"]] || [ids containsObject:item[@"id"]] || !Text(item[@"name"],80) || ![item[@"parts"] isKindOfClass:NSArray.class] || ![item[@"parts"] count] || [item[@"parts"] count]>50) return NO;
        [ids addObject:item[@"id"]]; for(id p in item[@"parts"]) if(!Part(p)) return NO;
    }
    return YES;
}
static BOOL Fail(NSError **e, NSString *s) { if(e) *e=[NSError errorWithDomain:@"WURepository" code:1 userInfo:@{NSLocalizedDescriptionKey:s}]; return NO; }
static NSURL *Path(NSURL *d, NSString *a) {
    if(!Text(a,256)) return nil;
    NSMutableString *name=[NSMutableString string]; NSData *data=[a dataUsingEncoding:NSUTF8StringEncoding];
    // Account names never become path separators. Separate atomic file, no shared config mutation.
    if(data.length>100) return nil;
    const unsigned char *bytes=data.bytes; for(NSUInteger i=0;i<data.length;i++) [name appendFormat:@"%02x",bytes[i]];
    return [d URLByAppendingPathComponent:[name stringByAppendingString:@".plist"]];
}
NSArray *WURepositoryLoad(NSURL *d, NSString *a, NSError **e) {
    NSURL *p=Path(d,a); if(!p) { Fail(e,@"账号不可用或过长"); return nil; }
    if(![NSFileManager.defaultManager fileExistsAtPath:p.path]) return @[];
    NSNumber *size=nil; if(![p getResourceValue:&size forKey:NSURLFileSizeKey error:e]) return nil;
    if(size.unsignedLongLongValue>1024*1024) { Fail(e,@"仓库超过1MiB，拒绝加载且不覆盖"); return nil; }
    NSData *data=[NSData dataWithContentsOfURL:p options:0 error:e]; if(!data) return nil;
    id root=[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:e];
    if(![root isKindOfClass:NSDictionary.class] || [root count]!=3 || ![root[@"version"] isEqual:@1] || ![root[@"account"] isEqual:a] || !WURepositoryValid(root[@"items"])) { Fail(e,@"仓库损坏或账号不符，未覆盖原文件"); return nil; }
    return root[@"items"];
}
BOOL WURepositorySave(NSURL *d, NSString *a, NSArray *items, NSError **e) {
    NSURL *p=Path(d,a); if(!p || !WURepositoryValid(items)) return Fail(e,@"内容无效或超过200条/每组50项/文本10000字限制");
    NSData *data=[NSPropertyListSerialization dataWithPropertyList:@{@"version":@1,@"account":a,@"items":items} format:NSPropertyListBinaryFormat_v1_0 options:0 error:e];
    if(!data) return NO; if(data.length>1024*1024) return Fail(e,@"仓库超过1MiB，保存被拒绝");
    if(![NSFileManager.defaultManager createDirectoryAtURL:d withIntermediateDirectories:YES attributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} error:e]) return NO;
    return [data writeToURL:p options:NSDataWritingAtomic error:e];
}
BOOL WURepositoryCanInvoke(id receiver, NSString *selector) {
    Method m=receiver?class_getInstanceMethod(object_getClass(receiver),NSSelectorFromString(selector)):NULL;
    if(!m || method_getNumberOfArguments(m)!=4) return NO;
    char *r=method_copyReturnType(m); BOOL ok=!strcmp(r,"v") || !strcmp(r,"B") || !strcmp(r,"c"); free(r);
    for(unsigned i=2;i<4;i++) { char *t=method_copyArgumentType(m,i); ok=ok && !strcmp(t,"@"); free(t); }
    return ok;
}
NSString *WURepositoryInvoke(id receiver, NSString *selector, id first, id second) {
    if(!first || !second || !WURepositoryCanInvoke(receiver,selector)) return @"失败：接口不可用，未提交";
    BOOL submitted=NO;
    @try {
        SEL sel=NSSelectorFromString(selector); NSInvocation *v=[NSInvocation invocationWithMethodSignature:[receiver methodSignatureForSelector:sel]];
        v.target=receiver; v.selector=sel; __unsafe_unretained id a=first,b=second;
        [v setArgument:&a atIndex:2]; [v setArgument:&b atIndex:3]; submitted=YES; [v invoke];
        return @"已请求（非送达）";
    } @catch(NSException *exception) { return submitted?@"未知：调用异常，请核对宿主，勿盲重发":@"失败：未提交"; }
}
