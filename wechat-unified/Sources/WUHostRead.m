#import "WUHostRead.h"
#import <objc/runtime.h>
#import <objc/message.h>
#include <string.h>
#include <stdbool.h>
static NSMethodSignature *Signature(id object, NSString *name, NSUInteger arguments) {
    if(!object || object_isClass(object)) return nil;
    Method m=class_getInstanceMethod(object_getClass(object),NSSelectorFromString(name));
    if(!m || method_getNumberOfArguments(m)!=arguments+2) return nil;
    NSMethodSignature *s=[NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(m)];
    for(NSUInteger i=2;i<s.numberOfArguments;i++) if(strcmp([s getArgumentTypeAtIndex:i],"@")) return nil;
    return s;
}
BOOL WUHostIs(id object, NSString *name) { Class c=NSClassFromString(name); return c && object && !object_isClass(object) && [object isKindOfClass:c]; }
NSString *WUHostString(id value, NSUInteger limit) { return [value isKindOfClass:NSString.class] && [value length]<=limit ? [value copy] : nil; }
id WUHostObject(id object, NSString *name, id argument, BOOL hasArgument) {
    @try {
        NSMethodSignature *s=Signature(object,name,hasArgument?1:0); if(!s || strcmp(s.methodReturnType,"@")) return nil;
        SEL sel=NSSelectorFromString(name);
        return hasArgument?((id(*)(id,SEL,id))objc_msgSend)(object,sel,argument):((id(*)(id,SEL))objc_msgSend)(object,sel);
    } @catch(__unused NSException *e) { return nil; }
}
NSNumber *WUHostUInt32(id object, NSString *name) {
    @try {
        NSMethodSignature *s=Signature(object,name,0); if(!s) return nil; SEL sel=NSSelectorFromString(name);
        if(!strcmp(s.methodReturnType,"I")) return @(((uint32_t(*)(id,SEL))objc_msgSend)(object,sel));
        if(!strcmp(s.methodReturnType,"i")) { int32_t n=((int32_t(*)(id,SEL))objc_msgSend)(object,sel); return n>=0?@(n):nil; }
        return nil;
    } @catch(__unused NSException *e) { return nil; }
}
NSNumber *WUHostBool(id object, NSString *name) {
    @try {
        NSMethodSignature *s=Signature(object,name,0); if(!s) return nil; SEL sel=NSSelectorFromString(name);
        if(!strcmp(s.methodReturnType,"B")) return @(((bool(*)(id,SEL))objc_msgSend)(object,sel));
        if(!strcmp(s.methodReturnType,"c")) { signed char n=((signed char(*)(id,SEL))objc_msgSend)(object,sel); return n==0 || n==1?@(n):nil; }
        return nil;
    } @catch(__unused NSException *e) { return nil; }
}
