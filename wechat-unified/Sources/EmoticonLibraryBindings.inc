// Included in Messages.m: use its verified selection/account/session helpers, never a second sender.
static void OpenEmoticonLibrary(UIViewController *owner) {
    NSString *account=Account(), *target=Session(owner); NSUInteger gen=generation;
    if(!account.length || !target.length) { Notice(owner,@"账号或当前会话不可核验，未打开表情库"); return; }
    WUEmoticonLibraryBinding *binding=[WUEmoticonLibraryBinding new]; binding.account=account; binding.target=target; binding.generation=gen;
    __weak UIViewController *weak=owner;
    BOOL (^current)(void)=^BOOL {
        @try { UIViewController *v=weak;
            return v && (v.viewIfLoaded.window || WUIsEmoticonLibraryController(v.presentedViewController)) && (!v.navigationController || v.navigationController.topViewController==v) && UIApplication.sharedApplication.applicationState==UIApplicationStateActive && [WUValue(@"enabled") boolValue] && [account isEqual:Account()] && gen==generation && [target isEqual:Session(v)] && [WUToolbarActions(WUAccountOptions(account)[@"toolbar"]) containsObject:@"emoticonLibrary"];
        } @catch(NSException *e) { return NO; }
    };
    binding.current=current;
    binding.capture=^NSDictionary * {
        @try {
            if(!current()) return nil; id selected=Obj(weak,@"getSelectedMsgs");
            if(![selected isKindOfClass:NSArray.class] || [selected count]!=1) return nil;
            id wrap=[selected firstObject]; NSDictionary *identity=Info(wrap);
            if([identity[@"type"] unsignedIntValue]!=47 || !InSession(identity,account,target)) return nil;
            NSString *md5=Str(wrap,@"m_nsEmoticonMD5")?:Str(Obj(wrap,@"m_extendInfoWithMsgType"),@"m_nsEmoticonMD5");
            Class util=NSClassFromString(@"EmoticonUtil"); NSString *selector=@"pathOfEmoticonForMd5:needUpdateTime:ignoreWxAM:";
            if(!WUValidMD5(md5) || !Has(util,selector,"@",@[@"@",@"B",@"B"])) return nil;
            id path=((id(*)(id,SEL,id,BOOL,BOOL))objc_msgSend)(util,NSSelectorFromString(selector),md5,NO,NO);
            if(![path isKindOfClass:NSString.class] || ![path isAbsolutePath] || !current()) return nil;
            return @{@"wrap":wrap,@"identity":identity,@"path":[path copy],@"md5":md5};
        } @catch(NSException *e) { return nil; }
    };
    // Pin the toolbar selection before presenting the library; never retarget a later message.
    NSDictionary *selectedSnapshot=binding.capture();
    binding.capture=^NSDictionary *{ return current()?selectedSnapshot:nil; };
    binding.selectionCurrent=^BOOL(NSDictionary *capture) {
        @try {
            if(!current()) return NO; id selected=Obj(weak,@"getSelectedMsgs"); id wrap=capture[@"wrap"];
            return [selected isKindOfClass:NSArray.class] && [selected count]==1 && [selected firstObject]==wrap && [Info(wrap) isEqual:capture[@"identity"]] && [capture[@"md5"] isEqual:(Str(wrap,@"m_nsEmoticonMD5")?:Str(Obj(wrap,@"m_extendInfoWithMsgType"),@"m_nsEmoticonMD5"))];
        } @catch(NSException *e) { return NO; }
    };
    binding.canSubmit=^BOOL{ return current() && WUEmoticonDataAvailable(Service(@"CMessageMgr")); };
    binding.submit=^NSString *(NSData *data) {
        if(!current()) return @"账号、会话、开关或代次失效，未提交";
        return WUSubmitEmoticonData(data,Service(@"CMessageMgr"),account,target,current);
    };
    WUShowEmoticonLibrary(owner,binding);
}
