#import "ReadOnly.h"
#include <string.h>

static void (*ROOriginal)(id,SEL,id);
static void (^ROCallback)(id,id);
static void RODeliver(id owner, SEL command, id event) {
    // Public void sendEvent:(UIEvent *) ABI. No argument getter is called.
    ROOriginal(owner, command, event);
    @try { if(ROCallback) ROCallback(owner,event); }
    @catch(NSException *exception) { (void)exception; /* Observation must not change delivery. */ }
}
BOOL ROInstallObserver(Class cls, void (^observer)(id,id)) {
    if(ROOriginal || !cls || !observer) return NO;
    SEL selector=sel_registerName("sendEvent:");
    Method method=class_getInstanceMethod(cls,selector);
    if(!method || strcmp(method_getTypeEncoding(method), "v24@0:8@16")) return NO;
    ROOriginal=(void (*)(id,SEL,id))method_getImplementation(method);
    ROCallback=[observer copy];
    // Install on this application class only, never modify an inherited superclass slot.
    if(!class_addMethod(cls,selector,(IMP)RODeliver,method_getTypeEncoding(method)))
        method_setImplementation(class_getInstanceMethod(cls,selector),(IMP)RODeliver);
    return YES;
}
