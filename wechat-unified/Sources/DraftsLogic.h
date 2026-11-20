#import <Foundation/Foundation.h>
NSArray *WUDraftsLoad(NSURL *directory, NSString *account, NSError **error);
BOOL WUDraftsPut(NSURL *directory, NSString *account, NSString *uuid, NSString *text, NSError **error);
BOOL WUDraftsDelete(NSURL *directory, NSString *account, NSString *uuid, NSError **error);
// Exact runtime ABI gate; no guessing private object layouts or archive classes.
BOOL WUDraftsEditorAvailable(Class cls);
id WUDraftsCreateEditor(Class cls);
id WUDraftsTextView(id editor);
id WUDraftsObject(id receiver, NSString *selector);
id WUDraftsCreateImageEditor(Class cls, NSArray *images);
BOOL WUDraftsVideoEditorAvailable(Class editor, Class factory);
id WUDraftsCreateVideoEditor(Class editor, Class factory, NSURL *editingCopy, BOOL (^current)(void), id *expectedDraft);
