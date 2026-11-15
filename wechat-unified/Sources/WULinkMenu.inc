// Included by Messages.m: private menu methods are checked before every invocation.
#import "LinkLogic.h"
static IMP wuLinkMenuOriginal;
static char wuLinkMenuLeaseKey, wuLinkMenuItemKey, wuEmoticonMenuTokenKey, wuOwnerMenuLeaseKey;
static NSUInteger wuLinkMenuSerial;

static BOOL WULinkNumberGetter(id object, NSString *name) {
    Method m=object?class_getInstanceMethod(object_getClass(object),NSSelectorFromString(name)):NULL;
    for(NSString *type in @[@"I",@"i",@"Q",@"q"]) if(WUMatches(m,type.UTF8String,@[])) return YES;
    return NO;
}
static BOOL WULinkMessageReady(id wrap) {
    for(NSString *name in @[@"m_nsFromUsr",@"m_nsToUsr",@"m_nsRealChatUsr"]) if(!Has(wrap,name,"@",@[])) return NO;
    for(NSString *name in @[@"m_n64MesSvrID",@"m_uiMesLocalID",@"m_uiCreateTime",@"m_uiMessageType"]) if(!WULinkNumberGetter(wrap,name)) return NO;
    return YES;
}
static UIView *WUMenuActionCell(id receiver, SEL cmd, id argument) {
    UIView *cell=[receiver isKindOfClass:UIView.class]?receiver:nil;
    if(!cell && [receiver isKindOfClass:UIViewController.class]) {
        NSDictionary *lease=objc_getAssociatedObject(receiver,&wuOwnerMenuLeaseKey);
        UIView *(^source)(void)=lease[@"cell"];
        if([lease[@"selector"] isEqual:NSStringFromSelector(cmd)] && source) cell=source();
    }
    if(!cell && [argument isKindOfClass:UIView.class]) cell=argument;
    return cell;
}
static void WUMenuStoreLease(UIView *cell, UIViewController *owner, NSDictionary *lease) {
    __weak UIView *weakCell=cell;
    objc_setAssociatedObject(cell,&wuLinkMenuLeaseKey,lease,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(owner,&wuOwnerMenuLeaseKey,@{@"selector":lease[@"selector"],@"cell":[^UIView *{ return weakCell; } copy]},OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void WULinkMenuAction(id receiver, SEL cmd, id argument) {
    @try {
        if(!NSThread.isMainThread) return;
        UIView *cell=WUMenuActionCell(receiver,cmd,argument); if(!cell) return;
        NSDictionary *lease=objc_getAssociatedObject(cell,&wuLinkMenuLeaseKey);
        UIViewController *owner=Chat(cell);
        if(!lease || ![lease[@"selector"] isEqual:NSStringFromSelector(cmd)] || !owner || (receiver!=owner && receiver!=cell)) return;
        // Consume before presenting: an old menu cannot activate a newer lease.
        objc_setAssociatedObject(cell,&wuLinkMenuLeaseKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        BOOL (^current)(void)=lease[@"current"];
        if(current && current()) WUOpenSelectedLinks(owner,@[lease[@"content"]],current);
    } @catch(__unused NSException *e) {}
}
static NSString *WUMenuEmoticonMD5(id wrap) {
    if(!Has(wrap,@"m_nsEmoticonMD5","@",@[])) return nil;
    return Str(wrap,@"m_nsEmoticonMD5");
}
static BOOL WUMenuEmoticonEnabled(void) {
    return WUEnabled(@"repeatEmoticon") && [(WUValue(@"repeatOptions")?:WURepeatDefaults())[@"longDownload"] boolValue];
}
static void WUMenuEmoticonAction(id receiver, SEL cmd, id argument) {
    @try {
        if(!NSThread.isMainThread) return;
        UIView *cell=WUMenuActionCell(receiver,cmd,argument); if(!cell) return;
        NSDictionary *lease=objc_getAssociatedObject(cell,&wuLinkMenuLeaseKey);
        UIViewController *owner=Chat(cell);
        if(!lease || ![lease[@"selector"] isEqual:NSStringFromSelector(cmd)] || !owner || (receiver!=owner && receiver!=cell)) return;
        objc_setAssociatedObject(cell,&wuLinkMenuLeaseKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        BOOL (^current)(void)=lease[@"current"]; id wrap=lease[@"wrap"];
        if(current && current()) WUSaveEmoticonForWrap(owner,wrap,current,YES);
    } @catch(__unused NSException *e) {}
}
static id WUMenuAddEmoticon(id original, UIView *cell) {
    if(!WUMenuEmoticonEnabled()) return original;
    Class itemClass=NSClassFromString(@"MMMenuItem"); SEL init=NSSelectorFromString(@"initWithTitle:svgName:action:");
    if(!itemClass || !WUMatches(class_getInstanceMethod(itemClass,init),"@",@[@"@",@"@",@":"])) return original;
    UIViewController *owner=Chat(cell); id model=Obj(cell,@"viewModel"), wrap=Obj(model,@"messageWrap");
    if(!owner || !cell.window || !model || !wrap || !WULinkMessageReady(wrap)) return original;
    NSDictionary *identity=Info(wrap); NSString *account=Account(), *session=Session(owner), *md5=WUMenuEmoticonMD5(wrap); NSUInteger gen=generation;
    Class util=NSClassFromString(@"EmoticonUtil"); NSString *pathSelector=@"pathOfEmoticonForMd5:needUpdateTime:ignoreWxAM:";
    if([identity[@"type"] unsignedIntegerValue]!=47 || !account.length || !session.length || !InSession(identity,account,session) || (![identity[@"id"] unsignedLongLongValue] && ![identity[@"local"] unsignedLongLongValue]) || !WUValidMD5(md5) || !Has(util,pathSelector,"@",@[@"@",@"B",@"B"])) return original;
    NSObject *token=[NSObject new]; objc_setAssociatedObject(cell,&wuEmoticonMenuTokenKey,token,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UIView *weakCell=cell; __weak UIViewController *weakOwner=owner; __weak id weakModel=model, weakWrap=wrap;
    BOOL (^current)(void)=^BOOL {
        @try {
            UIView *c=weakCell; UIViewController *v=weakOwner; id m=weakModel,w=weakWrap;
            return c && v && m && w && objc_getAssociatedObject(c,&wuEmoticonMenuTokenKey)==token && (c.window || WUMessageEntriesOwnsController(v.presentedViewController)) && UIApplication.sharedApplication.applicationState==UIApplicationStateActive && Chat(c)==v && (!v.navigationController || v.navigationController.topViewController==v) && Obj(c,@"viewModel")==m && Obj(m,@"messageWrap")==w && WULinkMessageReady(w) && [Info(w) isEqual:identity] && [md5 isEqual:WUMenuEmoticonMD5(w)] && WUMenuEmoticonEnabled() && [account isEqual:Account()] && gen==generation && [session isEqual:Session(v)];
        } @catch(__unused NSException *e) { return NO; }
    };
    if(!current() || wuLinkMenuSerial>=4096) return original;
    SEL action=NSSelectorFromString([NSString stringWithFormat:@"wu_saveEmoticonToPhotos_%lu:",(unsigned long)++wuLinkMenuSerial]);
    Class ownerClass=object_getClass(owner),cellClass=object_getClass(cell);
    if(class_getInstanceMethod(ownerClass,action) || class_getInstanceMethod(cellClass,action) || !class_addMethod(ownerClass,action,(IMP)WUMenuEmoticonAction,"v@:@") || !class_addMethod(cellClass,action,(IMP)WUMenuEmoticonAction,"v@:@")) return original;
    id item=((id(*)(id,SEL,id,id,SEL))objc_msgSend)([itemClass alloc],init,@"保存表情到图库",@"",action);
    if(!item || ![item isKindOfClass:itemClass] || !current()) return original;
    objc_setAssociatedObject(item,&wuLinkMenuItemKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    WUMenuStoreLease(cell,owner,@{@"selector":NSStringFromSelector(action),@"current":[current copy],@"wrap":wrap});
    return [original arrayByAddingObject:item];
}
static void WUMenuImageAction(id receiver, SEL cmd, id argument) {
    @try {
        if(!NSThread.isMainThread) return;
        UIView *cell=WUMenuActionCell(receiver,cmd,argument); if(!cell) return;
        NSDictionary *lease=objc_getAssociatedObject(cell,&wuLinkMenuLeaseKey); UIViewController *owner=Chat(cell);
        if(!lease || ![lease[@"selector"] isEqual:NSStringFromSelector(cmd)] || !owner || (receiver!=owner && receiver!=cell)) return;
        objc_setAssociatedObject(cell,&wuLinkMenuLeaseKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        BOOL (^current)(void)=lease[@"current"];
        if(current && current()) WUOpenMessageImageEditor(owner,lease[@"wrap"],current);
    } @catch(__unused NSException *e) {}
}
static id WUMenuAddImage(id original, UIView *cell) {
    if(![WUValue(@"enabled") boolValue]) return original;
    Class itemClass=NSClassFromString(@"MMMenuItem"); SEL init=NSSelectorFromString(@"initWithTitle:svgName:action:");
    if(!itemClass || !WUMatches(class_getInstanceMethod(itemClass,init),"@",@[@"@",@"@",@":"])) return original;
    UIViewController *owner=Chat(cell); id model=Obj(cell,@"viewModel"), wrap=Obj(model,@"messageWrap");
    if(!owner || !cell.window || !model || !wrap || !WULinkMessageReady(wrap)) return original;
    if(!Has(wrap,@"m_nsImageHDPath","@",@[]) && !Has(wrap,@"m_nsImagePath","@",@[])) return original;
    Class editor=NSClassFromString(@"EmoticonPickViewController");
    if(!editor || ![editor isSubclassOfClass:UIViewController.class] || !WUMatches(class_getInstanceMethod(editor,@selector(init)),"@",@[]) || !WUMatches(class_getInstanceMethod(editor,NSSelectorFromString(@"setM_image:")),"v",@[@"@"])) return original;
    NSDictionary *identity=Info(wrap); NSString *account=Account(), *session=Session(owner); NSUInteger gen=generation;
    if([identity[@"type"] unsignedIntegerValue]!=3 || !account.length || !session.length || !InSession(identity,account,session) || (![identity[@"id"] unsignedLongLongValue] && ![identity[@"local"] unsignedLongLongValue])) return original;
    NSObject *token=[NSObject new]; objc_setAssociatedObject(cell,&wuEmoticonMenuTokenKey,token,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UIView *weakCell=cell; __weak UIViewController *weakOwner=owner; __weak id weakModel=model, weakWrap=wrap;
    BOOL (^current)(void)=^BOOL {
        @try {
            UIView *c=weakCell; UIViewController *v=weakOwner; id m=weakModel,w=weakWrap;
            return c && v && m && w && objc_getAssociatedObject(c,&wuEmoticonMenuTokenKey)==token && (c.window || WUImageEntryOwnsNavigation(v)) && Chat(c)==v && Obj(c,@"viewModel")==m && Obj(m,@"messageWrap")==w && WULinkMessageReady(w) && [Info(w) isEqual:identity] && [WUValue(@"enabled") boolValue] && [account isEqual:Account()] && gen==generation && [session isEqual:Session(v)];
        } @catch(__unused NSException *e) { return NO; }
    };
    if(!current() || wuLinkMenuSerial>=4096) return original;
    SEL action=NSSelectorFromString([NSString stringWithFormat:@"wu_imageToEmoticon_%lu:",(unsigned long)++wuLinkMenuSerial]);
    Class ownerClass=object_getClass(owner),cellClass=object_getClass(cell);
    if(class_getInstanceMethod(ownerClass,action) || class_getInstanceMethod(cellClass,action) || !class_addMethod(ownerClass,action,(IMP)WUMenuImageAction,"v@:@") || !class_addMethod(cellClass,action,(IMP)WUMenuImageAction,"v@:@")) return original;
    id item=((id(*)(id,SEL,id,id,SEL))objc_msgSend)([itemClass alloc],init,@"图片转表情",@"",action);
    if(!item || ![item isKindOfClass:itemClass] || !current()) return original;
    objc_setAssociatedObject(item,&wuLinkMenuItemKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    WUMenuStoreLease(cell,owner,@{@"selector":NSStringFromSelector(action),@"current":[current copy],@"wrap":wrap});
    return [original arrayByAddingObject:item];
}
static id WULinkFilteredMenu(id cell, SEL cmd, id input) {
    id original=((id(*)(id,SEL,id))wuLinkMenuOriginal)(cell,cmd,input);
    @try {
        if(!NSThread.isMainThread || ![cell isKindOfClass:UIView.class]) return original;
        objc_setAssociatedObject(cell,&wuLinkMenuLeaseKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(cell,&wuEmoticonMenuTokenKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if(![original isKindOfClass:NSArray.class]) return original;
        NSMutableArray *host=[NSMutableArray array];
        for(id item in original) if(!objc_getAssociatedObject(item,&wuLinkMenuItemKey)) [host addObject:item];
        if(host.count!=[original count]) original=[host copy];
        id withImage=WUMenuAddImage(original,cell);
        if(withImage!=original) return withImage;
        id withEmoticon=WUMenuAddEmoticon(original,cell);
        if(withEmoticon!=original) return withEmoticon;
        if(!WUEnabled(@"enhancedLinks")) return original;
        Class itemClass=NSClassFromString(@"MMMenuItem"); SEL init=NSSelectorFromString(@"initWithTitle:svgName:action:");
        if(!itemClass || !WUMatches(class_getInstanceMethod(itemClass,init),"@",@[@"@",@"@",@":"])) return original;
        UIViewController *owner=Chat(cell); id model=Obj(cell,@"viewModel"), wrap=Obj(model,@"messageWrap");
        if(!owner || ![(UIView *)cell window] || !model || !wrap || !WULinkMessageReady(wrap)) return original;
        NSString *account=Account(), *session=Session(owner); NSUInteger gen=generation;
        NSDictionary *identity=Info(wrap); NSString *text=Str(wrap,@"m_nsContent");
        if(!account.length || !session.length || !text || text.length>8192 || !InSession(identity,account,session) || (![identity[@"id"] unsignedLongLongValue] && ![identity[@"local"] unsignedLongLongValue])) return original;
        NSDictionary *content=@{@"type":identity[@"type"],@"content":text};
        if(!WULinkCandidates(@[content]).count) return original;
        __weak UIView *weakCell=cell; __weak UIViewController *weakOwner=owner; __weak id weakModel=model, weakWrap=wrap;
        BOOL (^current)(void)=^BOOL {
            @try {
                UIView *c=weakCell; UIViewController *v=weakOwner; id m=weakModel, w=weakWrap;
                return c && v && m && w && (c.window || WUMessageEntriesOwnsController(v.presentedViewController)) && Chat(c)==v && Obj(c,@"viewModel")==m && Obj(m,@"messageWrap")==w && WULinkMessageReady(w) && [Info(w) isEqual:identity] && [text isEqual:Str(w,@"m_nsContent")] && WUEnabled(@"enhancedLinks") && [account isEqual:Account()] && gen==generation && [session isEqual:Session(v)];
            } @catch(__unused NSException *e) { return NO; }
        };
        if(!current() || wuLinkMenuSerial>=4096) return original;
        SEL action=NSSelectorFromString([NSString stringWithFormat:@"wu_identifyLink_%lu:",(unsigned long)++wuLinkMenuSerial]);
        Class ownerClass=object_getClass(owner), cellClass=object_getClass(cell);
        if(class_getInstanceMethod(ownerClass,action) || class_getInstanceMethod(cellClass,action) || !class_addMethod(ownerClass,action,(IMP)WULinkMenuAction,"v@:@") || !class_addMethod(cellClass,action,(IMP)WULinkMenuAction,"v@:@")) return original;
        id item=((id(*)(id,SEL,id,id,SEL))objc_msgSend)([itemClass alloc],init,@"识别链接",@"",action);
        if(!item || ![item isKindOfClass:itemClass] || !current()) return original;
        objc_setAssociatedObject(item,&wuLinkMenuItemKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        WUMenuStoreLease(cell,owner,@{@"selector":NSStringFromSelector(action),@"current":[current copy],@"content":content});
        return [original arrayByAddingObject:item];
    } @catch(__unused NSException *e) { return original; }
}
static void WUInstallLinkMenu(void) {
    Class cell=NSClassFromString(@"BaseMessageCellView"), item=NSClassFromString(@"MMMenuItem");
    if(!cell || !item || !WUMatches(class_getInstanceMethod(item,NSSelectorFromString(@"initWithTitle:svgName:action:")),"@",@[@"@",@"@",@":"])) return;
    WUHook(@"BaseMessageCellView",@"filteredMenuItems:",NO,"@",@[@"@"],(IMP)WULinkFilteredMenu,&wuLinkMenuOriginal);
}
