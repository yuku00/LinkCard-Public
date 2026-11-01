#import "DraftsLogic.h"
#import <objc/runtime.h>
#include <string.h>
#include <stdlib.h>
// WCRefine 0x5d1d50..0x5d208c: SightDraft +draftWithVideoURL: (or
// +draftWithVideoURL:thumbImage:) receives a file NSURL, then WCNewCommitViewController
// -initWithSightDraft: receives the returned object. No upload/send selector here.
static BOOL ObjectMethod(Method method, unsigned count) {
    if(!method || method_getNumberOfArguments(method)!=count+2) return NO;
    char *t=method_copyReturnType(method); BOOL ok=!strcmp(t,"@"); free(t);
    for(unsigned i=2;i<count+2;i++) { t=method_copyArgumentType(method,i); ok=ok && !strcmp(t,"@"); free(t); }
    return ok;
}
BOOL WUDraftsVideoEditorAvailable(Class editor, Class factory) {
    return editor && factory && ObjectMethod(class_getInstanceMethod(editor,NSSelectorFromString(@"initWithSightDraft:")),1) &&
      (ObjectMethod(class_getClassMethod(factory,NSSelectorFromString(@"draftWithVideoURL:")),1) || ObjectMethod(class_getClassMethod(factory,NSSelectorFromString(@"draftWithVideoURL:thumbImage:")),2));
}
@protocol WUDraftVideoFactory
+ (id)draftWithVideoURL:(NSURL *)url;
+ (id)draftWithVideoURL:(NSURL *)url thumbImage:(id)image;
@end
@protocol WUDraftVideoInit
- (instancetype)initWithSightDraft:(id)draft;
@end
id WUDraftsCreateVideoEditor(Class editor, Class factory, NSURL *editingCopy, BOOL (^current)(void), id *expectedDraft) {
    if(expectedDraft) *expectedDraft=nil;
    if(!NSThread.isMainThread || !editingCopy.isFileURL || !current || !current() || !WUDraftsVideoEditorAvailable(editor,factory)) return nil;
    @try {
        id draft=nil;
        // An unavailable selector may use the independently observed alternative; a failed call is never retried.
        if(ObjectMethod(class_getClassMethod(factory,NSSelectorFromString(@"draftWithVideoURL:")),1)) draft=[(Class<WUDraftVideoFactory>)factory draftWithVideoURL:editingCopy];
        else draft=[(Class<WUDraftVideoFactory>)factory draftWithVideoURL:editingCopy thumbImage:nil];
        if(![draft isKindOfClass:factory] || !current()) return nil;
        id controller=[(id<WUDraftVideoInit>)[editor alloc] initWithSightDraft:draft];
        if(![controller isKindOfClass:editor] || !current()) return nil;
        if(expectedDraft) *expectedDraft=draft;
        return controller;
    } @catch(NSException *e) { return nil; }
}
