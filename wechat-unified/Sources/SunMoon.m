#import "WU.h"
#import <QuartzCore/QuartzCore.h>
static char switchSkinKey;
static NSHashTable<UISwitch *> *switches;
@interface WUSunMoon : UIControl
@property(nonatomic,weak) UISwitch *original;
@property(nonatomic,assign) CGPoint began;
@property(nonatomic,assign) BOOL initial;
- (void)sync;
@end
@implementation WUSunMoon
- (instancetype)initWithFrame:(CGRect)frame { if((self=[super initWithFrame:frame])) { self.opaque=NO; self.isAccessibilityElement=NO; self.accessibilityElementsHidden=YES; self.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight; } return self; }
- (void)sync { self.enabled=self.original.enabled; self.alpha=self.original.enabled?1:.45; [self setNeedsDisplay]; }
- (BOOL)beginTracking:(UITouch *)touch withEvent:(UIEvent *)event { self.began=[touch locationInView:self]; self.initial=self.original.on; return self.enabled; }
- (void)endTracking:(UITouch *)touch withEvent:(UIEvent *)event {
    UISwitch *sw=self.original; CGPoint p=[touch locationInView:self];
    if(!sw.enabled || !self.window || !CGRectContainsPoint(CGRectInset(self.bounds,-16,-16),p) || !WUEnabled(@"sunMoon")) { [self sync]; return; }
    BOOL on=fabs(p.x-self.began.x)>8?p.x>CGRectGetMidX(self.bounds):!self.initial;
    if(sw.on!=on) { [sw setOn:on animated:!UIAccessibilityIsReduceMotionEnabled()]; [sw sendActionsForControlEvents:UIControlEventValueChanged]; }
    [self sync];
}
- (void)cancelTrackingWithEvent:(UIEvent *)event { [self sync]; }
- (void)drawRect:(CGRect)rect {
    BOOL day=self.original.on; CGRect b=CGRectInset(self.bounds,.5,.5); CGFloat h=b.size.height;
    UIColor *sky=day?[UIColor colorWithRed:.22 green:.65 blue:.90 alpha:1]:[UIColor colorWithRed:.12 green:.16 blue:.30 alpha:1];
    [sky setFill]; [[UIBezierPath bezierPathWithRoundedRect:b cornerRadius:h/2] fill];
    CGContextRef ctx=UIGraphicsGetCurrentContext(); CGContextSaveGState(ctx); [[UIBezierPath bezierPathWithRoundedRect:b cornerRadius:h/2] addClip];
    if(day) { [[UIColor colorWithWhite:1 alpha:.6] setFill]; [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(4,h*.54,18,8)] fill]; [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(9,h*.42,9,9)] fill]; }
    else { [[UIColor colorWithWhite:1 alpha:.8] setFill]; for(NSValue *v in @[[NSValue valueWithCGPoint:CGPointMake(.62,.27)],[NSValue valueWithCGPoint:CGPointMake(.84,.49)],[NSValue valueWithCGPoint:CGPointMake(.65,.74)]]) { CGPoint p=v.CGPointValue; [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(b.size.width*p.x,h*p.y,2,2)] fill]; } }
    CGFloat side=h-6,x=day?CGRectGetMaxX(b)-side-3:b.origin.x+3; CGRect disc=CGRectMake(x,b.origin.y+3,side,side);
    [(day?[UIColor colorWithRed:1 green:.84 blue:.35 alpha:1]:[UIColor colorWithRed:.90 green:.94 blue:1 alpha:1]) setFill]; [[UIBezierPath bezierPathWithOvalInRect:disc] fill];
    if(!day) { [sky setFill]; [[UIBezierPath bezierPathWithOvalInRect:CGRectOffset(CGRectInset(disc,2,2),6,-3)] fill]; }
    CGContextRestoreGState(ctx);
}
@end
static void ClearSwitch(UISwitch *sw) { WUSunMoon *skin=objc_getAssociatedObject(sw,&switchSkinKey); if(!skin) return; [sw removeTarget:skin action:@selector(sync) forControlEvents:UIControlEventValueChanged]; [skin removeFromSuperview]; objc_setAssociatedObject(sw,&switchSkinKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
static void SkinWalk(UIView *v,NSUInteger depth,NSUInteger *budget) {
    if(!*budget || depth>10) return; --*budget;
    if([v isKindOfClass:UISwitch.class]) {
        UISwitch *sw=(UISwitch *)v; if(!WUEnabled(@"sunMoon") || CGRectIsEmpty(sw.bounds)) { ClearSwitch(sw); return; }
        WUSunMoon *skin=objc_getAssociatedObject(sw,&switchSkinKey); if(!skin) { skin=[[WUSunMoon alloc] initWithFrame:sw.bounds]; skin.original=sw; objc_setAssociatedObject(sw,&switchSkinKey,skin,OBJC_ASSOCIATION_RETAIN_NONATOMIC); [sw addSubview:skin]; [sw addTarget:skin action:@selector(sync) forControlEvents:UIControlEventValueChanged]; [switches addObject:sw]; }
        skin.frame=sw.bounds; [sw bringSubviewToFront:skin]; [skin sync]; return;
    }
    for(UIView *c in v.subviews) SkinWalk(c,depth+1,budget);
}
void WUStyleSettingSwitches(UIViewController *controller) {
    // Only callers in our settings and the explicitly hooked NewSettingViewController.
    static dispatch_once_t once; dispatch_once(&once, ^{ switches=NSHashTable.weakObjectsHashTable;
        [NSNotificationCenter.defaultCenter addObserverForName:WUChanged object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n){ for(UISwitch *sw in switches) { ClearSwitch(sw); [sw setNeedsLayout]; } [switches removeAllObjects]; }];
    });
    NSUInteger budget=512; SkinWalk(controller.view,0,&budget);
}
