static NSDictionary *SnapshotRecord(NSDictionary *report, NSNumber *identity) {
    assert(identity.unsignedIntegerValue && identity.unsignedIntegerValue<=[report[@"objects"] count]);
    return report[@"objects"][identity.unsignedIntegerValue-1];
}
static void AssertReferences(NSDictionary *report) {
    NSUInteger count=[report[@"objects"] count];
    for(NSNumber *key in [report[@"roles"] allValues]) assert(key.unsignedIntegerValue<=count);
    for(NSDictionary *record in report[@"objects"]) {
        assert([record[@"id"] unsignedIntegerValue]<=count);
        for(NSString *name in @[@"super",@"owner"]) assert([record[name] unsignedIntegerValue]<=count);
        for(NSNumber *key in record[@"guides"]) assert(key.unsignedIntegerValue<=count);
        for(NSDictionary *entry in record[@"stack"][@"arranged"]) assert([entry[@"view"] unsignedIntegerValue]<=count);
    }
    for(NSDictionary *c in report[@"activeConstraints"]) for(NSString *name in @[@"owner",@"first",@"second"]) assert([c[name] unsignedIntegerValue]<=count);
}
static void SnapshotCases(void) {
    nativeReentry=nil;
    NativeFixture *f=Native();
    // Object getters may return private strings: only anonymous identity/type may escape.
    f.cell.cellContent=@"PRIVATE_GETTER_VALUE file:///PRIVATE_URL_SENTINEL";
    f.title.text=@"PRIVATE_FILE_SENTINEL…pdf";
    f.detail.text=@"PRIVATE_ACCOUNT_SENTINEL";
    UILabel *date=[UILabel new]; date.text=@"PRIVATE_DATE_SENTINEL 2026-10-28"; [f.row.arrangedSubviews[1] addSubview:date]; f.cell.dateLabel=date;
    f.title.attributedText=[[NSAttributedString alloc] initWithString:@"PRIVATE_ATTRIBUTED_SENTINEL..."];
    f.sizes[0].identifier=@"/PRIVATE_PATH_SENTINEL";
    f.edges[0].identifier=@"UISV-spacing";
    FPStyleVisibleCell(f.cell); FPStyleVisibleCell(f.cell);
    int nw=nativeWrites,w=writes,aw=accessoryWrites,bw=backgroundWrites,rq=readyQueued;
    NSDictionary *report=FPLCell(f.cell,@"file");
    assert(nativeWrites==nw && writes==w && accessoryWrites==aw && backgroundWrites==bw && readyQueued==rq);
    assert([report[@"styleResult"][@"native"] boolValue]);
    assert([report[@"lastNativeDecision"][@"cache"] hasPrefix:@"hit_"]);
    assert(report[@"lastNativeDecision"][@"planDecision"][@"geometry"]);
    assert(report[@"lastNativeDecision"][@"planDecision"][@"trailingReject"]);
    NSDictionary *title=SnapshotRecord(report,report[@"roles"][@"accessibilityTitleLabel"]);
    NSDictionary *dateRecord=SnapshotRecord(report,report[@"roles"][@"accessibilityDateLabel"]);
    assert([title[@"text"][@"length"] unsignedIntegerValue]==f.title.text.length);
    assert([title[@"text"][@"containsEllipsis"] boolValue]);
    assert([dateRecord[@"text"][@"length"] unsignedIntegerValue]==date.text.length);
    assert(![dateRecord[@"text"][@"containsEllipsis"] boolValue]);
    assert([report[@"getters"][@"accessibilityTitleLabel"][@"object"] isEqual:report[@"roles"][@"accessibilityTitleLabel"]]);
    assert([title[@"class"] isEqual:@"UILabel"] && [title[@"isa"] isEqual:@"UILabel"]);
    AssertReferences(report);
    NSData *data=[NSJSONSerialization dataWithJSONObject:report options:0 error:nil]; assert(data);
    NSString *json=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    for(NSString *secret in @[@"PRIVATE_",@"2026-10-28",@"A long provider filename",@"0x"]) assert(![json containsString:secret]);
    assert([json containsString:@"redacted"] && [json containsString:@"UISV-spacing"]);
    NativeFixture *wrong=Native(); NSDictionary *wrongReport=FPLCell(wrong.cell,@"folder");
    assert([wrongReport[@"getters"][@"accessibilityDateLabel"][@"status"] isEqual:@"wrong_runtime_type"]);
    Class bad=NamedClass(@"SnapshotBadABI",NSClassFromString(@"Files.DOCItemCollectionListCell"));
    class_addMethod(bad,NSSelectorFromString(@"accessibilityTitleLabel"),imp_implementationWithBlock(^NSInteger(id self){ assert(0); return 3; }),"q@:");
    UICollectionViewCell *badCell=NewCell(bad); NSDictionary *badReport=FPLCell(badCell,@"unknown");
    assert([badReport[@"getters"][@"accessibilityTitleLabel"][@"status"] isEqual:@"abi_mismatch"]);
    assert([wrongReport[@"getters"][@"accessibilitySizeLabel"][@"status"] isEqual:@"nil"]);
    assert([wrongReport[@"lastNativeDecision"][@"status"] isEqual:@"not_observed"]);
    FPStyleVisibleCell(badCell);
    badReport=FPLCell(badCell,@"unknown");
    assert([badReport[@"styleResult"][@"unsupported"] boolValue]);
    assert([badReport[@"lastNativeDecision"][@"nativeGate"] isEqual:@"FPCompactNative_05"]);
    assert([badReport[@"lastNativeDecision"][@"geometry"] isEqual:@"not_reached"]);
    assert([badReport[@"reasonMeanings"][@"FPCompactNative_05"] isEqual:@"identity_getter_missing_or_abi_or_type"]);
    assert([badReport[@"decisionTiming"] isEqual:@"last_normal_style_event_not_replayed_for_capture"]);
    NativeFixture *large=Native();
    for(NSUInteger i=0;i<240;i++) [large.cell.contentView addSubview:[UIView new]];
    for(NSUInteger i=0;i<700;i++) Constraint(large.cell.contentView,large.title,NSLayoutAttributeWidth,nil,0,80);
    NSDictionary *bounded=FPLCell(large.cell,@"file");
    assert([bounded[@"budget"][@"truncated"] boolValue]);
    assert([bounded[@"budget"][@"views"] unsignedIntegerValue]<=100 && [bounded[@"activeConstraints"] count]<=500);
    assert([bounded[@"budget"][@"constraintInspections"] unsignedIntegerValue]<=2000);
    for(NSString *role in @[@"cell",@"contentView",@"accessibilityTitleLabel",@"thumbnailSlot",@"row",@"textSlot"]) {
        NSDictionary *geometry=SnapshotRecord(bounded,bounded[@"roles"][role]);
        assert([geometry[@"detail"] isEqual:@"view"] && [geometry[@"bounds"] count]==4);
    }
    AssertReferences(bounded);
    puts("PASS snapshot privacy no-getter-value; captured unsupported rejection stage/reason; geometry budget prioritizes title/slot/row/contentView");
    puts("PASS production snapshot schema: anonymous date/title, actual getter ids/ABI, connected endpoints, fixed identifier allowlist, 100 views/500 constraints cap, cache original proof, zero layout/selection writes");
    puts("LIMIT synthetic objects validate capture privacy/schema only; no actual device width constraint or UI rendering was measured");
}
