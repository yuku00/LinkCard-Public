#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#define RO_VERSION @"0.5.2"
#define RO_MODULES @"production modules: readonly/Entry.m, readonly/Session.m, readonly/Graph.m, readonly/Metadata.m, readonly/Observer.m; query mutation hooks:none; rule engine absent"

NSString *ROType(id object);
BOOL ROIsKind(id object, Class cls);
NSDictionary *ROMetadata(NSArray<NSString *> *names);
NSString *ROPageRole(NSArray<NSString *> *visibleControllerTypes, BOOL hasList);
BOOL ROInstallObserver(Class applicationClass, void (^observer)(id owner,id event));

@interface ROSession : NSObject
@property(nonatomic,readonly) BOOL active;
@property(nonatomic,readonly) BOOL paused;
@property(nonatomic,readonly) NSUInteger generation;
@property(nonatomic,readonly) NSUInteger stageCount;
@property(nonatomic,readonly) NSString *pageRole;
- (void)start;
- (void)pause;
- (void)resume;
- (void)stop;
- (void)clear;
- (NSString *)identifier:(id)object;
- (void)record:(NSDictionary *)graph label:(NSString *)label automatic:(BOOL)automatic;
- (void)eventOwner:(id)owner argument:(id)argument;
- (NSDictionary *)document:(NSString *)observerStatus;
@end
