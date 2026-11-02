#import <Foundation/Foundation.h>
BOOL WUEmoticonSourceReady(id source, id manager);
BOOL WUEmoticonDataAvailable(id manager);
// Sole AddEmoticonMsg submission implementation, shared by repeat and library.
NSString *WUSubmitEmoticonCopy(id source, id manager, NSString *account, NSString *target, BOOL (^current)(void));
// Builds only through the evidenced CEmoticonMgr class factory; no cache-writing fallback.
NSString *WUSubmitEmoticonData(NSData *original, id manager, NSString *account, NSString *target, BOOL (^current)(void));
// Prepares only the evidenced GIF wrapper; never starts an upload without a verified data/delegate contract.
NSString *WUPrepareOfficialGIF(NSData *original, NSString *expectedMD5, BOOL (^current)(void));
