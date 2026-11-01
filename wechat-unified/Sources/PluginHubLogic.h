#import <Foundation/Foundation.h>
BOOL WUHubValidOptions(id value);
NSDictionary *WUHubDefaultOptions(void);
BOOL WUHubValidControllerName(id value);
NSArray<NSDictionary *> *WUHubRows(NSArray<NSDictionary *> *registry, NSDictionary *options, BOOL includeHidden);
NSDictionary *WUHubSetEntry(NSDictionary *options, NSString *identifier, NSString *name, NSString *group, BOOL hidden);
NSDictionary *WUHubMove(NSDictionary *options, NSArray<NSDictionary *> *registry, NSString *identifier, NSInteger delta);
