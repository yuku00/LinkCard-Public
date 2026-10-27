from pathlib import Path
import sys
r=Path(__file__).resolve().parents[1]
production=(r/'CompactCells.inc').read_text()
actions=(r/'NativeActions.inc').read_text()
production+=actions[actions.index('static void FPStyleVisibleCell'):actions.index('static void FPHookCell')]
prefix=r'''#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#include <assert.h>
typedef struct { CGFloat top, leading, bottom, trailing; } NSDirectionalEdgeInsets;
static int copies, writes, nested, accessoryWrites, backgroundWrites;
static NSString *const UIFontTextStyleBody=@"body", *const UIFontTextStyleCaption1=@"caption";
@interface UIFont : NSObject
@property CGFloat pointSize;
+ (instancetype)systemFontOfSize:(CGFloat)size;
@end
@implementation UIFont
+ (instancetype)systemFontOfSize:(CGFloat)size { UIFont *font=[UIFont new]; font.pointSize=size; return font; }
- (BOOL)isEqual:(id)other { return [other isKindOfClass:UIFont.class] && self.pointSize==[other pointSize]; }
@end
@interface UIFontMetrics : NSObject
+ (instancetype)metricsForTextStyle:(NSString *)style;
- (UIFont *)scaledFontForFont:(UIFont *)font compatibleWithTraitCollection:(NSNumber *)trait;
@end
@implementation UIFontMetrics
+ (instancetype)metricsForTextStyle:(NSString *)style { return [UIFontMetrics new]; }
- (UIFont *)scaledFontForFont:(UIFont *)font compatibleWithTraitCollection:(NSNumber *)trait { return [UIFont systemFontOfSize:font.pointSize*(trait ? trait.doubleValue : 1)]; }
@end
@interface UIColor : NSObject
@property CGFloat alpha;
- (instancetype)colorWithAlphaComponent:(CGFloat)alpha;
@end
@implementation UIColor
- (instancetype)colorWithAlphaComponent:(CGFloat)alpha { UIColor *color=[UIColor new]; color.alpha=alpha; return color; }
- (BOOL)isEqual:(id)other { return [other isKindOfClass:UIColor.class] && self.alpha==[other alpha]; }
@end
@interface TextProperties : NSObject <NSCopying>
@property UIFont *font;
@property BOOL adjustsFontForContentSizeCategory;
@end
@implementation TextProperties
- (instancetype)init { if((self=[super init])) _font=[UIFont systemFontOfSize:17]; return self; }
- (id)copyWithZone:(NSZone *)zone { TextProperties *p=[TextProperties new]; p.font=_font; p.adjustsFontForContentSizeCategory=_adjustsFontForContentSizeCategory; return p; }
@end
@interface UIBackgroundConfiguration : NSObject <NSCopying>
@property UIColor *backgroundColor;
@property id nativeMarker;
+ (instancetype)clearConfiguration;
@end
@implementation UIBackgroundConfiguration
+ (instancetype)clearConfiguration { return [UIBackgroundConfiguration new]; }
- (id)copyWithZone:(NSZone *)zone { copies++; UIBackgroundConfiguration *p=[UIBackgroundConfiguration new]; p.backgroundColor=_backgroundColor; p.nativeMarker=_nativeMarker; return p; }
@end
@interface UICellAccessory : NSObject @end
@implementation UICellAccessory @end
@interface UICellAccessoryMultiselect : UICellAccessory @end
@implementation UICellAccessoryMultiselect @end
@interface UICellAccessoryDisclosureIndicator : UICellAccessory @end
@implementation UICellAccessoryDisclosureIndicator @end
@interface ImageProperties : NSObject <NSCopying>
@property CGSize maximumSize;
@property CGSize reservedLayoutSize;
@end
@implementation ImageProperties
- (id)copyWithZone:(NSZone *)zone { ImageProperties *p=[ImageProperties new]; p.maximumSize=_maximumSize; p.reservedLayoutSize=_reservedLayoutSize; return p; }
@end
@interface UIListContentConfiguration : NSObject <NSCopying>
@property ImageProperties *imageProperties;
@property TextProperties *textProperties;
@property TextProperties *secondaryTextProperties;
@property NSDirectionalEdgeInsets directionalLayoutMargins;
@property CGFloat imageToTextPadding;
@property NSUInteger axesPreservingSuperviewLayoutMargins;
@property NSString *text;
@property id image;
@end
@implementation UIListContentConfiguration
- (instancetype)init { if((self=[super init])) { _textProperties=[TextProperties new]; _secondaryTextProperties=[TextProperties new]; _imageProperties=[ImageProperties new]; _imageProperties.maximumSize=CGSizeMake(40,40); _imageProperties.reservedLayoutSize=CGSizeMake(40,40); _directionalLayoutMargins=(NSDirectionalEdgeInsets){7,18,9,18}; _imageToTextPadding=12; _axesPreservingSuperviewLayoutMargins=3; } return self; }
- (id)copyWithZone:(NSZone *)zone { copies++; UIListContentConfiguration *p=[UIListContentConfiguration new]; p.textProperties=[_textProperties copy]; p.secondaryTextProperties=[_secondaryTextProperties copy]; p.imageProperties=[_imageProperties copy]; p.directionalLayoutMargins=_directionalLayoutMargins; p.imageToTextPadding=_imageToTextPadding; p.axesPreservingSuperviewLayoutMargins=_axesPreservingSuperviewLayoutMargins; p.text=_text; p.image=_image; return p; }
@end
@interface UICollectionViewCell : NSObject
@property(nonatomic,copy) id contentConfiguration;
@property BOOL scope;
@property BOOL reenter;
@property(nonatomic,copy) UIBackgroundConfiguration *backgroundConfiguration;
@property(getter=isSelected) BOOL selected;
@property UIColor *tintColor;
@property NSNumber *traitCollection;
@end
@interface UICollectionViewListCell : UICollectionViewCell
@property(nonatomic,copy) NSArray<UICellAccessory *> *accessories;
@end
static void StyleCell(UICollectionViewCell *cell, BOOL compact);
static void FPStyleVisibleCell(UICollectionViewCell *cell);
static void Reenter(UICollectionViewCell *cell) {
    if(cell.reenter) {
        assert(++nested<8);
        FPStyleVisibleCell(cell);
        StyleCell(cell,YES); StyleCell(cell,NO);
        --nested;
    }
}
@implementation UICollectionViewCell
- (void)setContentConfiguration:(id)value {
    writes++; _contentConfiguration=[value copy]; Reenter(self);
}
- (void)setBackgroundConfiguration:(UIBackgroundConfiguration *)value {
    backgroundWrites++; _backgroundConfiguration=[value copy]; Reenter(self);
}
@end
@implementation UICollectionViewListCell
- (void)setAccessories:(NSArray<UICellAccessory *> *)value {
    accessoryWrites++; _accessories=[value copy]; Reenter(self);
}
@end
static BOOL IsPaneListCell(UICollectionViewCell *cell) { return cell.scope; }
'''
main=r'''
int main(void) { @autoreleasepool {
    UICollectionViewCell *cell=[UICollectionViewCell new]; cell.scope=YES;
    UIListContentConfiguration *native=[UIListContentConfiguration new]; native.text=@"native"; native.image=[NSObject new];
    cell.contentConfiguration=native; cell.reenter=YES;
    int before=writes; FPStyleVisibleCell(cell);
    assert(writes==before+1 && FPCompactConfigurationMatches(cell.contentConfiguration,cell));
    assert(((UIListContentConfiguration *)cell.contentConfiguration).directionalLayoutMargins.top==7);
    assert(((UIListContentConfiguration *)cell.contentConfiguration).directionalLayoutMargins.bottom==9);
    int copyCount=copies; before=writes;
    for(int i=0;i<1000;i++) FPStyleVisibleCell(cell);
    assert(writes==before && copies==copyCount && nested==0);
    objc_setAssociatedObject(cell,&FPCellBusyKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    cell.scope=NO; FPStyleVisibleCell(cell); StyleCell(cell,NO);
    assert(writes==before && objc_getAssociatedObject(cell,&CellStyleKey));
    objc_setAssociatedObject(cell,&FPCellBusyKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    FPStyleVisibleCell(cell); assert(writes==before+1);
    UIListContentConfiguration *restored=cell.contentConfiguration;
    assert(restored.imageToTextPadding==12 && restored.directionalLayoutMargins.leading==18);
    assert(restored.imageProperties.maximumSize.width==40 && restored.axesPreservingSuperviewLayoutMargins==3);
    assert([restored.text isEqual:@"native"] && restored.image==native.image);
    for(int i=0;i<1000;i++) FPStyleVisibleCell(cell);
    assert(writes==before+1 && !objc_getAssociatedObject(cell,&CellStyleKey));
    cell.scope=YES; FPStyleVisibleCell(cell);
    cell.reenter=NO;
    UIListContentConfiguration *newNative=[UIListContentConfiguration new]; newNative.text=@"new provider row"; newNative.image=[NSObject new]; newNative.imageToTextPadding=23;
    cell.contentConfiguration=newNative; cell.reenter=YES; cell.scope=NO; before=writes;
    FPStyleVisibleCell(cell);
    assert(writes==before && !objc_getAssociatedObject(cell,&CellStyleKey));
    assert([((UIListContentConfiguration *)cell.contentConfiguration).text isEqual:newNative.text]);
    assert(((UIListContentConfiguration *)cell.contentConfiguration).image==newNative.image);
    assert(((UIListContentConfiguration *)cell.contentConfiguration).imageToTextPadding==23);
    cell.scope=YES; FPStyleVisibleCell(cell); cell.scope=NO; FPStyleVisibleCell(cell);
    assert(((UIListContentConfiguration *)cell.contentConfiguration).imageToTextPadding==23);
    cell.scope=YES; FPStyleVisibleCell(cell);
    objc_setAssociatedObject(cell,&FPCellResettingKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    before=writes; FPStyleVisibleCell(cell); assert(writes==before);
    StyleCell(cell,NO); assert(writes==before+1);
    objc_setAssociatedObject(cell,&FPCellResettingKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    cell.reenter=NO; cell.contentConfiguration=@"unknown native layout"; cell.reenter=YES;
    before=writes; FPStyleVisibleCell(cell); assert(writes==before);
    UICollectionViewListCell *list=[UICollectionViewListCell new]; list.scope=YES;
    list.contentConfiguration=[UIListContentConfiguration new]; list.tintColor=[UIColor new]; list.selected=YES;
    UICellAccessory *provider=[UICellAccessory new], *back=[UICellAccessory new];
    NSArray *originalAccessories=@[[UICellAccessoryMultiselect new],provider,[UICellAccessoryDisclosureIndicator new],back];
    list.accessories=originalAccessories;
    UIBackgroundConfiguration *nativeBackground=[UIBackgroundConfiguration new]; nativeBackground.nativeMarker=[NSObject new]; nativeBackground.backgroundColor=[UIColor new];
    list.backgroundConfiguration=nativeBackground; list.reenter=YES;
    before=writes; int aBefore=accessoryWrites, bBefore=backgroundWrites;
    FPStyleVisibleCell(list);
    assert(writes==before+1 && accessoryWrites==aBefore+1 && backgroundWrites==bBefore+1);
    assert([list.accessories isEqual:@[provider,back]] && list.isSelected);
    assert(list.backgroundConfiguration.backgroundColor.alpha==0.18 && list.backgroundConfiguration.nativeMarker==nativeBackground.nativeMarker);
    UIListContentConfiguration *styled=list.contentConfiguration;
    assert(styled.textProperties.font.pointSize==14 && styled.secondaryTextProperties.font.pointSize==13);
    assert(styled.textProperties.adjustsFontForContentSizeCategory && styled.secondaryTextProperties.adjustsFontForContentSizeCategory);
    before=writes; aBefore=accessoryWrites; bBefore=backgroundWrites; copyCount=copies;
    for(int i=0;i<1000;i++) FPStyleVisibleCell(list);
    assert(writes==before && accessoryWrites==aBefore && backgroundWrites==bBefore && copies==copyCount && nested==0);
    objc_setAssociatedObject(list,&FPCellBusyKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    list.scope=NO; FPStyleVisibleCell(list); StyleCell(list,NO);
    assert(writes==before && accessoryWrites==aBefore && backgroundWrites==bBefore);
    objc_setAssociatedObject(list,&FPCellBusyKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    list.scope=YES; list.selected=NO; FPStyleVisibleCell(list);
    assert(!list.isSelected && backgroundWrites==bBefore+1 && list.backgroundConfiguration.backgroundColor==nativeBackground.backgroundColor);
    assert(writes==before && accessoryWrites==aBefore);
    list.selected=YES; FPStyleVisibleCell(list);
    list.traitCollection=@1.5; FPStyleVisibleCell(list);
    styled=list.contentConfiguration;
    assert(styled.textProperties.font.pointSize==21 && styled.secondaryTextProperties.font.pointSize==19.5);
    before=writes; aBefore=accessoryWrites; bBefore=backgroundWrites; copyCount=copies;
    for(int i=0;i<1000;i++) FPStyleVisibleCell(list);
    assert(writes==before && accessoryWrites==aBefore && backgroundWrites==bBefore && copies==copyCount);
    // Provider replaces accessories while compact: adopt its new list, never resurrect the old one.
    UICellAccessory *newProvider=[UICellAccessory new];
    NSArray *newAccessories=@[newProvider,[UICellAccessoryDisclosureIndicator new],back,[UICellAccessoryMultiselect new]];
    list.reenter=NO; list.accessories=newAccessories; list.reenter=YES;
    FPStyleVisibleCell(list); assert([list.accessories isEqual:@[newProvider,back]]);
    list.scope=NO; before=writes; aBefore=accessoryWrites; bBefore=backgroundWrites;
    FPStyleVisibleCell(list);
    assert(writes==before+1 && accessoryWrites==aBefore+1 && backgroundWrites==bBefore+1);
    assert([list.accessories isEqual:newAccessories] && list.isSelected);
    styled=list.contentConfiguration;
    assert(styled.textProperties.font.pointSize==17 && !styled.textProperties.adjustsFontForContentSizeCategory);
    assert(styled.secondaryTextProperties.font.pointSize==17 && !styled.secondaryTextProperties.adjustsFontForContentSizeCategory);
    for(int i=0;i<1000;i++) FPStyleVisibleCell(list);
    assert(writes==before+1 && accessoryWrites==aBefore+1 && backgroundWrites==bBefore+1);
    // Replacement on scope exit is native-owned, including a provider-only list and background.
    list.scope=YES; FPStyleVisibleCell(list);
    UIBackgroundConfiguration *newBackground=[UIBackgroundConfiguration new]; newBackground.nativeMarker=[NSObject new];
    list.reenter=NO; list.accessories=@[newProvider,back]; list.backgroundConfiguration=newBackground; list.reenter=YES;
    list.scope=NO; aBefore=accessoryWrites; bBefore=backgroundWrites;
    FPStyleVisibleCell(list);
    assert(accessoryWrites==aBefore && backgroundWrites==bBefore && [list.accessories isEqual:@[newProvider,back]]);
    assert(list.backgroundConfiguration.nativeMarker==newBackground.nativeMarker);
    // Reuse restores all three channels exactly once, even if setters reenter synchronously.
    list.reenter=NO; list.accessories=newAccessories; list.reenter=YES; list.scope=YES; FPStyleVisibleCell(list);
    objc_setAssociatedObject(list,&FPCellResettingKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    before=writes; aBefore=accessoryWrites; bBefore=backgroundWrites;
    FPStyleVisibleCell(list); StyleCell(list,NO); StyleCell(list,NO);
    assert(writes==before+1 && accessoryWrites==aBefore+1 && backgroundWrites==bBefore+1 && nested==0);
    assert([list.accessories isEqual:newAccessories] && list.backgroundConfiguration.nativeMarker==newBackground.nativeMarker);
    objc_setAssociatedObject(list,&FPCellResettingKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    puts("PASS production style: all setters synchronous reentry; 1000 repeats zero writes/copies; busy never restores; exit/reuse restores once; native replacement content/accessories/background survives; real selection unchanged; Dynamic Type 14/13; 20pt/gap6/margins10");
    puts("LIMIT Foundation doubles execute production functions, not UIKit rendering or a device hang reproduction");
} return 0; }
'''
if '--mutate-margin' in sys.argv:
    production=production.replace('margins.leading=10;', 'margins.leading=0;')
Path(sys.argv[1]).write_text(prefix+production+main)
