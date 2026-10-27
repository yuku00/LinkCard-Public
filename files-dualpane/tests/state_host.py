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
@interface DOCUserInterfaceState : NSObject @end
@implementation DOCUserInterfaceState @end
@interface DOCUserInterfaceStateStore : NSObject
- (id)interfaceStateForConfiguration:(id)c;
- (void)updateInterfaceState:(id)s forConfiguration:(id)c;
- (void)_writeUserInterfaceStateToDefaultsForConfiguration:(id)c;
- (void)_writeMostRecentUserInterfaceStateToDefaultsForConfiguration:(id)c;
@end
@implementation DOCUserInterfaceStateStore
- (id)interfaceStateForConfiguration:(id)c { reads++; return @"original"; }
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
    paneStates[left.stateIdentifier]=[DOCUserInterfaceState new];
    paneStates[right.stateIdentifier]=[DOCUserInterfaceState new];
    id l=[store interfaceStateForConfiguration:left], r=[store interfaceStateForConfiguration:right];
    assert(l!=r && reads==0);
    id replacement=[DOCUserInterfaceState new];
    [store updateInterfaceState:replacement forConfiguration:left];
    assert([store interfaceStateForConfiguration:left]==replacement);
    assert([store interfaceStateForConfiguration:right]==r && updates==0);
    [store _writeUserInterfaceStateToDefaultsForConfiguration:left];
    [store _writeMostRecentUserInterfaceStateToDefaultsForConfiguration:right];
    assert(writes==0);
    assert([[store interfaceStateForConfiguration:original] isEqual:@"original"]);
    [store updateInterfaceState:l forConfiguration:original];
    [store _writeUserInterfaceStateToDefaultsForConfiguration:original];
    [store _writeMostRecentUserInterfaceStateToDefaultsForConfiguration:original];
    assert(reads==1 && updates==1 && writes==2);
    [paneStates removeAllObjects];
    [store updateInterfaceState:l forConfiguration:left];
    assert([store interfaceStateForConfiguration:left]!=nil && paneStates.count==0);
    assert(reads==1 && updates==1 && writes==2);
    puts("PASS actual production state wrappers: separate panes, original passthrough, no owned persistence, late callback does not recreate retained state");
} return 0; }
'''
Path(sys.argv[1]).write_text(prefix+helpers+state+main)
