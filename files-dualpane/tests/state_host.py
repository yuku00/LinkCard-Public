from pathlib import Path
import sys
s=(Path(__file__).resolve().parents[1]/'DualPane.m').read_text()
helpers=s[s.index('static BOOL ABI'):s.index('static void Set')]
state=s[s.index('static NSMutableDictionary<NSString *, id> *paneStates'):s.index('@interface FPBrowserPane')]
prefix='''#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <string.h>
#include <assert.h>
static int reads,updates,writes;
@interface DOCUserInterfaceState : NSObject
@property(nonatomic,copy) NSData *mostRecentlyVisitedLocation;
@property(nonatomic,copy) NSData *mostRecentEffectiveRootLocation;
@property(nonatomic,copy) NSNumber *selectedTab;
@end
@implementation DOCUserInterfaceState @end
static DOCUserInterfaceState *nativeState;
@interface DOCUserInterfaceStateStore : NSObject
+ (id)sharedStore;
- (id)interfaceStateForConfiguration:(id)c;
- (void)updateInterfaceState:(id)s forConfiguration:(id)c;
- (void)_writeUserInterfaceStateToDefaultsForConfiguration:(id)c;
- (void)_writeMostRecentUserInterfaceStateToDefaultsForConfiguration:(id)c;
@end
@implementation DOCUserInterfaceStateStore
+ (id)sharedStore { static id store; if(!store) store=[self new]; return store; }
- (id)interfaceStateForConfiguration:(id)c { reads++; return nativeState; }
- (void)updateInterfaceState:(id)s forConfiguration:(id)c { updates++; }
- (void)_writeUserInterfaceStateToDefaultsForConfiguration:(id)c { writes++; }
- (void)_writeMostRecentUserInterfaceStateToDefaultsForConfiguration:(id)c { writes++; }
@end
@interface Config : NSObject
@property(nonatomic,copy) NSString *stateIdentifier;
@end
@implementation Config @end
'''
main='''
int main(void) { @autoreleasepool {
    assert(InstallStateIsolation()); assert(InstallStateIsolation());
    DOCUserInterfaceStateStore *store=[DOCUserInterfaceStateStore new];
    Config *original=[Config new], *left=[Config new], *right=[Config new];
    original.stateIdentifier=@"Files.original";
    left.stateIdentifier=@"dev.filesdualpane.session.left";
    right.stateIdentifier=@"dev.filesdualpane.session.right";
    nativeState=[DOCUserInterfaceState new];
    nativeState.mostRecentlyVisitedLocation=[@"native-folder" dataUsingEncoding:NSUTF8StringEncoding];
    nativeState.mostRecentEffectiveRootLocation=[@"provider-root" dataUsingEncoding:NSUTF8StringEncoding];
    nativeState.selectedTab=@1;
    paneStates[left.stateIdentifier]=[DOCUserInterfaceState new];
    paneStates[right.stateIdentifier]=[DOCUserInterfaceState new];
    id l=[store interfaceStateForConfiguration:left], r=[store interfaceStateForConfiguration:right];
    assert(l!=r && l!=nativeState && r!=nativeState && reads==0);
    assert(![l mostRecentlyVisitedLocation]);
    assert(![r mostRecentEffectiveRootLocation]);
    assert(![l selectedTab]);
    [l setMostRecentlyVisitedLocation:[@"left navigated" dataUsingEncoding:NSUTF8StringEncoding]];
    assert(![[l mostRecentlyVisitedLocation] isEqual:[r mostRecentlyVisitedLocation]]);
    assert(![r mostRecentlyVisitedLocation]);
    id replacement=[DOCUserInterfaceState new];
    [store updateInterfaceState:replacement forConfiguration:left];
    assert([store interfaceStateForConfiguration:left]==replacement);
    assert([store interfaceStateForConfiguration:right]==r && updates==0);
    [store _writeUserInterfaceStateToDefaultsForConfiguration:left];
    [store _writeMostRecentUserInterfaceStateToDefaultsForConfiguration:right];
    assert(writes==0);
    assert([store interfaceStateForConfiguration:original]==nativeState);
    [store updateInterfaceState:l forConfiguration:original];
    [store _writeUserInterfaceStateToDefaultsForConfiguration:original];
    [store _writeMostRecentUserInterfaceStateToDefaultsForConfiguration:original];
    assert(reads==1 && updates==1 && writes==2);
    [paneStates removeAllObjects];
    [store updateInterfaceState:l forConfiguration:left];
    assert([store interfaceStateForConfiguration:left]!=nil && paneStates.count==0);
    assert(reads==1 && updates==1 && writes==2);
    Config *reopened=[Config new]; reopened.stateIdentifier=@"dev.filesdualpane.session.new-unique-id";
    paneStates[reopened.stateIdentifier]=[DOCUserInterfaceState new];
    id fresh=[store interfaceStateForConfiguration:reopened];
    [store updateInterfaceState:l forConfiguration:left];
    assert([store interfaceStateForConfiguration:reopened]==fresh && paneStates.count==1);
    puts("PASS actual production state wrappers: empty independent states without reading native history, separate panes, original passthrough, no owned persistence, late callback does not recreate retained state");
} return 0; }
'''
Path(sys.argv[1]).write_text(prefix+helpers+state+main)
