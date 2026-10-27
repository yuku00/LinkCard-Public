#import "Theme.h"
#import "Trace.h"
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <sys/sysctl.h>

// No rule, mailbox, message, data-source or system-preference dependencies.
static char SnapshotKey;
static NSMapTable *ToolbarOwners; // weak keys and values: never retain or dereference a dead controller
static NSHashTable *Controllers;
static NSMapTable *Sections;
static id Null(id value) { return value ?: NSNull.null; }
static id Value(id value) { return value == NSNull.null ? nil : value; }
BOOL MRThemeEnabled(void) {
    CFPropertyListRef raw=CFPreferencesCopyAppValue(CFSTR("themeEnabled"), CFSTR("dev.mailrules.theme"));
    BOOL enabled=raw ? (CFGetTypeID(raw)==CFBooleanGetTypeID() && CFBooleanGetValue((CFBooleanRef)raw)) : YES;
    if(raw) CFRelease(raw);
    return enabled;
}
static BOOL Allowed(UIViewController *vc) {
    NSString *name=NSStringFromClass(vc.class);
    return [@[@"MailboxPickerOutlineController",@"MessageListViewController",@"ConversationViewController"] containsObject:name];
}
static UICollectionView *Collection(UIViewController *vc) {
    if ([NSStringFromClass(vc.class) isEqual:@"ConversationViewController"]) return nil;
    SEL sel=NSSelectorFromString(@"collectionView");
    Method m=class_getInstanceMethod(vc.class,sel);
    if(!m || strcmp(method_getTypeEncoding(m),"@16@0:8")) return nil;
    id view=((id(*)(id,SEL))objc_msgSend)(vc,sel);
    return [view isKindOfClass:UICollectionView.class] ? view : nil;
}
static void Restore(UIViewController *vc) {
    NSDictionary *s=objc_getAssociatedObject(vc,&SnapshotKey);
    if(!s) return;
    UINavigationItem *item=vc.navigationItem;
    item.standardAppearance=Value(s[@"navStandard"]);
    item.scrollEdgeAppearance=Value(s[@"navEdge"]);
    item.compactAppearance=Value(s[@"navCompact"]);
    item.compactScrollEdgeAppearance=Value(s[@"navCompactEdge"]);
    UIToolbar *bar=Value(s[@"toolbar"]);
    if(bar && [ToolbarOwners objectForKey:bar]==vc) {
        bar.standardAppearance=s[@"toolStandard"];
        bar.scrollEdgeAppearance=Value(s[@"toolEdge"]);
        bar.compactAppearance=Value(s[@"toolCompact"]);
        bar.compactScrollEdgeAppearance=Value(s[@"toolCompactEdge"]);
        bar.tintColor=Value(s[@"toolTint"]);
        [ToolbarOwners removeObjectForKey:bar];
    }
    UICollectionView *collection=Value(s[@"collection"]);
    if(collection) collection.backgroundColor=Value(s[@"background"]);
    objc_setAssociatedObject(vc,&SnapshotKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void Apply(UIViewController *vc) {
    MRD(@"theme.apply",@"pending",@"entered",vc,@{@"enabled":@(MRThemeEnabled())});
    if(!Allowed(vc) || !vc.isViewLoaded) {MRD(@"theme.apply",@"skipped",@"guard",vc,nil);return;}
    if(!MRThemeEnabled()) { Restore(vc); return; }
    UINavigationItem *item=vc.navigationItem;
    UIToolbar *bar=vc.navigationController.toolbar;
    UICollectionView *collection=Collection(vc);
    if(!objc_getAssociatedObject(vc,&SnapshotKey)) {
        // Shared toolbar ownership is transferred only after restoring its previous owner.
        UIViewController *previous=[ToolbarOwners objectForKey:bar];
        if(previous && previous!=vc) Restore(previous);
        NSDictionary *s=@{@"navStandard":Null(item.standardAppearance),@"navEdge":Null(item.scrollEdgeAppearance),
            @"navCompact":Null(item.compactAppearance),@"navCompactEdge":Null(item.compactScrollEdgeAppearance),
            @"toolbar":Null(bar),@"toolStandard":Null(bar.standardAppearance),@"toolEdge":Null(bar.scrollEdgeAppearance),
            @"toolCompact":Null(bar.compactAppearance),@"toolCompactEdge":Null(bar.compactScrollEdgeAppearance),@"toolTint":Null(bar.tintColor),
            @"collection":Null(collection),@"background":Null(collection.backgroundColor)};
        objc_setAssociatedObject(vc,&SnapshotKey,s,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if(bar) [ToolbarOwners setObject:vc forKey:bar];
    }
    UINavigationBarAppearance *nav=[[[UINavigationBarAppearance alloc] init] autorelease];
    [nav configureWithDefaultBackground];
    nav.backgroundColor=UIColor.systemGroupedBackgroundColor;
    nav.titleTextAttributes=@{NSForegroundColorAttributeName:UIColor.labelColor,
        NSFontAttributeName:[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline compatibleWithTraitCollection:vc.traitCollection]};
    nav.largeTitleTextAttributes=@{NSForegroundColorAttributeName:UIColor.labelColor,
        NSFontAttributeName:[UIFont preferredFontForTextStyle:UIFontTextStyleLargeTitle compatibleWithTraitCollection:vc.traitCollection]};
    // Per-controller appearances, never UIAppearance/global navigation bars.
    item.standardAppearance=nav; item.scrollEdgeAppearance=nav;
    item.compactAppearance=nav; item.compactScrollEdgeAppearance=nav;
    if(bar && [ToolbarOwners objectForKey:bar]==vc) {
        UIToolbarAppearance *tool=[[[UIToolbarAppearance alloc] init] autorelease];
        [tool configureWithDefaultBackground]; tool.backgroundColor=UIColor.systemGroupedBackgroundColor;
        bar.standardAppearance=tool; bar.scrollEdgeAppearance=tool;
        bar.compactAppearance=tool; bar.compactScrollEdgeAppearance=tool;
        bar.tintColor=UIColor.systemBlueColor;
    }
    if(collection) collection.backgroundColor=UIColor.systemGroupedBackgroundColor;
    MRD(@"theme.apply",@"success",@"ok",vc,nil);
}
void MRThemeSetEnabled(BOOL enabled) {
    MRD(@"theme.toggle",@"pending",@"entered",nil,@{@"enabled":@(enabled)});
    NSCAssert(NSThread.isMainThread,@"Theme changes must run on main thread");
    CFPreferencesSetAppValue(CFSTR("themeEnabled"), enabled ? kCFBooleanTrue : kCFBooleanFalse, CFSTR("dev.mailrules.theme"));
    BOOL synced=CFPreferencesAppSynchronize(CFSTR("dev.mailrules.theme"));
    MRD(@"theme.toggle",synced?@"success":@"failed",synced?@"ok":@"sync_failed",nil,@{@"enabled":@(enabled),@"saved":@(synced)});
    for(NSCollectionLayoutSection *section in Sections) {
        NSDirectionalEdgeInsets insets; [[Sections objectForKey:section] getValue:&insets];
        section.contentInsets=insets;
    }
    [Sections removeAllObjects];
    for(UIViewController *vc in Controllers.allObjects) {
        Restore(vc);
        if(enabled && vc.viewIfLoaded.window) Apply(vc);
        [Collection(vc).collectionViewLayout invalidateLayout];
    }
}
static BOOL Hook(Class c,NSString *name,const char *encoding,id (^factory)(IMP)) {
    SEL sel=NSSelectorFromString(name); Method m=class_getInstanceMethod(c,sel);
    MRDDeclare(@"install.theme",name,encoding,m?method_getTypeEncoding(m):NULL,m && !strcmp(method_getTypeEncoding(m),encoding));
    if(!m || strcmp(method_getTypeEncoding(m),encoding)) return NO;
    IMP imp=imp_implementationWithBlock(factory(method_getImplementation(m)));
    if(!class_addMethod(c,sel,imp,encoding)) method_setImplementation(m,imp);
    return YES;
}
__attribute__((constructor)) static void InstallTheme(void) {
    @autoreleasepool {
        if(![NSBundle.mainBundle.bundleIdentifier isEqual:@"com.apple.mobilemail"]) return;
        char build[64]={0};size_t size=sizeof(build);
        BOOL supported=!sysctlbyname("kern.osversion",build,&size,NULL,0) && !strcmp(build,"20G75");
        Controllers=[[NSHashTable weakObjectsHashTable] retain];
        ToolbarOwners=[[NSMapTable weakToWeakObjectsMapTable] retain];
        Sections=[[NSMapTable weakToStrongObjectsMapTable] retain];
        for(NSString *name in @[@"MailboxPickerOutlineController",@"MessageListViewController",@"ConversationViewController"]) {
            Class c=NSClassFromString(name); if(!c) continue;
            Hook(c,@"viewWillAppear:","v20@0:8B16",^id(IMP original) {
                return [[^(UIViewController *vc,BOOL animated) {
                    ((void(*)(id,SEL,BOOL))original)(vc,@selector(viewWillAppear:),animated);
                    MRDInstallButton(vc);MRD(@"ui.lifecycle",@"success",@"original_returned",vc,nil);
                    if(supported && Allowed(vc)) { [Controllers addObject:vc]; Apply(vc); }
                } copy] autorelease];
            });
            Hook(c,@"viewWillDisappear:","v20@0:8B16",^id(IMP original) {
                return [[^(UIViewController *vc,BOOL animated) {
                    MRD(@"ui.lifecycle",@"success",@"entered",vc,nil);Restore(vc);
                    ((void(*)(id,SEL,BOOL))original)(vc,@selector(viewWillDisappear:),animated);
                } copy] autorelease];
            });
            Hook(c,@"traitCollectionDidChange:","v24@0:8@16",^id(IMP original) {
                return [[^(UIViewController *vc,UITraitCollection *previous) {
                    ((void(*)(id,SEL,id))original)(vc,@selector(traitCollectionDidChange:),previous);
                    if(supported && vc.viewIfLoaded.window) Apply(vc);
                } copy] autorelease];
            });
        }
        // Actual IPA caller creates a native list section including its existing header mode.
        // Keep that section, all providers, and every item; change visual side spacing only.
        if(supported) Hook(NSClassFromString(@"MailboxPickerOutlineController"),@"_configuredSectionForSection:layoutEnvironment:","@32@0:8q16@24",^id(IMP original) {
            return [[^id(id vc,NSInteger index,id environment) {
                id result=((id(*)(id,SEL,NSInteger,id))original)(vc,NSSelectorFromString(@"_configuredSectionForSection:layoutEnvironment:"),index,environment);
                MRD(@"theme.section",@"success",@"original_returned",vc,@{@"section":@(index),@"resultPresent":@(result!=nil),@"enabled":@(MRThemeEnabled())});
                if(MRThemeEnabled() && Allowed(vc) && [result isKindOfClass:NSCollectionLayoutSection.class]) {
                    NSCollectionLayoutSection *section=result;
                    NSDirectionalEdgeInsets insets=section.contentInsets;
                    if(![Sections objectForKey:section]) [Sections setObject:[NSValue valueWithBytes:&insets objCType:@encode(NSDirectionalEdgeInsets)] forKey:section];
                    insets.leading=MAX(insets.leading,12); insets.trailing=MAX(insets.trailing,12);
                    section.contentInsets=insets;
                }
                return result;
            } copy] autorelease];
        });
    }
}
