from pathlib import Path
import sys
r=Path(__file__).resolve().parents[1]
s=(r/'DualPane.m').read_text(); cross=(r/'CrossPane.inc').read_text(); style=(r/'CompactCells.inc').read_text()
prefix='''#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <assert.h>
#include <math.h>
#include <string.h>
@interface UIView : NSObject
@property NSArray *subviews;
@end
@implementation UIView @end
@interface UIViewController : NSObject
@property UIView *view;
@property BOOL isViewLoaded;
@end
@implementation UIViewController @end
@interface UICollectionViewDiffableDataSource : NSObject
@property NSDictionary *items;
- (id)itemIdentifierForIndexPath:(NSIndexPath *)path;
@end
@implementation UICollectionViewDiffableDataSource
- (id)itemIdentifierForIndexPath:(NSIndexPath *)path { return self.items[path]; }
@end
@interface UICollectionView : UIView
@property id delegate;
@property id dataSource;
@property NSArray *indexPathsForSelectedItems;
@end
@implementation UICollectionView @end
@interface FPItem : NSObject
@property NSURL *fileURL;
@end
@implementation FPItem @end
@interface DOCConcreteLocation : NSObject
@property id node;
@end
@implementation DOCConcreteLocation @end
@interface FakeFull : NSObject
@property id currentItemCollectionViewController;
@property id hierarchyController;
@property id lastLocation;
@property id fullDocumentManagerViewController;
@end
@implementation FakeFull @end
@interface FPBrowserPane : NSObject
@property id nativeSplit;
@end
@implementation FPBrowserPane @end
static BOOL InExperiment(id o) { return [o isKindOfClass:UIViewController.class]; }
'''
core=(r/'FileCore.inc').read_text()
abi=s[s.index('static BOOL ABI('):s.index('static void Set(')]
selection=cross[:cross.index('static NSUserDefaults')]
policy=style[style.index('static NSInteger FPNameLines'):style.index('static char CellStyleKey')]
main='''
int main(void) { @autoreleasepool {
    assert(FPNameLines(28,17)==1); assert(FPNameLines(34,17)==2);
    assert(FPCompactRowHeight(16,13)==53); assert(FPCompactRowHeight(35,29)==107);
    NSURL *root=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
    NSFileManager *fm=NSFileManager.defaultManager;
    assert([fm createDirectoryAtURL:root withIntermediateDirectories:NO attributes:nil error:nil]);
    NSURL *left=[root URLByAppendingPathComponent:@"left"], *right=[root URLByAppendingPathComponent:@"right"];
    assert([fm createDirectoryAtURL:left withIntermediateDirectories:NO attributes:nil error:nil]);
    assert([fm createDirectoryAtURL:right withIntermediateDirectories:NO attributes:nil error:nil]);
    NSURL *a=[left URLByAppendingPathComponent:@"a.txt"], *b=[left URLByAppendingPathComponent:@"b.txt"];
    assert([@"a" writeToURL:a atomically:YES encoding:NSUTF8StringEncoding error:nil]);
    assert([@"b" writeToURL:b atomically:YES encoding:NSUTF8StringEncoding error:nil]);
    FPItem *item=[FPItem new]; item.fileURL=a;
    FPItem *item2=[FPItem new]; item2.fileURL=b;
    NSIndexPath *p=[NSIndexPath indexPathWithIndex:40], *p2=[NSIndexPath indexPathWithIndex:80];
    UICollectionViewDiffableDataSource *ds=[UICollectionViewDiffableDataSource new]; ds.items=@{p:item,p2:item2};
    UIViewController *current=[UIViewController new]; current.isViewLoaded=YES;
    UICollectionView *cv=[UICollectionView new]; cv.delegate=current; cv.dataSource=ds; cv.indexPathsForSelectedItems=@[p,p2]; current.view=cv;
    FakeFull *full=[FakeFull new]; full.currentItemCollectionViewController=current; full.fullDocumentManagerViewController=full;
    FPBrowserPane *pane=[FPBrowserPane new]; pane.nativeSplit=full;
    NSError *error=nil;
    assert(([FPSelectedURLs(pane,&error) isEqual:@[a,b]])); // No visible cells exist.
    item2.fileURL=nil; assert(!FPSelectedURLs(pane,&error)); item2.fileURL=b;
    cv.indexPathsForSelectedItems=@[]; assert(!FPSelectedURLs(pane,&error)); cv.indexPathsForSelectedItems=@[p];
    DOCConcreteLocation *location=[DOCConcreteLocation new]; FPItem *dir=[FPItem new]; dir.fileURL=right; location.node=dir;
    full.hierarchyController=full; full.lastLocation=location; assert([FPFolder(pane) isEqual:right]);
    assert(!FPTransferOne(a,right,NO)); assert([fm fileExistsAtPath:a.path]);
    assert(FPTransferOne(a,right,YES)); assert([fm fileExistsAtPath:a.path]); // Conflict retains source.
    assert(!FPTransferOne(b,right,YES)); assert(![fm fileExistsAtPath:b.path]);
    assert([fm fileExistsAtPath:[[right URLByAppendingPathComponent:@"b.txt"] path]]);
    assert(FPTransferOne(a,left,YES)); assert([fm fileExistsAtPath:a.path]);
    assert(FPTransferOne(left,left,NO));
    assert(FPTransferOne([left URLByAppendingPathComponent:@"missing"],right,YES));
    NSData *lh=FPHomeBookmark(left,&error), *rh=FPHomeBookmark(right,&error); assert(lh && rh);
    NSMutableDictionary *homes=[@{@"left":lh,@"right":rh} mutableCopy];
    assert([FPResolveHome(homes[@"left"],&error).URLByResolvingSymlinksInPath.path isEqual:left.URLByResolvingSymlinksInPath.path]);
    assert([FPResolveHome(homes[@"right"],&error).URLByResolvingSymlinksInPath.path isEqual:right.URLByResolvingSymlinksInPath.path]);
    [homes removeObjectForKey:@"left"]; assert(homes[@"right"] && !homes[@"left"]);
    assert(!FPResolveHome(@"corrupt",&error)); assert(!FPResolveHome([NSData data],&error));
    assert([fm removeItemAtURL:left error:nil]);
    NSURL *invalid=FPResolveHome(lh,&error); assert(!invalid || !FPDirectory(invalid,&error));
    assert([fm removeItemAtURL:root error:nil]);
    full.fullDocumentManagerViewController=nil; full.hierarchyController=nil; cv.delegate=nil;
    puts("PASS production core: bounded row policy, offscreen selection/source/target mapping, missing URL rejects whole selection, copy/move, conflict retains source, self/descendant rejection, independent bookmarks, corrupt/deleted home");
} return 0; }
'''
Path(sys.argv[1]).write_text(prefix+abi+core+selection+policy+main)
