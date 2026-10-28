// Foundation/CoreGraphics host doubles, NOT UIKit or a device layout solver.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#include <assert.h>
#include <string.h>
#include <math.h>
typedef struct { CGFloat top, leading, bottom, trailing; } NSDirectionalEdgeInsets;
typedef NSInteger NSLayoutAttribute;
enum { NSLayoutAttributeNotAnAttribute=0, NSLayoutAttributeLeft=1, NSLayoutAttributeRight=2, NSLayoutAttributeLeading=5, NSLayoutAttributeTrailing=6, NSLayoutAttributeWidth=7, NSLayoutAttributeHeight=8 };
enum { NSLayoutRelationEqual=0, NSLayoutRelationLessThanOrEqual=-1, UILayoutConstraintAxisHorizontal=0, UILayoutConstraintAxisVertical=1, UIStackViewDistributionFill=0, NSLineBreakByTruncatingTail=4 };
static int copies, writes, nested, accessoryWrites, backgroundWrites, nativeWrites;
static int parentUpdates, childUpdates, bridgeUpdates, parentReuse, childReuse, parentDisplays, childDisplays;
@class UICollectionViewCell, NSLayoutConstraint;
static void StyleCell(UICollectionViewCell *cell, BOOL compact);
static void FPStyleVisibleCell(UICollectionViewCell *cell);
static void Reenter(UICollectionViewCell *cell);
static __weak UICollectionViewCell *nativeReentry;
static void NativeWrite(void) { nativeWrites++; if(nativeReentry) Reenter(nativeReentry); }
@interface NSValue (HostSize)
+ (instancetype)valueWithCGSize:(CGSize)size;
- (CGSize)CGSizeValue;
@end
@implementation NSValue (HostSize)
+ (instancetype)valueWithCGSize:(CGSize)size { return [NSValue valueWithBytes:&size objCType:@encode(CGSize)]; }
- (CGSize)CGSizeValue { CGSize size; [self getValue:&size size:sizeof(size)]; return size; }
@end
static NSString *const UIFontTextStyleBody=@"body", *const UIFontTextStyleCaption1=@"caption";
@interface UIFont : NSObject
@property CGFloat pointSize;
@property(readonly) CGFloat lineHeight;
+ (instancetype)systemFontOfSize:(CGFloat)size;
@end
@implementation UIFont
+ (instancetype)systemFontOfSize:(CGFloat)size { UIFont *font=[UIFont new]; font.pointSize=size; return font; }
- (CGFloat)lineHeight { return self.pointSize*1.2; }
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
@interface UIResponder : NSObject
@property(nonatomic,weak) UIResponder *nextResponder;
@end
@implementation UIResponder @end
@class UIView;
@interface UILayoutGuide : NSObject
@property(nonatomic,weak) UIView *owningView;
@end
@implementation UILayoutGuide @end
@interface UIView : UIResponder
@property(nonatomic,weak) UIView *superview;
@property NSMutableArray<UIView *> *subviews;
@property NSMutableArray<NSLayoutConstraint *> *constraints;
@property CGRect bounds;
@property NSDirectionalEdgeInsets directionalLayoutMargins;
@property id layoutMarginsGuide;
@property BOOL translatesAutoresizingMaskIntoConstraints;
@property(getter=isHidden) BOOL hidden;
- (void)addSubview:(UIView *)view;
- (BOOL)isDescendantOfView:(UIView *)view;
@end
@implementation UIView
- (instancetype)init { if((self=[super init])) { _subviews=[NSMutableArray new]; _constraints=[NSMutableArray new]; _bounds=CGRectMake(0,0,320,72); _layoutMarginsGuide=[UILayoutGuide new]; [(UILayoutGuide *)_layoutMarginsGuide setOwningView:self]; } return self; }
- (void)addSubview:(UIView *)view { [view.superview.subviews removeObjectIdenticalTo:view]; view.superview=self; view.nextResponder=self; [_subviews addObject:view]; }
- (BOOL)isDescendantOfView:(UIView *)view { for(UIView *v=self;v;v=v.superview) if(v==view) return YES; return NO; }
@end
@interface NSLayoutConstraint : NSObject
@property id firstItem, secondItem;
@property NSLayoutAttribute firstAttribute, secondAttribute;
@property NSInteger relation;
@property CGFloat multiplier;
@property(nonatomic) CGFloat constant;
@property(nonatomic) BOOL active;
@property(nonatomic) float priority;
+ (instancetype)constraintWithItem:(id)first attribute:(NSLayoutAttribute)a relatedBy:(NSInteger)relation toItem:(id)second attribute:(NSLayoutAttribute)b multiplier:(CGFloat)m constant:(CGFloat)c;
@end
@implementation NSLayoutConstraint
+ (instancetype)constraintWithItem:(id)first attribute:(NSLayoutAttribute)a relatedBy:(NSInteger)relation toItem:(id)second attribute:(NSLayoutAttribute)b multiplier:(CGFloat)m constant:(CGFloat)c { NSLayoutConstraint *v=[self new]; v.firstItem=first; v.secondItem=second; v.firstAttribute=a; v.secondAttribute=b; v.relation=relation; v.multiplier=m; v.constant=c; v.priority=1000; return v; }
- (void)setConstant:(CGFloat)value { _constant=value; NativeWrite(); }
- (void)setPriority:(float)value { _priority=value; NativeWrite(); }
- (void)setActive:(BOOL)value { _active=value; if(!self.secondItem && [self.firstItem isKindOfClass:UIView.class] && ![[(UIView *)self.firstItem constraints] containsObject:self]) [[(UIView *)self.firstItem constraints] addObject:self]; NativeWrite(); }
@end
@interface UIStackView : UIView
@property NSMutableArray<UIView *> *arrangedSubviews;
@property NSInteger axis, distribution;
@property BOOL layoutMarginsRelativeArrangement;
@property NSMapTable *spacings;
- (void)addArrangedSubview:(UIView *)view;
- (CGFloat)customSpacingAfterView:(UIView *)view;
- (void)setCustomSpacing:(CGFloat)spacing afterView:(UIView *)view;
@end
@implementation UIStackView
- (instancetype)init { if((self=[super init])) { _arrangedSubviews=[NSMutableArray new]; _spacings=[NSMapTable strongToStrongObjectsMapTable]; } return self; }
- (void)addArrangedSubview:(UIView *)view { [self addSubview:view]; [_arrangedSubviews addObject:view]; }
- (CGFloat)customSpacingAfterView:(UIView *)view { NSNumber *n=[_spacings objectForKey:view]; return n ? n.doubleValue : 12; }
- (void)setCustomSpacing:(CGFloat)value afterView:(UIView *)view { [_spacings setObject:@(value) forKey:view]; NativeWrite(); }
@end
@interface UILabel : UIView
@property(nonatomic) UIFont *font;
@property(nonatomic) NSInteger numberOfLines, lineBreakMode;
@property(nonatomic) BOOL adjustsFontForContentSizeCategory;
@property NSString *text;
@end
@implementation UILabel
- (instancetype)init { if((self=[super init])) { _font=[UIFont systemFontOfSize:17]; _numberOfLines=1; self.bounds=CGRectMake(0,0,200,36); } return self; }
- (void)setFont:(UIFont *)value { _font=value; NativeWrite(); }
- (void)setNumberOfLines:(NSInteger)value { _numberOfLines=value; NativeWrite(); }
- (void)setLineBreakMode:(NSInteger)value { _lineBreakMode=value; NativeWrite(); }
- (void)setAdjustsFontForContentSizeCategory:(BOOL)value { _adjustsFontForContentSizeCategory=value; NativeWrite(); }
@end
@interface UIImageView : UIView
@property id image;
@end
@implementation UIImageView @end
@interface UIViewController : UIResponder
@property(nonatomic,weak) UIViewController *parentViewController;
@property NSArray *childViewControllers;
@property UIViewController *presentedViewController;
@end
@implementation UIViewController @end
@interface FPBrowserPane : UIViewController @end
@implementation FPBrowserPane @end
@interface UICollectionView : UIView
@property id delegate;
@property NSArray *visibleCells;
@end
@implementation UICollectionView @end
@interface TextProperties : NSObject <NSCopying>
@property UIFont *font;
@property BOOL adjustsFontForContentSizeCategory;
@property NSInteger numberOfLines, lineBreakMode;
@end
@implementation TextProperties
- (instancetype)init { if((self=[super init])) { _font=[UIFont systemFontOfSize:17]; _numberOfLines=1; } return self; }
- (id)copyWithZone:(NSZone *)zone { TextProperties *p=[TextProperties new]; p.font=_font; p.adjustsFontForContentSizeCategory=_adjustsFontForContentSizeCategory; p.numberOfLines=_numberOfLines; p.lineBreakMode=_lineBreakMode; return p; }
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
@property CGSize maximumSize, reservedLayoutSize;
@end
@implementation ImageProperties
- (id)copyWithZone:(NSZone *)zone { ImageProperties *p=[ImageProperties new]; p.maximumSize=_maximumSize; p.reservedLayoutSize=_reservedLayoutSize; return p; }
@end
@interface UIListContentConfiguration : NSObject <NSCopying>
@property ImageProperties *imageProperties;
@property TextProperties *textProperties, *secondaryTextProperties;
@property NSDirectionalEdgeInsets directionalLayoutMargins;
@property CGFloat imageToTextPadding;
@property NSUInteger axesPreservingSuperviewLayoutMargins;
@property NSString *text, *secondaryText;
@property NSAttributedString *secondaryAttributedText;
@property id image;
@end
@implementation UIListContentConfiguration
- (instancetype)init { if((self=[super init])) { _textProperties=[TextProperties new]; _secondaryTextProperties=[TextProperties new]; _imageProperties=[ImageProperties new]; _imageProperties.maximumSize=CGSizeMake(40,40); _imageProperties.reservedLayoutSize=CGSizeMake(40,40); _directionalLayoutMargins=(NSDirectionalEdgeInsets){7,18,9,18}; _imageToTextPadding=12; _axesPreservingSuperviewLayoutMargins=3; } return self; }
- (id)copyWithZone:(NSZone *)zone { copies++; UIListContentConfiguration *p=[UIListContentConfiguration new]; p.textProperties=[_textProperties copy]; p.secondaryTextProperties=[_secondaryTextProperties copy]; p.imageProperties=[_imageProperties copy]; p.directionalLayoutMargins=_directionalLayoutMargins; p.imageToTextPadding=_imageToTextPadding; p.axesPreservingSuperviewLayoutMargins=_axesPreservingSuperviewLayoutMargins; p.text=_text; p.image=_image; p.secondaryText=_secondaryText; p.secondaryAttributedText=_secondaryAttributedText; return p; }
@end
@interface UICellConfigurationState : NSObject @end
@implementation UICellConfigurationState @end
@interface UICollectionViewCell : UIView
@property(nonatomic,copy) id contentConfiguration;
@property BOOL reenter;
@property(nonatomic,copy) UIBackgroundConfiguration *backgroundConfiguration;
@property(getter=isSelected) BOOL selected;
@property UIColor *tintColor;
@property NSNumber *traitCollection;
@property UIView *contentView;
@property id titleLabel, thumbnailView, subtitleLabel, dateLabel, sizeLabel, cellContent;
@property BOOL renaming;
- (id)accessibilityTitleLabel;
- (id)accessibilityThumbnailView;
- (id)accessibilitySubtitleLabel;
- (id)accessibilityDateLabel;
- (id)accessibilitySizeLabel;
- (BOOL)accessibilityIsRenaming;
- (void)updateConfigurationUsingState:(UICellConfigurationState *)state;
- (void)_bridgedUpdateConfigurationUsingState:(UICellConfigurationState *)state;
- (void)prepareForReuse;
@end
@interface UICollectionViewListCell : UICollectionViewCell
@property(nonatomic,copy) NSArray<UICellAccessory *> *accessories;
@end
static void Reenter(UICollectionViewCell *cell) {
    if(cell.reenter) { assert(++nested<8); FPStyleVisibleCell(cell); StyleCell(cell,YES); StyleCell(cell,NO); --nested; }
}
@implementation UICollectionViewCell
- (instancetype)init { if((self=[super init])) { _contentView=[UIView new]; [self addSubview:_contentView]; _tintColor=[UIColor new]; } return self; }
- (void)setContentConfiguration:(id)value { writes++; _contentConfiguration=[value copy]; Reenter(self); }
- (void)setBackgroundConfiguration:(UIBackgroundConfiguration *)value { backgroundWrites++; _backgroundConfiguration=[value copy]; Reenter(self); }
- (id)accessibilityTitleLabel { return self.titleLabel; }
- (id)accessibilityThumbnailView { return self.thumbnailView; }
- (id)accessibilitySubtitleLabel { return self.subtitleLabel; }
- (id)accessibilityDateLabel { return self.dateLabel; }
- (id)accessibilitySizeLabel { return self.sizeLabel; }
- (BOOL)accessibilityIsRenaming { return self.renaming; }
- (void)updateConfigurationUsingState:(UICellConfigurationState *)state { parentUpdates++; [self _bridgedUpdateConfigurationUsingState:state]; }
- (void)_bridgedUpdateConfigurationUsingState:(UICellConfigurationState *)state { bridgeUpdates++; }
- (void)prepareForReuse { parentReuse++; }
@end
@implementation UICollectionViewListCell
- (void)setAccessories:(NSArray<UICellAccessory *> *)value { accessoryWrites++; _accessories=[value copy]; Reenter(self); }
@end
@interface HookChild : UICollectionViewListCell @end
@implementation HookChild
- (void)updateConfigurationUsingState:(UICellConfigurationState *)state { childUpdates++; [super updateConfigurationUsingState:state]; }
- (void)prepareForReuse { childReuse++; [super prepareForReuse]; }
@end
@interface HostController : UIViewController
@property BOOL listMode;
- (BOOL)accessibilityIsInListMode;
- (void)collectionView:(UICollectionView *)view willDisplayCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)path;
@end
@implementation HostController
- (instancetype)init { if((self=[super init])) _listMode=YES; return self; }
- (BOOL)accessibilityIsInListMode { return self.listMode; }
- (void)collectionView:(UICollectionView *)view willDisplayCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)path { parentDisplays++; }
@end
static NSMutableArray *hostOwners;
static Class NamedClass(NSString *name, Class parent) { Class cls=objc_allocateClassPair(parent,name.UTF8String,0); assert(cls); objc_registerClassPair(cls); return cls; }
static FPBrowserPane *hostPane;
static void SetScope(UICollectionViewCell *cell, BOOL scope) {
    UICollectionView *cv=(id)cell.superview;
    ((HostController *)cv.delegate).parentViewController=scope ? hostPane : nil;
    cv.nextResponder=scope ? hostPane : nil;
}
static id NewCell(Class cls) {
    UICollectionViewCell *cell=[cls new]; UICollectionView *cv=[UICollectionView new];
    cv.delegate=[NSClassFromString(@"Files.DOCItemCollectionViewController") new];
    [cv addSubview:cell]; [hostOwners addObject:cv]; SetScope(cell,YES); return cell;
}
static void RegisterHostClasses(void) {
    hostPane=[FPBrowserPane new]; hostOwners=[NSMutableArray new];
    NamedClass(@"Files.DOCItemCollectionViewController",HostController.class);
    NamedClass(@"Files.DOCSidebarViewController",HostController.class);
    NamedClass(@"Files.DOCItemCollectionListCell",HookChild.class);
    NamedClass(@"Files.DOCItemCollectionCell",UICollectionViewCell.class);
    NamedClass(@"DOCFittingImageView",UIImageView.class);
    NamedClass(@"DOCBorderedFittingImageView",NSClassFromString(@"DOCFittingImageView"));
    NamedClass(@"DOCThumbnailFittingImageView",NSClassFromString(@"DOCBorderedFittingImageView"));
}
