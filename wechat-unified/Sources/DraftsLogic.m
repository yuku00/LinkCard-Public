#import "DraftsLogic.h"
#import "RepositoryLogic.h"
#import <objc/runtime.h>
#include <string.h>
static BOOL Fail(NSError **e, NSString *message) { if(e) *e=[NSError errorWithDomain:@"WUDrafts" code:1 userInfo:@{NSLocalizedDescriptionKey:message}]; return NO; }
NSArray *WUDraftsLoad(NSURL *d, NSString *a, NSError **e) {
    NSArray *rows=WURepositoryLoad(d,a,e); if(!rows) return nil;
    for(NSDictionary *row in rows) {
        NSArray *parts=row[@"parts"];
        if(parts.count!=1 || ![parts[0][@"kind"] isEqual:@"text"]) { Fail(e,@"草稿索引类型错误，保留原文件"); return nil; }
    }
    return rows;
}
BOOL WUDraftsPut(NSURL *d, NSString *a, NSString *uuid, NSString *text, NSError **e) {
    @synchronized(NSFileManager.defaultManager) {
        if(![[NSUUID alloc] initWithUUIDString:uuid] || ![text isKindOfClass:NSString.class] || !text.length || text.length>10000) return Fail(e,@"文字需为1–10000字，标识必须为UUID");
        NSArray *old=WUDraftsLoad(d,a,e); if(!old) return NO;
        NSMutableArray *rows=[old mutableCopy];
        NSDictionary *row=@{@"id":uuid,@"name":[text substringToIndex:MIN(text.length,80)],@"parts":@[@{@"kind":@"text",@"text":text}]};
        NSUInteger index=[rows indexOfObjectPassingTest:^BOOL(NSDictionary *x, NSUInteger i, BOOL *stop){ return [x[@"id"] isEqual:uuid]; }];
        if(index==NSNotFound) [rows insertObject:row atIndex:0]; else rows[index]=row;
        return WURepositorySave(d,a,rows,e);
    }
}
BOOL WUDraftsDelete(NSURL *d, NSString *a, NSString *uuid, NSError **e) {
    @synchronized(NSFileManager.defaultManager) {
        NSArray *old=WUDraftsLoad(d,a,e); if(!old) return NO;
        NSMutableArray *rows=[old mutableCopy];
        NSIndexSet *matches=[rows indexesOfObjectsPassingTest:^BOOL(NSDictionary *x, NSUInteger i, BOOL *stop){ return [x[@"id"] isEqual:uuid]; }];
        if(!matches.count) return Fail(e,@"该草稿已不存在");
        [rows removeObjectsAtIndexes:matches];
        // Text only. Never unlink media, sweep directories or touch host archives.
        return WURepositorySave(d,a,rows,e);
    }
}
static BOOL ObjectGetter(Class c, SEL s) {
    Method m=class_getInstanceMethod(c,s); if(!m || method_getNumberOfArguments(m)!=2) return NO;
    char *r=method_copyReturnType(m); BOOL ok=!strcmp(r,"@"); free(r); return ok;
}
BOOL WUDraftsEditorAvailable(Class cls) { return cls && ObjectGetter(cls,NSSelectorFromString(@"initWithTextType")) && ObjectGetter(cls,NSSelectorFromString(@"textView")); }
@protocol WUDraftHostInit
- (instancetype)initWithTextType;
@end
id WUDraftsCreateEditor(Class cls) {
    if(!WUDraftsEditorAvailable(cls)) return nil;
    @try { return [(id<WUDraftHostInit>)[cls alloc] initWithTextType]; } @catch(NSException *e) { return nil; }
}
id WUDraftsObject(id editor, NSString *selector) {
    if(!editor || !ObjectGetter(object_getClass(editor),NSSelectorFromString(selector))) return nil;
    @try { NSInvocation *v=[NSInvocation invocationWithMethodSignature:[editor methodSignatureForSelector:NSSelectorFromString(selector)]]; v.target=editor; v.selector=NSSelectorFromString(selector); [v invoke]; __unsafe_unretained id result=nil; [v getReturnValue:&result]; return result; } @catch(NSException *e) { return nil; }
}
id WUDraftsTextView(id editor) { return WUDraftsObject(editor,@"textView"); }
@protocol WUDraftImageInit
- (instancetype)initWithImages:(NSArray *)images contacts:(id)contacts;
@end
id WUDraftsCreateImageEditor(Class cls, NSArray *images) {
    if(!cls || !images.count) return nil;
    Method m=class_getInstanceMethod(cls,NSSelectorFromString(@"initWithImages:contacts:"));
    if(!m || method_getNumberOfArguments(m)!=4) return nil;
    char *r=method_copyReturnType(m); BOOL ok=!strcmp(r,"@"); free(r);
    for(unsigned i=2;i<4;i++) { char *t=method_copyArgumentType(m,i); ok=ok && !strcmp(t,"@"); free(t); }
    if(!ok) return nil;
    @try { return [(id<WUDraftImageInit>)[cls alloc] initWithImages:images contacts:nil]; } @catch(NSException *e) { return nil; }
}
