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
static SEL Constructor(void) { return NSSelectorFromString(@"initWithMsgType:nsFromUsr:"); }
static char ConstructorEncoding(Class cls, NSMethodSignature *sig) {
    Method m=cls?class_getInstanceMethod(cls,Constructor()):NULL;
    if(!m || !sig || method_getNumberOfArguments(m)!=4 || sig.numberOfArguments!=4 || sig.methodReturnLength!=sizeof(id)) return 0;
    char *r=method_copyReturnType(m);
    BOOL ok=r && !strcmp(r,"@") && !strcmp(sig.methodReturnType,r); free(r);
    char kind=0;
    for(unsigned i=0; i<4 && ok; i++) {
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
    @try { return ConstructorEncoding(cls,[cls instanceMethodSignatureForSelector:Constructor()])!=0; }
    @catch(NSException *e) { return NO; }
}
id WUCreateMessage(Class cls, uint64_t type, NSString *account) {
    @try {
        if(![account isKindOfClass:NSString.class] || !account.length || !WUMessageCanConstruct(cls)) return nil;
        id allocated=[cls alloc];
        // Recheck the actual receiver: instance signature overrides may disagree with the class.
        switch(ConstructorEncoding(object_getClass(allocated),[allocated methodSignatureForSelector:Constructor()])) {
            case 'I': if(sizeof(unsigned int)==4 && type<=UINT_MAX) return [(id<WUConstructI>)allocated initWithMsgType:(unsigned int)type nsFromUsr:account]; break;
            case 'i': if(sizeof(int)==4 && type<=INT_MAX) return [(id<WUConstructi>)allocated initWithMsgType:(int)type nsFromUsr:account]; break;
            case 'q': if(sizeof(long long)==8 && type<=LLONG_MAX) return [(id<WUConstructq>)allocated initWithMsgType:(long long)type nsFromUsr:account]; break;
            case 'Q': if(sizeof(unsigned long long)==8) return [(id<WUConstructQ>)allocated initWithMsgType:(unsigned long long)type nsFromUsr:account]; break;
        }
    } @catch(NSException *e) { return nil; }
    return nil;
}
