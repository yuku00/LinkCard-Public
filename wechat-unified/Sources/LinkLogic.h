#import <Foundation/Foundation.h>
// Inputs are frozen selected-message content, never WebView/HTML/page responses.
NSURL *WULinkSafeURL(NSString *text);
NSArray<NSDictionary *> *WULinkCandidates(NSArray<NSDictionary *> *messages);
// Risk wrappers: explicit, one-level, allowlisted query extraction; no network resolution.
NSDictionary *WULinkDestination(NSURL *url);
