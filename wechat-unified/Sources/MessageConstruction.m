#import "MessageConstruction.h"
#import <objc/runtime.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
// Protocol-qualified init calls preserve ARC's consumed receiver and retained result,
// including an initializer returning a different object. Never invoke init via NSInvocation.
@protocol WUConstructI <NSObject>
- (instancetype)initWithMsgType:(unsigned int)type nsFromUsr:(NSString *)account;
@end
@protocol WUConstructi <NSObject>
- (instancetype)initWithMsgType:(int)type nsFromUsr:(NSString *)account;
@end
@protocol WUConstructq <NSObject>
- (instancetype)initWithMsgType:(long long)type nsFromUsr:(NSString *)account;
@end
@protocol WUConstructQ <NSObject>
- (instancetype)initWithMsgType:(unsigned long long)type nsFromUsr:(NSString *)account;
@end
@protocol WUConstructOneI <NSObject>
- (instancetype)initWithMsgType:(unsigned int)type;
@end
@protocol WUConstructOnei <NSObject>
- (instancetype)initWithMsgType:(int)type;
@end
@protocol WUConstructOneq <NSObject>
- (instancetype)initWithMsgType:(long long)type;
@end
@protocol WUConstructOneQ <NSObject>
- (instancetype)initWithMsgType:(unsigned long long)type;
@end
static SEL Constructor(void) { return NSSelectorFromString(@"initWithMsgType:nsFromUsr:"); }
static SEL OneConstructor(void) { return NSSelectorFromString(@"initWithMsgType:"); }
static char ConstructorEncoding(Class cls, SEL selector, NSMethodSignature *sig, unsigned count) {
    Method m=cls?class_getInstanceMethod(cls,selector):NULL;
    if(!m || !sig || method_getNumberOfArguments(m)!=count || sig.numberOfArguments!=count || sig.methodReturnLength!=sizeof(id)) return 0;
    char *r=method_copyReturnType(m);
    BOOL ok=r && !strcmp(r,"@") && !strcmp(sig.methodReturnType,r); free(r);
    char kind=0;
    for(unsigned i=0; i<count && ok; i++) {
        char *t=method_copyArgumentType(m,i);
        ok=t && !strcmp(t,[sig getArgumentTypeAtIndex:i]);
        if(ok && i==2) {
            ok=strlen(t)==1 && strchr("iIqQ",t[0]);
            if(ok) kind=t[0];
        } else if(ok) ok=!strcmp(t,i==1?":":"@");
        free(t);
    }
    return ok?kind:0;
}
BOOL WUMessageCanConstruct(Class cls) {
    @try { return ConstructorEncoding(cls,Constructor(),[cls instanceMethodSignatureForSelector:Constructor()],4)!=0; }
    @catch(NSException *e) { return NO; }
}
// An exception is not a nil initializer result: never try another initializer after it.
static id CreatePreferred(Class cls, uint64_t type, NSString *account, BOOL *fallback) {
    *fallback=NO;
    @try {
        if(![account isKindOfClass:NSString.class] || !account.length) return nil;
        char classKind=ConstructorEncoding(cls,Constructor(),[cls instanceMethodSignatureForSelector:Constructor()],4);
        if(!classKind) { *fallback=YES; return nil; }
        id allocated=[cls alloc];
        char kind=ConstructorEncoding(object_getClass(allocated),Constructor(),[allocated methodSignatureForSelector:Constructor()],4);
        if(kind!=classKind) { *fallback=YES; return nil; }
        id result=nil;
        switch(kind) {
            case 'I': if(sizeof(unsigned int)==4 && type<=UINT_MAX) result=[(id<WUConstructI>)allocated initWithMsgType:(unsigned int)type nsFromUsr:account]; break;
            case 'i': if(sizeof(int)==4 && type<=INT_MAX) result=[(id<WUConstructi>)allocated initWithMsgType:(int)type nsFromUsr:account]; break;
            case 'q': if(sizeof(long long)==8 && type<=LLONG_MAX) result=[(id<WUConstructq>)allocated initWithMsgType:(long long)type nsFromUsr:account]; break;
            case 'Q': if(sizeof(unsigned long long)==8) result=[(id<WUConstructQ>)allocated initWithMsgType:(unsigned long long)type nsFromUsr:account]; break;
        }
        *fallback=!result;
        return result;
    } @catch(NSException *e) { return nil; }
}
id WUCreateMessage(Class cls, uint64_t type, NSString *account) {
    BOOL ignored=NO;
    return CreatePreferred(cls,type,account,&ignored);
}
id WUCreateVoiceMessage(Class cls, uint64_t type, NSString *account) {
    BOOL fallback=NO;
    id result=CreatePreferred(cls,type,account,&fallback);
    if(result || !fallback) return result;
    @try {
        SEL selector=OneConstructor();
        char classKind=ConstructorEncoding(cls,selector,[cls instanceMethodSignatureForSelector:selector],3);
        if(!classKind) return nil;
        id allocated=[cls alloc];
        char kind=ConstructorEncoding(object_getClass(allocated),selector,[allocated methodSignatureForSelector:selector],3);
        if(kind!=classKind) return nil;
        switch(kind) {
            case 'I': if(sizeof(unsigned int)==4 && type<=UINT_MAX) return [(id<WUConstructOneI>)allocated initWithMsgType:(unsigned int)type]; break;
            case 'i': if(sizeof(int)==4 && type<=INT_MAX) return [(id<WUConstructOnei>)allocated initWithMsgType:(int)type]; break;
            case 'q': if(sizeof(long long)==8 && type<=LLONG_MAX) return [(id<WUConstructOneq>)allocated initWithMsgType:(long long)type]; break;
            case 'Q': if(sizeof(unsigned long long)==8) return [(id<WUConstructOneQ>)allocated initWithMsgType:(unsigned long long)type]; break;
        }
    } @catch(NSException *e) { return nil; }
    return nil;
}
