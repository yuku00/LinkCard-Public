// Candidate decision only: no hooks, cached identities, or changes to host arrays.
// Unknown must never be treated as hidden, nor as permission for a row action.
typedef NS_ENUM(NSInteger, WUHomeLiveDecision) {
    WUHomeLiveUnknown = 0, WUHomeLiveVisible, WUHomeLiveHidden
};

WUHomeLiveDecision WUHomeLiveRowDecision(id controller, UITableView *table, NSIndexPath *path) {
    if(!NSThread.isMainThread || !controller || ![table isKindOfClass:UITableView.class] ||
       ![path isKindOfClass:NSIndexPath.class] || path.length != 2 || path.section < 0 || path.row < 0 ||
       ![controller isKindOfClass:NSClassFromString(@"NewMainFrameViewController")]) return WUHomeLiveUnknown;
    @try {
        SEL countSel=NSSelectorFromString(@"logicGetCountForSection:");
        SEL rowSel=NSSelectorFromString(@"logicGetSessionAtIndexPath:");
        SEL reverseSel=NSSelectorFromString(@"indexPathOfSessionUserName:");
        Class cls=object_getClass(controller);
        if(!WUMatches(class_getInstanceMethod(cls,countSel),"q",@[@"q"]) ||
           !WUMatches(class_getInstanceMethod(cls,rowSel),"@",@[@"@"]) ||
           !WUMatches(class_getInstanceMethod(cls,reverseSel),"@",@[@"@"]) ||
           Obj(controller,@"m_tableView")!=table) return WUHomeLiveUnknown;
        BOOL searching=NO;
        if(!Flag(controller,@"isSearching",&searching) || searching || path.section>=table.numberOfSections) return WUHomeLiveUnknown;
        NSString *account=[WUCurrentAccount() copy]; id manager=CurrentManager();
        NSUInteger generation=WUContextGeneration();
        if(!account.length || !manager || ![WUValue(@"enabled") boolValue]) return WUHomeLiveUnknown;
        NSDictionary *state=State(account);
        if(!WUValidHomeGroups(state) || ![state[@"enabled"] boolValue]) return WUHomeLiveUnknown;
        long long count=((long long(*)(id,SEL,long long))objc_msgSend)(controller,countSel,(long long)path.section);
        if(count<0 || path.row>=count) return WUHomeLiveUnknown;
        id first=((id(*)(id,SEL,id))objc_msgSend)(controller,rowSel,path);
        NSDictionary *row=Row(first);
        if(!row) return WUHomeLiveUnknown;
        id reverse=((id(*)(id,SEL,id))objc_msgSend)(controller,reverseSel,row[@"username"]);
        if(![reverse isKindOfClass:NSIndexPath.class] || ![reverse isEqual:path]) return WUHomeLiveUnknown;
        NSArray *indexes=WUHomeIndexes(@[row],state);
        if(!indexes) return WUHomeLiveUnknown;
        id second=((id(*)(id,SEL,id))objc_msgSend)(controller,rowSel,path);
        NSDictionary *again=Row(second);
        BOOL searchingAgain=NO;
        if(first!=second || ![row isEqual:again] ||
           count!=((long long(*)(id,SEL,long long))objc_msgSend)(controller,countSel,(long long)path.section) ||
           Obj(controller,@"m_tableView")!=table || !Flag(controller,@"isSearching",&searchingAgain) || searchingAgain ||
           manager!=CurrentManager() || generation!=WUContextGeneration() || ![account isEqual:WUCurrentAccount()] ||
           ![WUValue(@"enabled") boolValue] || ![state isEqual:State(account)]) return WUHomeLiveUnknown;
        return indexes.count ? WUHomeLiveVisible : WUHomeLiveHidden;
    } @catch(__unused NSException *e) { return WUHomeLiveUnknown; }
}
