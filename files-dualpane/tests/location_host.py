from pathlib import Path
import sys
r=Path(__file__).resolve().parents[1]
s=(r/'DualPane.m').read_text(); n=(r/'NativeLocation.inc').read_text(); x=(r/'CrossPane.inc').read_text()
prefix=r'''#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <assert.h>
#include <string.h>
@interface UIViewController : NSObject
@property NSArray *childViewControllers;
@end
@implementation UIViewController @end
@interface UINavigationController : UIViewController
@property UIViewController *visibleViewController;
@end
@implementation UINavigationController @end
@interface FPItem : NSObject
@property NSURL *fileURL;
@end
@implementation FPItem @end
@interface DOCConcreteLocation : NSObject
@property id node;
+ (id)browseStartingPointsLocation;
@end
@implementation DOCConcreteLocation
+ (id)browseStartingPointsLocation { static id root; if(!root) root=[self new]; return root; }
@end
@interface Full : UIViewController
@property id internalNavigationController;
@property id fullDocumentManagerViewController;
@property id lastLocation;
@property id configuration;
@property BOOL isShowingCollapsedSidebarViewController;
@end
@implementation Full @end
@interface LocationConfig : NSObject
@property NSString *stateIdentifier;
@end
@implementation LocationConfig @end
@interface DOCFullDocumentManagerViewController : Full
- (id)provideContainerControllerAt:(id)location from:(id)source isUserInteraction:(BOOL)user isBrowsingTrash:(BOOL)trash;
@end
@implementation DOCFullDocumentManagerViewController
- (id)provideContainerControllerAt:(id)location from:(id)source isUserInteraction:(BOOL)user isBrowsingTrash:(BOOL)trash { return [UIViewController new]; }
@end
@interface FPBrowserPane : NSObject
@property Full *nativeSplit;
@end
@implementation FPBrowserPane @end
static BOOL hasParent;
static BOOL InExperiment(id v) { return hasParent && [v isKindOfClass:UIViewController.class]; }
static UIViewController *FindSplit(UIViewController *v,Class cls) {
 if(cls && [v isKindOfClass:cls]) return v;
 for(UIViewController *c in v.childViewControllers) { id f=FindSplit(c,cls); if(f) return f; }
 return nil;
}
'''
abi=s[s.index('static BOOL ABI('):s.index('static void Set(')]
base=x[:x.index('#include "NativeLocation.inc"')]
nav=s[s.index('static NSString *OwnState('):s.index('static BOOL InstallStateIsolation(')]+n
main=r'''
int main(void) { @autoreleasepool {
 FPBrowserPane *pane=[FPBrowserPane new]; Full *full=[DOCFullDocumentManagerViewController new]; pane.nativeSplit=full; full.fullDocumentManagerViewController=full;
 UINavigationController *nav=[UINavigationController new]; full.internalNavigationController=nav;
 UIViewController *container=[UIViewController new]; nav.visibleViewController=container;
 DOCConcreteLocation *location=[DOCConcreteLocation new]; FPItem *node=[FPItem new]; node.fileURL=[NSURL fileURLWithPath:@"/real-provider-folder"]; location.node=node;
 InstallLocationTracking();
 LocationConfig *config=[LocationConfig new]; config.stateIdentifier=@"dev.filesdualpane.session.first-location"; full.configuration=config;
 assert(!InExperiment(full)); // Factory callback before parent containment exists.
 container=[(DOCFullDocumentManagerViewController *)full provideContainerControllerAt:location from:nil isUserInteraction:NO isBrowsingTrash:NO];
 assert(objc_getAssociatedObject(container,&FPContainerLocationKey)==location);
 config.stateIdentifier=@"Files.original";
 id originalContainer=[(DOCFullDocumentManagerViewController *)full provideContainerControllerAt:location from:nil isUserInteraction:NO isBrowsingTrash:NO];
 assert(!objc_getAssociatedObject(originalContainer,&FPContainerLocationKey));
 nav.visibleViewController=container; hasParent=YES;
 full.lastLocation=[DOCConcreteLocation browseStartingPointsLocation];
 assert(FPCurrentLocation(pane)==location && [FPFolder(pane) isEqual:node.fileURL]);
 full.isShowingCollapsedSidebarViewController=YES; full.lastLocation=location;
 assert(FPBrowseVisible(pane) && !FPFolder(pane)); // Stale lastLocation must never turn Browse into a folder.
 full.isShowingCollapsedSidebarViewController=NO; nav.visibleViewController=[UIViewController new];
 assert(!FPCurrentLocation(pane) && !FPFolder(pane)); // Unknown != Browse or previous folder.
 nav.visibleViewController=container; node.fileURL=nil;
 assert(!FPBrowseVisible(pane) && FPCurrentLocation(pane)==location && !FPFolder(pane)); // Provider root/no URL isn't Browse.
 full.fullDocumentManagerViewController=nil;
 puts("PASS production native location: explicit Browse vs folder vs unavailable, visible container mapping ignores stale history; factory hook captures first location without parent tree; original Files untouched");
} return 0; }
'''
Path(sys.argv[1]).write_text(prefix+abi+base+nav+main)
