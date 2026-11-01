// Reuse the existing native/dictation UIKit surface without modifying it.
#import "../../native/stubs/UIKit/UIKit.h"
@interface UIImage : NSObject
@property(nonatomic,copy) NSArray<UIImage *> *images;
@property(nonatomic,copy) NSData *mockBytes;
+ (instancetype)imageWithData:(NSData *)data;
@end
@interface UINavigationController (WUImageEntryMockSurface)
@property(nonatomic,copy) NSArray<UIViewController *> *viewControllers;
- (void)setViewControllers:(NSArray<UIViewController *> *)controllers animated:(BOOL)animated;
@end
