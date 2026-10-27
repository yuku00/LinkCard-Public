from pathlib import Path
import sys
r=Path(__file__).resolve().parents[1]
production=(r/'CompactSelection.inc').read_text()
prefix=r'''#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#include <assert.h>
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
    UICellAccessory *arrow=[UICellAccessory new], *progress=[UICellAccessory new];
    UICellAccessory *circle=[UICellAccessoryMultiselect new];
    NSArray *native=@[circle,arrow,progress]; cell.accessories=native;
    cell.accessibilityTraits=128; cell.bounds=CGRectMake(0,0,190,50);
    FPSelectionVisual(cell,YES);
    assert(([cell.accessories isEqual:@[arrow,progress]]));
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
    puts("PASS production selection visual: exact accessory filter, native selection mapping, light/dark tint, VoiceOver traits, scope exit, reuse and native accessory replacement");
    puts("LIMIT Foundation view doubles exercise production functions, not UIKit rendering or Files device integration");
} return 0; }
'''
Path(sys.argv[1]).write_text(prefix+production+main)
