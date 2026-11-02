#import <UIKit/UIKit.h>
// Manual chat-toolbar entry only. Opening is not an add/upload receipt.
void WUOpenSelectedImageEditor(UIViewController *owner);
BOOL WUImageEntryOwnsNavigation(UIViewController *owner);
// Article callers have already shown source + preview and obtained user confirmation.
// The guard is main-thread only; editing=YES after our editor is allocated.
BOOL WUImageEntryValidateData(NSData *data);
BOOL WUOpenConfirmedImageDataEditor(UIViewController *owner, NSData *data, BOOL (^current)(BOOL editing));
void WUCancelImageDataEditor(UIViewController *owner);
void WUCancelImageEntries(void);
