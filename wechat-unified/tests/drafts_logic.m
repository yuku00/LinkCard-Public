#import <Foundation/Foundation.h>
#import "DraftsLogic.h"
#include <assert.h>
@interface Editor : NSObject
@property(nonatomic,copy) NSString *body;
- (instancetype)initWithTextType;
- (id)textView;
@end
@implementation Editor
- (instancetype)initWithTextType { if((self=[super init])) self.body=@"host"; return self; }
- (id)textView { return self.body; }
@end
@interface BadEditor : NSObject
- (int)initWithTextType __attribute__((objc_method_family(none)));
- (id)textView;
@end
@implementation BadEditor
- (int)initWithTextType { abort(); }
- (id)textView { abort(); }
@end
@interface ThrowEditor : Editor
@end
@implementation ThrowEditor
- (instancetype)initWithTextType { @throw [NSException exceptionWithName:@"test" reason:nil userInfo:nil]; }
@end
int main(void) { @autoreleasepool {
    NSFileManager *fm=NSFileManager.defaultManager; NSError *e=nil;
    NSURL *root=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
    NSString *one=NSUUID.UUID.UUIDString,*two=NSUUID.UUID.UUIDString;
    assert(WUDraftsLoad(root,@"a",&e).count==0);
    assert(WUDraftsPut(root,@"a",one,@"原文",&e));
    assert(WUDraftsPut(root,@"a",two,@"第二条",&e));
    assert(WUDraftsPut(root,@"a",one,@"更新同一UUID",&e));
    NSArray *rows=WUDraftsLoad(root,@"a",&e); assert(rows.count==2);
    assert([rows[1][@"parts"][0][@"text"] isEqual:@"更新同一UUID"]);
    assert(WUDraftsLoad(root,@"b",&e).count==0);
    assert(WUDraftsPut(root,@"b",one,@"账号B",&e));
    assert(WUDraftsDelete(root,@"a",two,&e)); assert(WUDraftsLoad(root,@"a",&e).count==1);
    assert([WUDraftsLoad(root,@"b",&e)[0][@"parts"][0][@"text"] isEqual:@"账号B"]);
    assert(!WUDraftsPut(root,@"a",one,@"",&e)); assert(!WUDraftsPut(root,@"a",@"index-0",@"bad",&e));
    // Production storage must leave same-path/shared/in-use media untouched, even on deletion or bad index.
    NSURL *media=[root URLByAppendingPathComponent:@"shared-video.mov"]; NSData *asset=[@"synthetic-owned-asset" dataUsingEncoding:NSUTF8StringEncoding]; assert([asset writeToURL:media atomically:YES]);
    assert(WUDraftsPut(root,@"a",one,@"再次更新",&e)); assert([[NSData dataWithContentsOfURL:media] isEqual:asset]);
    assert(WUDraftsDelete(root,@"a",one,&e)); assert([[NSData dataWithContentsOfURL:media] isEqual:asset]);
    NSURL *index=[root URLByAppendingPathComponent:@"61.plist"]; NSData *bad=[@"broken archive" dataUsingEncoding:NSUTF8StringEncoding]; assert([bad writeToURL:index atomically:YES]);
    assert(!WUDraftsLoad(root,@"a",&e)); assert(!WUDraftsPut(root,@"a",one,@"不得覆盖",&e)); assert(!WUDraftsDelete(root,@"a",one,&e));
    assert([[NSData dataWithContentsOfURL:index] isEqual:bad]); assert([[NSData dataWithContentsOfURL:media] isEqual:asset]);
    // Real filesystem failure: the directory path is occupied by a file.
    assert(!WUDraftsPut(media,@"a",one,@"write fails",&e)); assert([[NSData dataWithContentsOfURL:media] isEqual:asset]);
    assert(WUDraftsEditorAvailable(Editor.class)); assert(!WUDraftsEditorAvailable(BadEditor.class));
    assert(!WUDraftsCreateEditor(BadEditor.class)); assert(!WUDraftsCreateEditor(ThrowEditor.class));
    id editor=WUDraftsCreateEditor(Editor.class); assert([WUDraftsTextView(editor) isEqual:@"host"]);
    assert(!WUDraftsTextView([NSObject new]));
    assert([[NSData dataWithContentsOfURL:index] isEqual:bad]);
    assert([fm removeItemAtURL:root error:&e]);
    puts("Drafts production storage and host ABI tests passed (text only; no media restore claim)");
} return 0; }
