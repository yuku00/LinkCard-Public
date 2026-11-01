// Included once by Messages.m; uses its existing checked host adapters and account/session generation.
static void OpenSelectedLinks(UIViewController *owner) {
    if(!WUEnabled(@"enhancedLinks")) return;
    NSString *account=Account(), *session=Session(owner); NSUInteger gen=generation;
    id selected=Obj(owner,@"getSelectedMsgs");
    if(![selected isKindOfClass:NSArray.class] || ![selected count] || [selected count]>20) { Notice(owner,@"请先使用微信原长按菜单→多选，选择1–20条消息，再从聊天页工具中打开“所选消息链接”。不会读取未选择的消息。"); return; }
    if(!account.length || !session.length) { Notice(owner,@"无法核验账号或会话，已取消。"); return; }
    NSArray *wraps=[selected copy]; NSMutableArray *identities=[NSMutableArray array], *contents=[NSMutableArray array];
    NSUInteger total=0;
    for(id wrap in wraps) {
        NSDictionary *identity=Info(wrap); NSString *content=Str(wrap,@"m_nsContent")?:@"";
        if(!InSession(identity,account,session) || (![identity[@"id"] unsignedLongLongValue] && ![identity[@"local"] unsignedLongLongValue]) || content.length>8192 || (total+=content.length)>65536) { Notice(owner,@"选择包含不可核验或超长消息，本次未读取链接。"); return; }
        [identities addObject:identity]; [contents addObject:@{@"type":identity[@"type"],@"content":content}];
    }
    __weak UIViewController *weak=owner;
    BOOL (^current)(void)=^BOOL {
        @try {
            UIViewController *v=weak;
            if(!v || (!v.viewIfLoaded.window && !WUMessageEntriesOwnsController(v.presentedViewController)) || (v.navigationController && v.navigationController.topViewController!=v) || !WUEnabled(@"enhancedLinks") || ![account isEqual:Account()] || gen!=generation || ![session isEqual:Session(v)] || ![WUToolbarActions(WUAccountOptions(account)[@"toolbar"]) containsObject:@"messageLinks"]) return NO;
            id now=Obj(v,@"getSelectedMsgs"); if(![now isKindOfClass:NSArray.class] || [now count]!=wraps.count) return NO;
            for(NSUInteger i=0;i<wraps.count;i++) if(now[i]!=wraps[i] || ![Info(wraps[i]) isEqual:identities[i]] || ![(Str(wraps[i],@"m_nsContent")?:@"") isEqual:contents[i][@"content"]]) return NO;
            return YES;
        } @catch(__unused NSException *e) { return NO; }
    };
    WUOpenSelectedLinks(owner,[contents copy],current);
}
static void DownloadRepeat(UIView *cell) {
    if(!WUEnabled(@"repeatEmoticon") || ![(WUValue(@"repeatOptions")?:WURepeatDefaults())[@"longDownload"] boolValue]) return;
    UIViewController *owner=Chat(cell); if(!owner || owner.presentedViewController) return;
    id wrap=Wrap(cell); NSDictionary *identity=Info(wrap); NSString *account=Account(), *session=Session(owner); NSUInteger gen=generation;
    if(!account.length || !session.length || [identity[@"type"] unsignedIntegerValue]!=47 || !InSession(identity,account,session) || (![identity[@"id"] unsignedLongLongValue] && ![identity[@"local"] unsignedLongLongValue])) { Notice(owner,@"表情消息或会话身份不可核验，未下载。"); return; }
    NSString *md5=Str(wrap,@"m_nsEmoticonMD5")?:Str(Obj(wrap,@"m_extendInfoWithMsgType"),@"m_nsEmoticonMD5");
    Class util=NSClassFromString(@"EmoticonUtil"); NSString *selector=@"pathOfEmoticonForMd5:needUpdateTime:ignoreWxAM:";
    if(!WUValidMD5(md5) || !Has(util,selector,"@",@[@"@",@"B",@"B"])) { Notice(owner,@"原表情路径接口不可用或签名不匹配，未下载；不使用缩略图替代。"); return; }
    NSString *path=((id(*)(id,SEL,id,BOOL,BOOL))objc_msgSend)(util,NSSelectorFromString(selector),md5,NO,NO);
    if(![path isKindOfClass:NSString.class] || !path.length) { Notice(owner,@"没有可得的原表情文件，未下载；不自动请求网络媒体。"); return; }
    __weak UIView *weakCell=cell; __weak UIViewController *weakOwner=owner;
    BOOL (^current)(void)=^BOOL {
        @try {
            UIView *target=weakCell; UIViewController *v=weakOwner;
            if(!target || !v || (!target.window && !WUMessageEntriesOwnsController(v.presentedViewController)) || (v.navigationController && v.navigationController.topViewController!=v) || Wrap(target)!=wrap || ![Info(wrap) isEqual:identity] || ![account isEqual:Account()] || gen!=generation || ![session isEqual:Session(v)] || !WUEnabled(@"repeatEmoticon") || ![(WUValue(@"repeatOptions")?:WURepeatDefaults())[@"longDownload"] boolValue]) return NO;
            NSString *now=Str(wrap,@"m_nsEmoticonMD5")?:Str(Obj(wrap,@"m_extendInfoWithMsgType"),@"m_nsEmoticonMD5");
            return [md5 isEqual:now];
        } @catch(__unused NSException *e) { return NO; }
    };
    WUExportEmoticon(owner,[path copy],current);
}
