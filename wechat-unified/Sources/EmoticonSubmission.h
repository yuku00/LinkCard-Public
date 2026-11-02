#import <Foundation/Foundation.h>
BOOL WUEmoticonSourceReady(id source, id manager);
BOOL WUEmoticonDataAvailable(id manager);
// Sole AddEmoticonMsg submission implementation, shared by repeat and library.
NSString *WUSubmitEmoticonCopy(id source, id manager, NSString *account, NSString *target, BOOL (^current)(void));
// Builds only through the evidenced CEmoticonMgr class factory; no cache-writing fallback.
NSString *WUSubmitEmoticonData(NSData *original, id manager, NSString *account, NSString *target, BOOL (^current)(void));
