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
static int copies, writes, nested;
@interface ImageProperties : NSObject <NSCopying>
@property CGSize maximumSize;
@property CGSize reservedLayoutSize;
@end
@implementation ImageProperties
- (id)copyWithZone:(NSZone *)zone { ImageProperties *p=[ImageProperties new]; p.maximumSize=_maximumSize; p.reservedLayoutSize=_reservedLayoutSize; return p; }
@end
@interface UIListContentConfiguration : NSObject <NSCopying>
@property ImageProperties *imageProperties;
@property NSDirectionalEdgeInsets directionalLayoutMargins;
@property CGFloat imageToTextPadding;
@property NSUInteger axesPreservingSuperviewLayoutMargins;
@property NSString *text;
@property id image;
@end
@implementation UIListContentConfiguration
- (instancetype)init { if((self=[super init])) { _imageProperties=[ImageProperties new]; _imageProperties.maximumSize=CGSizeMake(40,40); _imageProperties.reservedLayoutSize=CGSizeMake(40,40); _directionalLayoutMargins=(NSDirectionalEdgeInsets){7,18,9,18}; _imageToTextPadding=12; _axesPreservingSuperviewLayoutMargins=3; } return self; }
- (id)copyWithZone:(NSZone *)zone { copies++; UIListContentConfiguration *p=[UIListContentConfiguration new]; p.imageProperties=[_imageProperties copy]; p.directionalLayoutMargins=_directionalLayoutMargins; p.imageToTextPadding=_imageToTextPadding; p.axesPreservingSuperviewLayoutMargins=_axesPreservingSuperviewLayoutMargins; p.text=_text; p.image=_image; return p; }
@end
@interface UICollectionViewCell : NSObject
@property(nonatomic,copy) id contentConfiguration;
@property BOOL scope;
@property BOOL reenter;
@end
static void StyleCell(UICollectionViewCell *cell, BOOL compact);
static void FPStyleVisibleCell(UICollectionViewCell *cell);
@implementation UICollectionViewCell
- (void)setContentConfiguration:(id)value {
    writes++; _contentConfiguration=[value copy];
    if(self.reenter) {
        assert(++nested<8); // Bound a broken fixture instead of overflowing the stack.
        FPStyleVisibleCell(self);
        StyleCell(self,YES); StyleCell(self,NO); // Synchronous setter/layout scope-flip reentry.
        --nested;
    }
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
    assert(writes==before+1 && FPCompactConfigurationMatches(cell.contentConfiguration));
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
    puts("PASS production style: synchronous setter reentry; 1000 repeats zero writes/copies; busy never restores; exit restores exactly once; replacement text/image/style survives; reuse and unknown layout untouched; 20pt/gap6/margins10");
    puts("LIMIT Foundation doubles execute production functions, not UIKit rendering or a device hang reproduction");
} return 0; }
'''
if '--mutate-margin' in sys.argv:
    production=production.replace('margins.leading=10;', 'margins.leading=0;')
Path(sys.argv[1]).write_text(prefix+production+main)
