#import "RepositoryLogic.h"
#import <objc/runtime.h>
#import <objc/message.h>
#include <string.h>
#include <errno.h>
#include <sys/stat.h>
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
    struct stat dirStat;
    if(stat(d.fileSystemRepresentation,&dirStat)!=0) {
        int code=errno; if(code==ENOENT) return @[];
        if(e) *e=[NSError errorWithDomain:NSPOSIXErrorDomain code:code userInfo:nil]; return nil;
    }
    if(!S_ISDIR(dirStat.st_mode)) { Fail(e,@"仓库目录不可用，未覆盖原文件"); return nil; }
    struct stat fileStat;
    if(stat(p.fileSystemRepresentation,&fileStat)!=0) {
        int code=errno; if(code==ENOENT) return @[];
        if(e) *e=[NSError errorWithDomain:NSPOSIXErrorDomain code:code userInfo:nil]; return nil;
    }
    if(!S_ISREG(fileStat.st_mode)) { Fail(e,@"仓库文件不可用，未覆盖原文件"); return nil; }
    if(fileStat.st_size>1024*1024) { Fail(e,@"仓库超过1MiB，拒绝加载且不覆盖"); return nil; }
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

// Verify direct methods, full-forwarding NSProxy signatures, or a verified fast target.
static BOOL RepoMethod(id object, NSString *selector, const char *result, NSArray<NSString *> *args, NSString *hostName);
BOOL WURepositoryFastService(id receiver, NSString *hostName, NSString *selector, const char *result, NSArray<NSString *> *args) {
    @try {
        if(!receiver || !hostName) return NO;
        SEL sel=NSSelectorFromString(selector);
        Class host=NSClassFromString(hostName);
        if(!host || class_getInstanceMethod(object_getClass(receiver),sel) ||
           !RepoMethod(receiver,@"forwardingTargetForSelector:","@",@[@":"],nil)) return NO;
        id target=((id(*)(id,SEL,SEL))objc_msgSend)(receiver,@selector(forwardingTargetForSelector:),sel);
        if(!target || target==receiver || ![target isKindOfClass:host]) return NO;
        // Check both the declared host ABI and the actual target's override.
        Method declared=class_getInstanceMethod(host,sel);
        if(!declared || method_getNumberOfArguments(declared)!=args.count+2) return NO;
        char *r=method_copyReturnType(declared); BOOL ok=r && !strcmp(r,result); free(r);
        for(NSUInteger i=0;i<args.count+2;i++) {
            const char *expected=i==0?"@":i==1?":":args[i-2].UTF8String;
            char *t=method_copyArgumentType(declared,(unsigned)i); ok=ok && t && !strcmp(t,expected); free(t);
        }
        return ok && RepoMethod(target,selector,result,args,nil);
    } @catch(NSException *e) { return NO; }
}
static BOOL RepoMethod(id object, NSString *selector, const char *result, NSArray<NSString *> *args, NSString *hostName) {
    @try {
        if(!object) return NO;
        SEL sel=NSSelectorFromString(selector);
        Method method=class_getInstanceMethod(object_getClass(object),sel);
        BOOL forwarded=method==NULL;
        if(forwarded && hostName && WURepositoryFastService(object,hostName,selector,result,args)) return YES;
        if(forwarded && hostName) {
            BOOL proxy=NO;
            for(Class c=object_getClass(object); c; c=class_getSuperclass(c)) if(c==objc_getClass("NSProxy")) { proxy=YES; break; }
            if(proxy) method=class_getInstanceMethod(NSClassFromString(hostName),sel);
        }
        if(!method || method_getNumberOfArguments(method)!=args.count+2) return NO;
        NSMethodSignature *sig=forwarded?[object methodSignatureForSelector:sel]:nil;
        if(forwarded && (!sig || sig.numberOfArguments!=args.count+2 || strcmp(sig.methodReturnType,result))) return NO;
        char *r=method_copyReturnType(method); BOOL ok=r && !strcmp(r,result); free(r);
        for(NSUInteger i=0;i<args.count+2;i++) {
            const char *expected=i==0?"@":i==1?":":args[i-2].UTF8String;
            char *type=method_copyArgumentType(method,(unsigned)i); const char *actual=forwarded?[sig getArgumentTypeAtIndex:i]:expected;
            ok=ok && type && actual && !strcmp(type,expected) && !strcmp(actual,expected); free(type);
        }
        return ok;
    } @catch(NSException *e) { return NO; }
}
id WURepositoryContact(id contacts, NSString *target) {
    @try {
        if(!Text(target,256) || !RepoMethod(contacts,@"getContactByName:","@",@[@"@"],@"CContactMgr")) return nil;
        id contact=((id(*)(id,SEL,id))objc_msgSend)(contacts,NSSelectorFromString(@"getContactByName:"),target);
        if(!RepoMethod(contact,@"m_nsUsrName","@",@[],nil)) return nil;
        id username=((id(*)(id,SEL))objc_msgSend)(contact,NSSelectorFromString(@"m_nsUsrName"));
        return [target isEqual:username]?contact:nil;
    } @catch(NSException *e) { return nil; }
}
NSString *WURepositorySendText(id manager, id sessionManager, id wrap, NSString *account, NSString *target, NSString *text, BOOL (^current)(void)) {
    BOOL submitted=NO;
    @try {
        if(!NSThread.isMainThread || !current || !current() || !Text(account,256) || !Text(target,256) || !Text(text,10000) ||
           !RepoMethod(manager,@"AddMsg:MsgWrap:","v",@[@"@",@"@"],@"CMessageMgr") ||
           !RepoMethod(sessionManager,@"GenSendMsgTime","I",@[],@"MMNewSessionMgr")) return @"失败：上下文或发送服务不可用，未提交";
        NSArray *setters=@[@"setM_nsFromUsr:",@"setM_nsToUsr:",@"setM_nsContent:"];
        NSArray *getters=@[@"m_nsFromUsr",@"m_nsToUsr",@"m_nsContent"];
        for(NSString *name in setters) if(!RepoMethod(wrap,name,"v",@[@"@"],nil)) return @"失败：文本字段ABI不符，未提交";
        for(NSString *name in getters) if(!RepoMethod(wrap,name,"@",@[],nil)) return @"失败：文本字段无法核验，未提交";
        for(NSString *name in @[@"setM_uiStatus:",@"setM_uiCreateTime:"]) if(!RepoMethod(wrap,name,"v",@[@"I"],nil)) return @"失败：文本整数ABI不符，未提交";
        for(NSString *name in @[@"m_uiMessageType",@"m_uiStatus",@"m_uiCreateTime"]) if(!RepoMethod(wrap,name,"I",@[],nil)) return @"失败：文本整数无法核验，未提交";
        unsigned type=((unsigned(*)(id,SEL))objc_msgSend)(wrap,NSSelectorFromString(@"m_uiMessageType"));
        if(type!=1) return @"失败：消息类型不符，未提交";
        unsigned time=((unsigned(*)(id,SEL))objc_msgSend)(sessionManager,NSSelectorFromString(@"GenSendMsgTime"));
        if(!time) return @"失败：宿主发送时间不可用，未提交";
        NSArray *values=@[account,target,text];
        for(NSUInteger i=0;i<setters.count;i++) ((void(*)(id,SEL,id))objc_msgSend)(wrap,NSSelectorFromString(setters[i]),values[i]);
        ((void(*)(id,SEL,unsigned))objc_msgSend)(wrap,NSSelectorFromString(@"setM_uiStatus:"),1);
        ((void(*)(id,SEL,unsigned))objc_msgSend)(wrap,NSSelectorFromString(@"setM_uiCreateTime:"),time);
        for(NSUInteger i=0;i<getters.count;i++) if(![values[i] isEqual:((id(*)(id,SEL))objc_msgSend)(wrap,NSSelectorFromString(getters[i]))]) return @"失败：文本字段核验不符，未提交";
        if(((unsigned(*)(id,SEL))objc_msgSend)(wrap,NSSelectorFromString(@"m_uiStatus"))!=1 || ((unsigned(*)(id,SEL))objc_msgSend)(wrap,NSSelectorFromString(@"m_uiCreateTime"))!=time) return @"失败：文本整数核验不符，未提交";
        if(!current() || !RepoMethod(manager,@"AddMsg:MsgWrap:","v",@[@"@",@"@"],@"CMessageMgr")) return @"失败：确认或发送服务已失效，未提交";
        submitted=YES;
        ((void(*)(id,SEL,id,id))objc_msgSend)(manager,NSSelectorFromString(@"AddMsg:MsgWrap:"),target,wrap);
        return @"已请求（非送达）；不自动重试";
    } @catch(NSException *e) { return submitted?@"未知：可能已提交，请核对宿主，未重试":@"失败：构造异常，未提交"; }
}
