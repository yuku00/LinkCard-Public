from pathlib import Path
import sys
r=Path(__file__).resolve().parents[1]
production=(r/'CompactMargins.inc').read_text()+(r/'CompactSelection.inc').read_text()+(r/'CompactDisclosure.inc').read_text()
sidebar=(r/'CompactSidebar.inc').read_text()
production+=sidebar[sidebar.index('static BOOL FPSidebarScope'):sidebar.index('static UIViewController *FPSidebarOwner')]
production+='static char FPSidebarTitleKey;\n'+sidebar[sidebar.index('static void FPSidebarTitle('):sidebar.index('static void FPSidebarHookCell(')]
prefix=r'''#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#include <assert.h>
#include <math.h>
typedef struct { CGFloat top, leading, bottom, trailing; } NSDirectionalEdgeInsets;
static NSDirectionalEdgeInsets NSDirectionalEdgeInsetsMake(CGFloat t, CGFloat l, CGFloat b, CGFloat r) { return (NSDirectionalEdgeInsets){t,l,b,r}; }
static BOOL NSDirectionalEdgeInsetsEqualToDirectionalEdgeInsets(NSDirectionalEdgeInsets a, NSDirectionalEdgeInsets b) { return a.top==b.top && a.leading==b.leading && a.bottom==b.bottom && a.trailing==b.trailing; }
@interface NSValue (Margins)
+ (instancetype)valueWithDirectionalEdgeInsets:(NSDirectionalEdgeInsets)value;
- (NSDirectionalEdgeInsets)directionalEdgeInsetsValue;
@end
@implementation NSValue (Margins)
+ (instancetype)valueWithDirectionalEdgeInsets:(NSDirectionalEdgeInsets)v { return [self valueWithBytes:&v objCType:@encode(NSDirectionalEdgeInsets)]; }
- (NSDirectionalEdgeInsets)directionalEdgeInsetsValue { NSDirectionalEdgeInsets v; [self getValue:&v size:sizeof(v)]; return v; }
@end
static const NSInteger UINavigationItemLargeTitleDisplayModeNever=2;
@interface UINavigationItem : NSObject
@property NSInteger largeTitleDisplayMode;
@end
@implementation UINavigationItem @end
@interface UIViewController : NSObject
@property UINavigationItem *navigationItem;
@end
@implementation UIViewController @end
typedef unsigned long long UIAccessibilityTraits;
static const UIAccessibilityTraits UIAccessibilityTraitSelected=4;
static const NSUInteger UIViewAutoresizingFlexibleWidth=2, UIViewAutoresizingFlexibleHeight=16;
static const NSInteger UIUserInterfaceStyleDark=2;
@interface UIColor : NSObject
@property CGFloat alpha;
- (instancetype)colorWithAlphaComponent:(CGFloat)alpha;
@end
@implementation UIColor
- (instancetype)colorWithAlphaComponent:(CGFloat)alpha { UIColor *c=[UIColor new]; c.alpha=alpha; return c; }
@end
@interface UITraitCollection : NSObject
@property NSInteger userInterfaceStyle;
@end
@implementation UITraitCollection @end
@interface UIView : NSObject
@property CGRect frame;
@property NSDirectionalEdgeInsets directionalLayoutMargins;
@property BOOL preservesSuperviewLayoutMargins;
@property CGRect bounds;
@property BOOL userInteractionEnabled;
@property BOOL isAccessibilityElement;
@property BOOL hidden;
@property NSUInteger autoresizingMask;
@property UIColor *backgroundColor;
@property UIColor *tintColor;
@property UITraitCollection *traitCollection;
@property UIAccessibilityTraits accessibilityTraits;
@property NSMutableArray *children;
@property(weak) UIView *parent;
- (void)removeFromSuperview;
- (void)insertSubview:(UIView *)view belowSubview:(UIView *)sibling;
@end
@implementation UIView
- (instancetype)init { if((self=[super init])) { _children=[NSMutableArray new]; _tintColor=[UIColor new]; _traitCollection=[UITraitCollection new]; } return self; }
- (void)removeFromSuperview { [self.parent.children removeObject:self]; self.parent=nil; }
- (void)insertSubview:(UIView *)view belowSubview:(UIView *)sibling { [self.children addObject:view]; view.parent=self; }
@end
@interface UICellAccessory : NSObject @end
@implementation UICellAccessory @end
@interface UICellAccessoryDisclosureIndicator : UICellAccessory @end
@implementation UICellAccessoryDisclosureIndicator @end
@interface UICellAccessoryMultiselect : UICellAccessory @end
@implementation UICellAccessoryMultiselect @end
@interface UICollectionViewCell : UIView
@property(getter=isSelected) BOOL selected;
@property UIView *contentView;
@end
@implementation UICollectionViewCell @end
@interface UICollectionViewListCell : UICollectionViewCell
@property NSArray<UICellAccessory *> *accessories;
@end
@implementation UICollectionViewListCell @end
'''
main=r'''
int main(void) { @autoreleasepool {
    UICollectionViewListCell *cell=[UICollectionViewListCell new]; cell.contentView=[UIView new];
    cell.directionalLayoutMargins=NSDirectionalEdgeInsetsMake(0,20,0,20);
    cell.contentView.directionalLayoutMargins=NSDirectionalEdgeInsetsMake(0,16,0,16);
    cell.contentView.preservesSuperviewLayoutMargins=YES;
    FPContentMargins(cell,YES); FPContentMargins(cell,YES);
    assert(cell.directionalLayoutMargins.trailing==0 && cell.contentView.directionalLayoutMargins.trailing==0);
    assert(!cell.contentView.preservesSuperviewLayoutMargins);
    FPContentMargins(cell,NO);
    assert(cell.directionalLayoutMargins.trailing==20 && cell.contentView.directionalLayoutMargins.trailing==16 && cell.contentView.preservesSuperviewLayoutMargins);
    assert(!objc_getAssociatedObject(cell,&FPContentMarginsKey));
    UICellAccessory *arrow=[UICellAccessoryDisclosureIndicator new], *progress=[UICellAccessory new];
    UICellAccessory *circle=[UICellAccessoryMultiselect new];
    NSArray *native=@[circle,arrow,progress]; cell.accessories=native;
    cell.accessibilityTraits=128; cell.bounds=CGRectMake(0,0,190,50);
    FPSelectionVisual(cell,YES);
    assert(([cell.accessories isEqual:@[progress]]));
    UIView *highlight=objc_getAssociatedObject(cell,&FPSelectionViewKey);
    assert(highlight.hidden && !cell.isSelected && !highlight.userInteractionEnabled);
    assert(!highlight.isAccessibilityElement && CGRectEqualToRect(highlight.frame,cell.bounds));
    assert(cell.accessibilityTraits==128);
    cell.selected=YES; FPSelectionVisual(cell,YES);
    assert(!highlight.hidden && cell.isSelected && cell.accessibilityTraits==132);
    assert(highlight.backgroundColor.alpha==0.16);
    cell.traitCollection.userInterfaceStyle=UIUserInterfaceStyleDark; FPSelectionVisual(cell,YES);
    assert(highlight.backgroundColor.alpha==0.28 && cell.children.count==1);
    cell.selected=NO; FPSelectionVisual(cell,YES);
    assert(highlight.hidden && cell.accessibilityTraits==128);
    FPSelectionVisual(cell,NO);
    assert([cell.accessories isEqual:native] && !cell.children.count);
    assert(!objc_getAssociatedObject(cell,&FPSelectionViewKey));
    assert(!objc_getAssociatedObject(cell,&FPAccessoriesKey));
    assert(!objc_getAssociatedObject(cell,&FPFilteredAccessoriesKey));
    FPSelectionVisual(cell,YES); cell.accessories=@[progress]; // Native left editing mode.
    FPSelectionVisual(cell,NO); assert(([cell.accessories isEqual:@[progress]]));
    cell.accessories=native; cell.selected=YES; FPSelectionVisual(cell,YES);
    FPSelectionVisual(cell,NO); assert(cell.isSelected); // Styling never mutates real selection.
    cell.selected=NO; FPSelectionVisual(cell,YES);
    assert(((UIView *)objc_getAssociatedObject(cell,&FPSelectionViewKey)).hidden);
    FPSelectionVisual(cell,NO);
    cell.accessories=@[arrow,progress]; FPDisclosure(cell,YES); assert(([cell.accessories isEqual:@[progress]]));
    FPDisclosure(cell,YES); FPDisclosure(cell,NO); assert(([cell.accessories isEqual:@[arrow,progress]]));
    FPDisclosure(cell,YES); cell.accessories=@[]; FPDisclosure(cell,NO); assert(!cell.accessories.count);
    assert(FPSidebarScope(YES,YES,NO)); assert(!FPSidebarScope(NO,YES,NO)); assert(!FPSidebarScope(YES,NO,NO)); assert(!FPSidebarScope(YES,YES,YES));
    assert(FPSidebarLines(200,80,100,17)==1); assert(FPSidebarHeight(17,1)==44); assert(FPSidebarHeight(50,1)==58);
    UIViewController *owner=[UIViewController new]; owner.navigationItem=[UINavigationItem new]; owner.navigationItem.largeTitleDisplayMode=1;
    FPSidebarTitle(owner,YES); FPSidebarTitle(owner,YES); assert(owner.navigationItem.largeTitleDisplayMode==2);
    FPSidebarTitle(owner,NO); assert(owner.navigationItem.largeTitleDisplayMode==1);
    puts("PASS production public margins reclaimed/restored; sidebar/disclosure: scoped single-line >=44pt Dynamic Type row policy, large title restoration, arrow removal/restoration and native replacement retained");
    puts("PASS production selection visual: exact accessory filter, native selection mapping, light/dark tint, VoiceOver traits, scope exit, reuse and native accessory replacement");
    puts("LIMIT Foundation view doubles exercise production functions, not UIKit rendering or Files device integration");
} return 0; }
'''
Path(sys.argv[1]).write_text(prefix+production+main)
