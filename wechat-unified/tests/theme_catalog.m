#import <Foundation/Foundation.h>
#import "ThemeCatalog.h"
#import "ThemeArchive.h"
#import "ThemeLibrary.h"
#include <assert.h>
#include <math.h>
static NSData *D(NSString *s) { return [s dataUsingEncoding:NSUTF8StringEncoding]; }
int main(void) { @autoreleasepool {
    NSString *a=@"11111111-1111-4111-8111-111111111111",*b=@"22222222-2222-4222-8222-222222222222";
    NSDictionary *old=@{@"light/icons/icon@2x.png":D(@"light"),@"dark/icons/icon@3x.png":D(@"dark")};
    assert(WUThemeSafePath(@"浅色/icons/icon@2x.png"));
    for(NSString *path in @[@"../a.png",@"a/../b.png",@".hidden/a.png",@"a//b.png",@"/a.png",@"a\\b.png",@"a:b.png"]) assert(!WUThemeSafePath(path));
    NSError *e=nil;
    NSDictionary *merged=WUThemeMergeFiles(old,@{@"other/icons/icon.png":D(@"other")},NO,&e); assert(merged.count==3&&[merged[@"light/icons/icon@2x.png"] isEqual:old[@"light/icons/icon@2x.png"]]);
    assert(WUThemeMergeFiles(old,@{@"LIGHT/icons/icon@2x.PNG":D(@"light")},NO,NULL).count==2);
    assert(!WUThemeMergeFiles(old,@{@"light/icons/icon@2x.png":D(@"new")},NO,&e)&&e);
    merged=WUThemeMergeFiles(old,@{@"light/icons/icon@2x.png":D(@"new")},YES,NULL); assert([merged[@"light/icons/icon@2x.png"] isEqual:D(@"new")]);
    assert(!WUThemeMergeFiles(@{@"A":D(@"file")},@{@"a/b.png":D(@"child")},YES,NULL));
    NSDictionary *idx=WUThemeResourceIndex(@[@"Pack/light/icon@2x.png",@"Pack/dark/icon@3x.png",@"Pack/icon.png",@"else/icon@3x.png"]);
    assert([idx[@"dark/icon"] isEqual:@[@"Pack/dark/icon@3x.png"]]); assert([idx[@"light/icon"] isEqual:@[@"Pack/light/icon@2x.png"]]);
    assert([WUThemeBestPath(@[@"a@2x.png",@"a@3x.png"],2.5) isEqual:@"a@3x.png"]);
    assert([WUThemeBestPath(@[@"nested/a@2x.png",@"a@2x.png"],2) isEqual:@"a@2x.png"]);
    NSArray *c=WUThemeCandidates(@"Chatroom_Bubble_Text_Sender_HL@2x.PNG",YES,@{});
    assert([c containsObject:@"chatroom_bubble_text_sender_dark_hl"]&&[c containsObject:@"chatroom_bubble_text_sender_hl_dark"]&&[c containsObject:@"chatroom_bubble_text_sender_new_hl"]);
    assert([c indexOfObject:@"chatroom_bubble_text_sender_dark_hl"]<[c indexOfObject:@"chatroom_bubble_text_sender_hl"]);
    assert([WUThemeCandidates(@"a_hl_dark",NO,@{}).firstObject isEqual:@"a_hl_dark"]);
    assert([WUThemeCandidates(@"a_new_hl",YES,@{}) containsObject:@"a_dark_hl"]);
    assert(![WUThemeCandidates(@"a_new_hl",YES,@{}) containsObject:@"a_new_new_hl"]);
    NSDictionary *descriptor=WUThemeReadDescriptor(D(@"{\"version\":1,\"aliases\":{\"Send@2x.PNG\":\"Pack/Button.SVG\"},\"catalogAssets\":{\"nested/Assets.car\":[\"cover\"]}}"),NULL);
    assert([descriptor[@"aliases"][@"send"] isEqual:@"pack/button"]);
    assert([WUThemeCandidates(@"send",NO,descriptor[@"aliases"]) containsObject:@"pack/button"]);
    assert(!WUThemeReadDescriptor(D(@"{\"version\":1,\"aliases\":{\"a\":\"../escape\"}}"),NULL));
    assert(!WUThemeReadDescriptor(D(@"{\"version\":1,\"catalogAssets\":{\"Assets.car\":[]}}"),NULL));
    NSArray *packs=@[@{@"id":a,@"name":@"A",@"size":@20},@{@"id":b,@"name":@"B",@"size":@10}];
    assert([WUThemeSortedPacks(packs,@{@"sort":@"name",@"ascending":@NO})[0][@"id"] isEqual:b]);
    assert([WUThemeSortedPacks(packs,@{@"sort":@"size",@"ascending":@YES,@"pinned":@[a]})[0][@"id"] isEqual:a]);
    assert(!WUValidThemeOptions(@{@"pinned":@[a,a]})&&!WUValidThemeOptions(@{@"sort":@"random"}));
    assert(WUValidSurfaceStyles(@{@"inputBorder":@{@"radius":@0,@"fontSize":@20,@"textDark":@"#fafaff80"}}));
    assert(!WUValidSurfaceStyles(@{@"inputBorder":@{@"radius":@(NAN)}}));
    assert(!WUValidSurfaceStyles(@{@"inputBorder":@{@"background":@"url(http://x)"}}));
    assert(!WUValidSurfaceStyles(@{@"guessedSendButton":@{@"radius":@12}}));
    NSDictionary *colors=WUThemeReadColors(D(@":root { --weui-BG-1: #fff; --weui-FG-0: rgba(0,0,0,0.9); } @media (prefers-color-scheme: dark) { :root { --weui-BG-1:#111; --weui-BRAND:#0f8; } }"),@"css",NO,&e);
    assert([colors[@"light"][@"bg-1"] isEqual:@"#ffffffff"]); assert([colors[@"dark"][@"bg-1"] isEqual:@"#111111ff"]);
    assert([colors[@"light"][@"fg-0"] isEqual:@"#000000e6"]);
    colors=WUThemeReadColors(D(@"[data-weui-theme=light] { --weui-BG-1:#eee; } :root { --weui-BRAND:#123; }"),@"css",YES,NULL);
    assert([colors[@"light"][@"bg-1"] isEqual:@"#eeeeeeff"]&&colors[@"dark"][@"brand"]);
    colors=WUThemeReadColors(D(@"<resources><!-- synthetic --><color name=\"weui_BG_1\">#80112233</color><color name=\"brand\">#8123</color></resources>"),@"xml",YES,NULL);
    assert([colors[@"dark"][@"bg-1"] isEqual:@"#11223380"]&&[colors[@"dark"][@"brand"] isEqual:@"#11223388"]);
    for(NSString *css in @[@"@import 'https://example.invalid'; :root{--weui-BG-1:#fff;}",@":root{--weui-BG-1:var(--unknown);}",@":root{--weui-BG-1:rgba(300,0,0,1);}",@":root{--weui-BG-1:#fff;"]) assert(!WUThemeReadColors(D(css),@"css",NO,NULL));
    assert(!WUThemeReadColors(D(@"<!DOCTYPE resources [<!ENTITY x SYSTEM 'file:///etc/passwd'>]><resources><color name='bg-1'>&x;</color></resources>"),@"xml",NO,NULL));
    NSData *zip=WUWriteThemeZIP(old,&e); assert(zip&&[WUReadThemeZIP(zip,NULL) isEqual:old]);
    assert([WUWriteThemeZIP(old,NULL) isEqual:zip]);
    assert(!WUWriteThemeZIP(@{@"A":D(@"x"),@"a/b":D(@"y")},NULL));
    NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]; assert([NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:NO attributes:nil error:&e]);
    assert(WUThemeCommitPack(root,a,old,@{@"name":@"Synthetic",@"size":@9},&e));
    NSString *path=[root stringByAppendingPathComponent:a]; assert([WUThemeReadPackFiles(path,NULL) isEqual:old]);
    assert(WUThemeCommitPack(root,a,merged,@{@"name":@"Appended"},&e)); assert([WUThemeReadPackFiles(path,NULL) isEqual:merged]);
    assert(!WUThemeCommitPack(root,a,@{@"../escape":D(@"bad")},@{@"name":@"Bad"},NULL)); assert([WUThemeReadPackFiles(path,NULL) isEqual:merged]);
    assert([WUThemePackMetadata(path)[@"name"] isEqual:@"Appended"]);
    assert([NSFileManager.defaultManager createSymbolicLinkAtPath:[path stringByAppendingPathComponent:@"link.png"] withDestinationPath:@"/etc/passwd" error:&e]); assert(!WUThemeReadPackFiles(path,NULL));
    [NSFileManager.defaultManager removeItemAtPath:root error:NULL];
    puts("Theme production Foundation tests passed: directory merge/conflict, names/variants/scale, sort/pin, options, CSS/XML, ZIP roundtrip, atomic directory swap, failed write retention, link rejection.");
} return 0; }
