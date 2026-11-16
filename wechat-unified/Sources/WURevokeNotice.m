#import "WURevokeNotice.h"
#import "MessageConstruction.h"
extern id WUValue(NSString *key);
#import <objc/runtime.h>
#import <objc/message.h>
#include <string.h>

@protocol WUNoticeInitI <NSObject>
- (instancetype)initWithMsgType:(unsigned int)type;
@end
@protocol WUNoticeIniti <NSObject>
- (instancetype)initWithMsgType:(int)type;
@end
@protocol WUNoticeInitQ <NSObject>
- (instancetype)initWithMsgType:(unsigned long long)type;
@end
@protocol WUNoticeInitq <NSObject>
- (instancetype)initWithMsgType:(long long)type;
@end

static NSMethodSignature *Signature(Class cls, SEL sel) {
    Method m=cls ? class_getInstanceMethod(cls,sel) : NULL;
    return m ? [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(m)] : nil;
}
static BOOL Match(NSMethodSignature *s, const char *ret, NSArray<NSString *> *args) {
    if (!s || s.numberOfArguments!=args.count+2 || strcmp(s.methodReturnType,ret) ||
        strcmp([s getArgumentTypeAtIndex:0],"@") || strcmp([s getArgumentTypeAtIndex:1],":")) return NO;
    for (NSUInteger i=0;i<args.count;i++) if (strcmp([s getArgumentTypeAtIndex:i+2],args[i].UTF8String)) return NO;
    return YES;
}
static id NewNotice(Class cls, NSString *account) {
    SEL sel=NSSelectorFromString(@"initWithMsgType:");
    NSMethodSignature *s=Signature(cls,sel);
    if (s && s.numberOfArguments==3 && !strcmp(s.methodReturnType,"@") &&
        !strcmp([s getArgumentTypeAtIndex:0],"@") && !strcmp([s getArgumentTypeAtIndex:1],":")) {
        const char *t=[s getArgumentTypeAtIndex:2];
        if (!strcmp(t,"I")) return [(id<WUNoticeInitI>)[cls alloc] initWithMsgType:10000];
        if (!strcmp(t,"i")) return [(id<WUNoticeIniti>)[cls alloc] initWithMsgType:10000];
        if (!strcmp(t,"Q")) return [(id<WUNoticeInitQ>)[cls alloc] initWithMsgType:10000];
        if (!strcmp(t,"q")) return [(id<WUNoticeInitq>)[cls alloc] initWithMsgType:10000];
    }
    return WUCreateMessage(cls,10000,account);
}
static BOOL SetObject(id obj, NSString *name, id value) {
    SEL sel=NSSelectorFromString(name);
    if (!Match(Signature(object_getClass(obj),sel),"v",@[@"@"])) return NO;
    ((void(*)(id,SEL,id))objc_msgSend)(obj,sel,value); return YES;
}
static BOOL SetNumber(id obj, NSString *name, uint32_t value) {
    SEL sel=NSSelectorFromString(name); NSMethodSignature *s=Signature(object_getClass(obj),sel);
    if (Match(s,"v",@[@"I"])) { ((void(*)(id,SEL,unsigned int))objc_msgSend)(obj,sel,value); return YES; }
    if (value<=INT32_MAX && Match(s,"v",@[@"i"])) { ((void(*)(id,SEL,int))objc_msgSend)(obj,sel,(int)value); return YES; }
    return NO;
}
static BOOL CanInsert(id manager) {
    Class host=NSClassFromString(@"CMessageMgr"), cls=object_getClass(manager); BOOL instance=NO, proxy=NO;
    for (Class c=cls;c;c=class_getSuperclass(c)) { if (c==host && host) instance=YES; if (c==objc_getClass("NSProxy")) proxy=YES; }
    SEL sel=NSSelectorFromString(@"AddLocalMsg:MsgWrap:fixTime:NewMsgArriveNotify:");
    NSMethodSignature *s=Signature(instance?cls:host,sel);
    BOOL boolABI=Match(s,"v",@[@"@",@"@",@"B",@"B"]);
    BOOL charABI=Match(s,"v",@[@"@",@"@",@"c",@"c"]);
    if (!boolABI && !charABI) return NO;
    if (instance) return YES;
    if (!proxy || class_getInstanceMethod(cls,sel)) return NO;
    NSMethodSignature *forward=[manager methodSignatureForSelector:sel];
    return boolABI ? Match(forward,"v",@[@"@",@"@",@"B",@"B"]) : Match(forward,"v",@[@"@",@"@",@"c",@"c"]);
}
void WURevokeNoticeInsert(id manager, NSString *account, NSString *session,
                          uint64_t serverID, NSUInteger generation,
                          NSString *from, NSString *to, uint32_t createTime,
                          BOOL (^valid)(void)) {
    @try {
        if (!manager || !account.length || !session.length || !serverID || !generation ||
            !from.length || !to.length || !valid || ![(WUValue(@"antiRevokeNotice") ?: @YES) boolValue]) return;
        static NSMutableSet *seen; static NSString *lastAccount; static NSUInteger lastGeneration;
        @synchronized ([NSProcessInfo class]) {
            if (!valid() || ![(WUValue(@"antiRevokeNotice") ?: @YES) boolValue]) return;
            if (!seen) seen=[NSMutableSet set];
            if (lastGeneration!=generation || ![lastAccount isEqualToString:account]) {
                [seen removeAllObjects]; lastAccount=[account copy]; lastGeneration=generation;
            }
            NSArray *key=@[account,session,@(serverID),@(generation)];
            if ([seen containsObject:key] || seen.count>=4096 || !CanInsert(manager)) return;
            id wrap=NewNotice(NSClassFromString(@"CMessageWrap"),account);
            if (!wrap || !SetObject(wrap,@"setM_nsFromUsr:",from) ||
                !SetObject(wrap,@"setM_nsToUsr:",to) || !SetNumber(wrap,@"setM_uiStatus:",4) ||
                !SetObject(wrap,@"setM_nsContent:",@"对方撤回了一条消息") ||
                (createTime && !SetNumber(wrap,@"setM_uiCreateTime:",createTime)) || !valid()) return;
            // Reserve before the call: an exception may follow a partial local insertion.
            [seen addObject:key];
            ((void(*)(id,SEL,id,id,BOOL,BOOL))objc_msgSend)(manager,NSSelectorFromString(@"AddLocalMsg:MsgWrap:fixTime:NewMsgArriveNotify:"),session,wrap,YES,NO);
        }
    } @catch (NSException *exception) { /* Never alter the already-made protection decision. */ }
}
