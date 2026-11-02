// Reuse the unchanged chat test's UIKit mocks and ImageIO fixture generator.
#define main ExistingChatImageTests
#import "image_entry_native.m"
#undef main
int main(int argc,const char *argv[]) { @autoreleasepool {
    NSString *mode=argc>1?[NSString stringWithUTF8String:argv[1]]:@"normal"; RegisterEditor(mode);
    account=@"synthetic-account"; session=nil; selectedTool=NO; throwSelection=YES;
    enabled=YES; generation++; UIApplication.sharedApplication.applicationState=UIApplicationStateActive;
    NSData *png=Fixture(@"public.png",1);
    UIViewController *article=[UIViewController new]; window=[UIWindow new]; [window addSubview:article.view];
    nav=[ImageNavigation new]; [nav setViewControllers:@[article] animated:NO];
    __block BOOL valid=YES; __block int before=0,editing=0;
    BOOL (^guard)(BOOL)=^BOOL(BOOL opened){if(opened) editing++;else before++;return valid;};
    BOOL opened=WUOpenConfirmedImageDataEditor(article,png,guard);
    if(![mode isEqual:@"normal"]) { CHECK(!opened && nav.topViewController==article && initCalls==0 && entries.count==0); }
    else {
        CHECK(opened && before>0 && editing>0 && WUImageEntryOwnsNavigation(article));
        CHECK([((ImageEditorBase *)nav.topViewController).accepted.mockBytes isEqual:png]);
        CHECK(!WUOpenConfirmedImageDataEditor(article,png,guard));
        UIViewController *other=[UIViewController new]; [nav pushViewController:other animated:NO];
        WUCancelImageDataEditor(article); CHECK(nav.topViewController==other && nav.viewControllers.count==2 && entries.count==0);
        [nav setViewControllers:@[article] animated:NO];
        CHECK(WUOpenConfirmedImageDataEditor(article,png,guard)); valid=NO; Tick(); CHECK(nav.topViewController==article && entries.count==0);
        valid=YES;
        for(NSData *bad in @[Fixture(@"com.compuserve.gif",2),APNGMarker(png),NSData.data,[NSMutableData dataWithLength:20*1024*1024+1]]) CHECK(!WUOpenConfirmedImageDataEditor(article,bad,guard));
        CHECK(WUOpenConfirmedImageDataEditor(article,png,guard)); generation++; Tick(); CHECK(entries.count==0 && nav.topViewController==article);
        CHECK(WUOpenConfirmedImageDataEditor(article,png,guard)); account=@"changed-account"; Tick(); CHECK(entries.count==0 && nav.topViewController==article);
        CHECK(WUOpenConfirmedImageDataEditor(article,png,guard));
        [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:nil]; CHECK(entries.count==0);
        CHECK(WUOpenConfirmedImageDataEditor(article,png,guard)); [nav setViewControllers:@[article] animated:NO]; NSUInteger changes=nav.changes; Tick(); CHECK(entries.count==0 && nav.changes==changes);
        valid=NO; CHECK(!WUOpenConfirmedImageDataEditor(article,png,guard));
        CHECK(!WUOpenConfirmedImageDataEditor(article,png,^BOOL(BOOL editing){ if(entries.count) WUCancelImageDataEditor(article); return YES; }));
        CHECK(entries.count==0 && nav.topViewController==article);
    }
    WUCancelImageEntries();
    printf("article-data %s: %d assertions; shared real production editor path; no chat selection/session or network\n",mode.UTF8String,checks);
} return 0; }
