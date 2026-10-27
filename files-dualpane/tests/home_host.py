from pathlib import Path
import sys
r=Path(__file__).resolve().parents[1]
s=(r/'DualPane.m').read_text(); n=(r/'HomeNavigation.inc').read_text(); x=(r/'CrossPane.inc').read_text()
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
@property BOOL isShowingCollapsedSidebarViewController;
@end
@implementation Full @end
@interface FPBrowserPane : NSObject
@property Full *nativeSplit;
@end
@implementation FPBrowserPane @end
static BOOL InExperiment(id v) { return [v isKindOfClass:UIViewController.class]; }
static UIViewController *FindSplit(UIViewController *v,Class cls) {
 if(cls && [v isKindOfClass:cls]) return v;
 for(UIViewController *c in v.childViewControllers) { id f=FindSplit(c,cls); if(f) return f; }
 return nil;
}
'''
abi=s[s.index('static BOOL ABI('):s.index('static void Set(')]
base=x[:x.index('#include "HomePolicy.inc"')]
nav=n[:n.index('static BOOL FPShowLocation(')]
main=r'''
int main(void) { @autoreleasepool {
 NSData *bookmark=[@"legacy" dataUsingEncoding:NSUTF8StringEncoding];
 NSDictionary *legacy=FPHomeRecord(bookmark); assert([legacy[@"mode"] isEqual:@"custom"] && legacy[@"bookmark"]==bookmark);
 assert([FPHomeRecord(nil)[@"mode"] isEqual:@"defaultDownloads"]);
 assert(!FPHomeRecord(@"bad") && !FPHomeRecord(@{@"schema":@2,@"mode":@"browse"}));
 assert(!FPHomeRecord(@{@"schema":@1,@"mode":@"custom",@"bookmark":@"corrupt"}));
 NSMutableDictionary *homes=[@{@"left":legacy,@"right":@{@"schema":@1,@"mode":@"browse"}} mutableCopy];
 id right=homes[@"right"]; homes[@"left"]=FPHomeRecord(nil); assert(homes[@"right"]==right);
 homes[@"left"]=legacy;
 if(FPHomeCanCommit(NO,1,1)) homes[@"left"]=FPHomeRecord(nil); assert(homes[@"left"]==legacy);
 assert(!FPHomeCanCommit(YES,1,2)); assert(FPHomeCanCommit(YES,2,2));
 assert(FPHomeLocationUnchanged(nil,nil)); assert(!FPHomeLocationUnchanged(@"old",@"new")); assert(FPHomeLocationUnchanged(@"same",@"same"));
 assert(FPHomeMayContinue(1,1,YES,NO,19)); assert(!FPHomeMayContinue(1,1,YES,NO,20));
 assert(!FPHomeMayContinue(1,2,YES,NO,0)); assert(!FPHomeMayContinue(1,1,YES,YES,0)); assert(!FPHomeMayContinue(1,1,NO,NO,0));
 assert(!FPHomeIsBrowse(NO,NO)); assert(FPHomeIsBrowse(YES,NO)); assert(FPHomeIsBrowse(NO,YES));
 FPBrowserPane *pane=[FPBrowserPane new]; Full *full=[Full new]; pane.nativeSplit=full; full.fullDocumentManagerViewController=full;
 UINavigationController *nav=[UINavigationController new]; full.internalNavigationController=nav;
 UIViewController *container=[UIViewController new]; nav.visibleViewController=container;
 DOCConcreteLocation *location=[DOCConcreteLocation new]; FPItem *node=[FPItem new]; node.fileURL=[NSURL fileURLWithPath:@"/real-provider-folder"]; location.node=node;
 objc_setAssociatedObject(container,&FPContainerLocationKey,location,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
 full.lastLocation=[DOCConcreteLocation browseStartingPointsLocation];
 assert(FPCurrentLocation(pane)==location && [FPFolder(pane) isEqual:node.fileURL]);
 full.isShowingCollapsedSidebarViewController=YES; full.lastLocation=location;
 assert(FPBrowseVisible(pane) && !FPFolder(pane)); // Stale lastLocation must never turn Browse into a folder.
 full.isShowingCollapsedSidebarViewController=NO; nav.visibleViewController=[UIViewController new];
 assert(!FPCurrentLocation(pane) && !FPFolder(pane)); // Unknown != Browse or previous folder.
 nav.visibleViewController=container; node.fileURL=nil;
 assert(!FPBrowseVisible(pane) && FPCurrentLocation(pane)==location && !FPFolder(pane)); // Provider root/no URL isn't Browse.
 full.fullDocumentManagerViewController=nil;
 puts("PASS production home policy/navigation: explicit Browse vs folder vs unavailable, visible container mapping ignores stale history, legacy migration, invalid schema, independent sides, failure preservation, bounded wait and touch/generation cancellation");
} return 0; }
'''
Path(sys.argv[1]).write_text(prefix+abi+base+(r/'HomePolicy.inc').read_text()+nav+main)
