// Persist only our schema. Unknown/corrupt values remain intact for explicit user repair.
static NSDictionary *FPHomeRecord(id value) {
    if(!value) return @{ @"schema":@1, @"mode":@"defaultDownloads" };
    if([value isKindOfClass:NSData.class]) return @{ @"schema":@1, @"mode":@"custom", @"bookmark":value };
    if(![value isKindOfClass:NSDictionary.class] || ![value[@"schema"] isEqual:@1]) return nil;
    NSString *mode=value[@"mode"];
    if([mode isEqual:@"browse"] || [mode isEqual:@"defaultDownloads"]) return value;
    if([mode isEqual:@"custom"] && [value[@"bookmark"] isKindOfClass:NSData.class]) return value;
    return nil;
}
static BOOL FPHomeMayContinue(NSUInteger generation, NSUInteger current, BOOL attached, BOOL touched, NSUInteger attempts) {
    return generation==current && attached && !touched && attempts<20;
}
// A root flag alone is insufficient: provider roots are real folders, not Browse.
static BOOL FPHomeIsBrowse(BOOL visibleSidebar, BOOL matchesBrowseLocation) {
    return visibleSidebar || matchesBrowseLocation;
}
static BOOL FPHomeCanCommit(BOOL bookmarkValid, NSUInteger savedGeneration, NSUInteger currentGeneration) {
    return bookmarkValid && savedGeneration==currentGeneration;
}

static BOOL FPHomeLocationUnchanged(id before,id now) { return before==now || [before isEqual:now]; }
