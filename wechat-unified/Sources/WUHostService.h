#import <Foundation/Foundation.h>

// Resolves a fresh provider on every call; never retains a context or service.
id WUHostService(NSString *name);
