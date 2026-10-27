#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#define MP_VERSION @"0.1.0"
BOOL MPAllowed(NSString *bundle, NSString *build);
BOOL MPRelevant(NSString *name);
NSArray<NSString *> *MPCandidates(void);
NSDictionary *MPMetadata(NSArray<NSString *> *observed, NSArray<NSString *> *imageAnchors);
