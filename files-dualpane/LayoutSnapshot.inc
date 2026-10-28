// Explicit single-use capture. UI reads only on main; no file contents, images or layout setters.
static NSString *FPLayoutLastReport;
static BOOL FPLayoutBusy;
static NSDictionary *FPLText(NSString *text) {
    return @{@"length":@(text.length),@"containsEllipsis":@([text containsString:@"…"] || [text containsString:@"..."])};
}
static id FPLNumber(CGFloat n) { return isfinite(n) ? @(n) : (id)NSNull.null; }
static NSArray *FPLRect(CGRect r) { return @[FPLNumber(r.origin.x),FPLNumber(r.origin.y),FPLNumber(r.size.width),FPLNumber(r.size.height)]; }
static NSArray *FPLSize(CGSize s) { return @[FPLNumber(s.width),FPLNumber(s.height)]; }
static NSString *FPLClass(id o, BOOL isa) { return o ? NSStringFromClass(isa ? object_getClass(o) : [o class]) : @"nil"; }
@interface FPLayoutGraph : NSObject
@property(nonatomic,strong) NSMutableArray *objects;
@property(nonatomic,strong) NSMutableArray *records;
@property(nonatomic,strong) NSMutableArray *views;
@property(nonatomic,strong) NSMutableArray *constraints;
@property(nonatomic,strong) NSMutableSet *seenConstraints;
@property(nonatomic,strong) UICollectionViewCell *cell;
@property(nonatomic) NSUInteger inspected;
@property(nonatomic) BOOL truncated;
@end
@implementation FPLayoutGraph
- (instancetype)init { if((self=[super init])) { _objects=[NSMutableArray new]; _records=[NSMutableArray new]; _views=[NSMutableArray new]; _constraints=[NSMutableArray new]; _seenConstraints=[NSMutableSet new]; } return self; }
- (NSNumber *)identity:(id)object {
    if(!object) return @0;
    NSUInteger i=[self.objects indexOfObjectIdenticalTo:object];
    if(i!=NSNotFound) return @(i+1);
    if(self.objects.count>=400) { self.truncated=YES; return @0; }
    [self.objects addObject:object]; NSNumber *key=@(self.objects.count);
    [self.records addObject:[@{@"id":key,@"class":FPLClass(object,NO),@"isa":FPLClass(object,YES),@"detail":@"reference_only"} mutableCopy]];
    return key;
}
- (void)queue:(id)object {
    [self identity:object];
    if(![object isKindOfClass:UIView.class] || [self.views containsObject:object]) return;
    if(self.views.count>=100) { self.truncated=YES; return; }
    [self.views addObject:object];
}
- (void)chain:(UIView *)view {
    for(NSUInteger depth=0;view && depth<16;depth++,view=view.superview) {
        [self queue:view]; if(view==self.cell) return;
    }
    if(view) self.truncated=YES;
}
- (void)guide:(UILayoutGuide *)guide {
    NSNumber *key=[self identity:guide]; if(!key.unsignedIntegerValue) return;
    NSMutableDictionary *record=self.records[key.unsignedIntegerValue-1];
    record[@"detail"]=@"guide"; record[@"owner"]=[self identity:guide.owningView];
    record[@"layoutFrame"]=FPLRect(guide.layoutFrame);
    if(guide.owningView.window==self.cell.window) record[@"frameInCell"]=FPLRect([guide.owningView convertRect:guide.layoutFrame toView:self.cell]);
    // Guide identifiers can contain provider names: export only the known role.
    record[@"role"]=guide==guide.owningView.layoutMarginsGuide ? @"layoutMargins" : guide==guide.owningView.safeAreaLayoutGuide ? @"safeArea" : @"other";
    [self queue:guide.owningView];
}
- (void)endpoint:(id)item {
    if([item isKindOfClass:UILayoutGuide.class]) [self guide:item];
    else if([item isKindOfClass:UIView.class]) [self queue:item];
    else [self identity:item];
}
- (void)constraintsOf:(UIView *)view {
    for(NSLayoutConstraint *c in view.constraints) {
        if(self.inspected>=2000 || self.constraints.count>=500) { self.truncated=YES; return; }
        self.inspected++;
        if(!c.active || [self.seenConstraints containsObject:c]) continue;
        [self.seenConstraints addObject:c]; [self endpoint:c.firstItem]; [self endpoint:c.secondItem];
        NSString *identifier=@"redacted";
        if(!c.identifier.length) identifier=@"none";
        else if([@[@"UISV-spacing",@"UISV-alignment",@"UISV-canvas-connection",@"UISV-hiding",@"UIView-Encapsulated-Layout-Width",@"UIView-Encapsulated-Layout-Height"] containsObject:c.identifier]) identifier=c.identifier;
        [self.constraints addObject:@{@"owner":[self identity:view],@"first":[self identity:c.firstItem],@"second":[self identity:c.secondItem],@"firstAttribute":@(c.firstAttribute),@"secondAttribute":@(c.secondAttribute),@"relation":@(c.relation),@"multiplier":FPLNumber(c.multiplier),@"constant":FPLNumber(c.constant),@"priority":FPLNumber(c.priority),@"active":@YES,@"identifier":identifier}];
    }
}
- (void)describeView:(UIView *)v {
    NSNumber *key=[self identity:v]; if(!key.unsignedIntegerValue) return;
    NSMutableDictionary *record=self.records[key.unsignedIntegerValue-1];
    record[@"detail"]=@"view"; record[@"super"]=[self identity:v.superview];
    record[@"bounds"]=FPLRect(v.bounds); record[@"frame"]=FPLRect(v.frame);
    if(v.window==self.cell.window) record[@"frameInCell"]=FPLRect([v convertRect:v.bounds toView:self.cell]);
    record[@"intrinsicSize"]=FPLSize(v.intrinsicContentSize);
    record[@"hugging"]=@[@([v contentHuggingPriorityForAxis:UILayoutConstraintAxisHorizontal]),@([v contentHuggingPriorityForAxis:UILayoutConstraintAxisVertical])];
    record[@"compression"]=@[@([v contentCompressionResistancePriorityForAxis:UILayoutConstraintAxisHorizontal]),@([v contentCompressionResistancePriorityForAxis:UILayoutConstraintAxisVertical])];
    record[@"translatesAutoresizingMaskIntoConstraints"]=@(v.translatesAutoresizingMaskIntoConstraints);
    record[@"hidden"]=@(v.hidden); record[@"alpha"]=FPLNumber(v.alpha);
    NSDirectionalEdgeInsets m=v.directionalLayoutMargins;
    record[@"margins"]=@[FPLNumber(m.top),FPLNumber(m.leading),FPLNumber(m.bottom),FPLNumber(m.trailing)];
    record[@"preservesSuperviewLayoutMargins"]=@(v.preservesSuperviewLayoutMargins);
    record[@"layoutDirection"]=@(v.effectiveUserInterfaceLayoutDirection);
    if([v isKindOfClass:UILabel.class]) {
        UILabel *label=(id)v; record[@"text"]=FPLText(label.text); record[@"attributedText"]=FPLText(label.attributedText.string);
        record[@"fontSize"]=FPLNumber(label.font.pointSize); record[@"numberOfLines"]=@(label.numberOfLines); record[@"lineBreak"]=@(label.lineBreakMode);
        record[@"adjustsFontSizeToFitWidth"]=@(label.adjustsFontSizeToFitWidth); record[@"minimumScaleFactor"]=FPLNumber(label.minimumScaleFactor);
    }
    if([v isKindOfClass:UIStackView.class]) {
        UIStackView *stack=(id)v; NSMutableArray *arranged=[NSMutableArray new];
        for(UIView *item in stack.arrangedSubviews) {
            if(arranged.count>=100) { self.truncated=YES; break; }
            [self queue:item]; [arranged addObject:@{@"view":[self identity:item],@"customSpacingAfter":FPLNumber([stack customSpacingAfterView:item])}];
        }
        record[@"stack"]=@{@"axis":@(stack.axis),@"distribution":@(stack.distribution),@"alignment":@(stack.alignment),@"spacing":FPLNumber(stack.spacing),@"marginsRelative":@(stack.layoutMarginsRelativeArrangement),@"arranged":arranged};
    }
    NSMutableArray *guides=[NSMutableArray new];
    for(UILayoutGuide *guide in v.layoutGuides) { if(guides.count>=32) { self.truncated=YES; break; } [self guide:guide]; [guides addObject:[self identity:guide]]; }
    record[@"guides"]=guides;
}
@end
static NSDictionary *FPLReasonMeanings(void) { return @{
@"FPNativeStateMatches_01":@"identity_size_margins_or_font_changed",
@"FPNativeStateMatches_02":@"pending_view_became_ready",
@"FPNativeStateMatches_03":@"layout_direction_changed",
@"FPNativeStateMatches_04":@"accessories_changed",
@"FPNativeStateMatches_05":@"watched_stack_changed",
@"FPNativeStateMatches_06":@"watched_constraint_changed",
@"FPNativeStateMatches_07":@"thumbnail_spacing_changed",
@"FPNativeStateMatches_08":@"applied_constraint_changed",
@"FPNativeStateMatches_09":@"label_geometry_font_or_lines_changed",
@"FPPlanDimension_01":@"autoresizing_mask",
@"FPPlanDimension_02":@"unsupported_dimension_link",
@"FPPlanDocumentDimensions_01":@"aspect_or_autoresizing_unsupported",
@"FPPlanDocumentDimensions_02":@"dimension_relation_or_multiplier_unsupported",
@"FPPlanDocumentDimensions_03":@"dimension_equation_not_proved",
@"FPPlanEdges_01":@"row_width_or_physical_edge_constraint",
@"FPPlanEdges_02":@"root_edge_equation_not_proved",
@"FPTextWidthPlan_01":@"width_not_known_fixed_or_max_constant",
@"FPTrailingPath_01":@"path_depth_budget",
@"FPTrailingPath_02":@"outside_content_root",
@"FPTrailingPath_03":@"width_plan_rejected",
@"FPTrailingPath_04":@"edge_relation_or_boundary_not_proved",
@"FPTrailingPath_05":@"sibling_nonzero_offset",
@"FPTrailingPath_06":@"multiple_trailing_edges",
@"FPTrailingPath_07":@"no_edge_or_vertical_fill_witness",
@"FPTrailingPath_08":@"provider_width_ambiguous_or_nonconstant",
@"FPTrailingPath_09":@"provider_width_missing",
@"FPTrailingPath_10":@"provider_tail_not_proved",
@"FPTrailingPath_11":@"ancestor_path_rejected",
@"FPPlanTrailing_01":@"not_left_to_right",
@"FPPlanTrailing_02":@"row_or_text_slot_path_rejected",
@"FPPlanTrailing_03":@"unproved_trailing_arranged_provider",
@"FPCompactNative_01":@"outside_compact_scope",
@"FPCompactNative_02":@"not_item_controller_or_sidebar",
@"FPCompactNative_03":@"unsupported_cell_class",
@"FPCompactNative_04":@"renaming_or_renaming_abi_mismatch",
@"FPCompactNative_05":@"identity_getter_missing_or_abi_or_type",
@"FPCompactNative_06":@"title_or_image_outside_content",
@"FPCompactNative_07":@"row_slot_distribution_height_or_margins",
@"FPCompactNative_08":@"label_height_insufficient",
@"FPCompactNative_09":@"no_ready_labels_or_document_aspect",
@"FPCompactNative_10":@"geometry_and_trailing_both_rejected",
@"FPCompactNative_11":@"no_image_only_fallback_or_labels",
@"FPPlanEdges_missing_edge":@"root_leading_or_trailing_missing"}; }
static id FPLGetter(id object, NSString *name, Class expected, FPLayoutGraph *graph, NSMutableDictionary *getters) {
    NSMutableDictionary *entry=[NSMutableDictionary new]; getters[name]=entry;
    if(!class_getInstanceMethod(object_getClass(object),NSSelectorFromString(name))) { entry[@"status"]=@"missing"; return nil; }
    if(!ABI(object_getClass(object),name,"@@:")) { entry[@"status"]=@"abi_mismatch"; return nil; }
    @try {
        id value=FPNativeGet(object,name);
        entry[@"status"]=!value ? @"nil" : expected && ![value isKindOfClass:expected] ? @"wrong_runtime_type" : @"ok";
        entry[@"object"]=[graph identity:value]; entry[@"class"]=FPLClass(value,NO); entry[@"isa"]=FPLClass(value,YES);
        return !expected || [value isKindOfClass:expected] ? value : nil;
    } @catch(NSException *exception) { entry[@"status"]=@"getter_exception"; return nil; }
}
static UIView *FPLThumbnail(UIView *root) {
    if(!root) return nil;
    NSMutableArray *queue=[NSMutableArray arrayWithObject:@[root,@0]]; UIView *match=nil;
    for(NSUInteger i=0;i<queue.count && i<32;i++) {
        UIView *v=queue[i][0]; NSUInteger depth=[queue[i][1] unsignedIntegerValue];
        if(FPClassInChain(v,@"DOCThumbnailFittingImageView") || FPClassInChain(v,@"DOCFittingImageView")) { if(match) return nil; match=v; continue; }
        if(depth>=4) continue;
        for(UIView *child in v.subviews) { if(queue.count>=32) return nil; [queue addObject:@[child,@(depth+1)]]; }
    }
    return match;
}
static NSDictionary *FPLCell(UICollectionViewCell *cell, NSString *kind) {
    FPLayoutGraph *graph=[FPLayoutGraph new]; graph.cell=cell;
    NSMutableDictionary *getters=[NSMutableDictionary new], *roles=[NSMutableDictionary new];
    roles[@"cell"]=[graph identity:cell]; roles[@"contentView"]=[graph identity:cell.contentView];
    [graph queue:cell]; [graph queue:cell.contentView];
    id content=cell.contentConfiguration;
    NSMutableDictionary *publicContent=[@{@"class":FPLClass(content,NO),@"isa":FPLClass(content,YES),@"supported":@([content isKindOfClass:UIListContentConfiguration.class])} mutableCopy];
    if([content isKindOfClass:UIListContentConfiguration.class]) {
        UIListContentConfiguration *c=content;
        publicContent[@"title"]=FPLText(c.text); publicContent[@"subtitle"]=FPLText(c.secondaryText);
        publicContent[@"attributedTitle"]=FPLText(c.attributedText.string); publicContent[@"attributedSubtitle"]=FPLText(c.secondaryAttributedText.string);
        publicContent[@"fits"]=@(FPPublicFits(c,cell)); publicContent[@"configurationMatches"]=@(FPCompactConfigurationMatches(c,cell));
        publicContent[@"fontSizes"]=@[FPLNumber(c.textProperties.font.pointSize),FPLNumber(c.secondaryTextProperties.font.pointSize)];
        publicContent[@"numberOfLines"]=@[@(c.textProperties.numberOfLines),@(c.secondaryTextProperties.numberOfLines)];
        publicContent[@"lineBreak"]=@[@(c.textProperties.lineBreakMode),@(c.secondaryTextProperties.lineBreakMode)];
    }
    UIView *title=nil, *thumbnail=nil;
    for(NSString *name in @[@"accessibilityTitleLabel",@"accessibilitySubtitleLabel",@"accessibilityDateLabel",@"accessibilitySizeLabel",@"accessibilityThumbnailView",@"cellContent"]) {
        Class expected=[name isEqual:@"cellContent"] ? Nil : [name isEqual:@"accessibilityThumbnailView"] ? UIView.class : UILabel.class;
        id value=FPLGetter(cell,name,expected,graph,getters); roles[name]=[graph identity:value];
        if([value isKindOfClass:UIView.class]) [graph chain:value];
        if([name isEqual:@"accessibilityTitleLabel"]) title=value;
        if([name isEqual:@"accessibilityThumbnailView"]) thumbnail=value;
    }
    UIView *image=FPLThumbnail(thumbnail), *slot=nil; UIStackView *row=nil;
    for(UIView *v=image;v && v!=cell.contentView;v=v.superview) {
        if([v.superview isKindOfClass:UIStackView.class]) { UIStackView *s=(id)v.superview; if(s.axis==UILayoutConstraintAxisHorizontal && [s.arrangedSubviews containsObject:v]) { slot=v; row=s; break; } }
    }
    UIView *textSlot=row ? FPArrangedSlot(title,row) : nil;
    roles[@"imageView"]=[graph identity:image]; roles[@"thumbnailSlot"]=[graph identity:slot]; roles[@"row"]=[graph identity:row]; roles[@"textSlot"]=[graph identity:textSlot];
    [graph chain:image]; [graph chain:textSlot];
    // Ancestor/getter geometry and connected constraints precede the small remaining subtree.
    [graph queue:cell.superview];
    for(NSUInteger i=0;i<graph.views.count && i<100;i++) {
        UIView *v=graph.views[i]; [graph describeView:v]; [graph constraintsOf:v];
    }
    for(NSUInteger i=0;i<graph.views.count && i<100;i++) {
        UIView *v=graph.views[i];
        if(v!=cell && ![v isDescendantOfView:cell]) continue;
        for(UIView *child in v.subviews) { if(graph.views.count>=100) { graph.truncated=YES; break; } [graph queue:child]; }
        [graph describeView:v]; [graph constraintsOf:v];
    }
    // Endpoint nodes added late still get geometry; constraint budgets are shared.
    for(NSUInteger i=0;i<graph.views.count;i++) [graph describeView:graph.views[i]];
    NSDictionary *native=objc_getAssociatedObject(cell,&FPNativeStyleKey);
    NSDictionary *decision=objc_getAssociatedObject(cell,&FPLayoutDecisionKey);
    NSMutableDictionary *cache=[@{@"present":@(native!=nil),@"trailingApplied":@([native[@"trailing"] boolValue]),@"geometryApplied":@([native[@"geometry"] boolValue]),@"textPending":@([native[@"textPending"] boolValue]),@"readyTicketPresent":@(objc_getAssociatedObject(cell,&FPNativeReadyKey)!=nil)} mutableCopy];
    NSMutableArray *pending=[NSMutableArray new]; for(UIView *v in native[@"pendingViews"]) [pending addObject:[graph identity:v]]; cache[@"pendingViews"]=pending;
    NSMutableArray *accessories=[NSMutableArray new];
    if([cell isKindOfClass:UICollectionViewListCell.class]) for(id item in [(UICollectionViewListCell *)cell accessories]) { if(accessories.count>=16) { graph.truncated=YES; break; } [accessories addObject:@{@"class":FPLClass(item,NO),@"isa":FPLClass(item,YES)}]; }
    NSUInteger bits=[objc_getAssociatedObject(cell,&FPStyleResultKey) unsignedIntegerValue];
    publicContent[@"gateAtCapture"]=(bits&FPStyleNativeApplied) ? @"native_path_owns_content" : ![content isKindOfClass:UIListContentConfiguration.class] ? @"unsupported_configuration_type" : !FPPublicFits(content,cell) ? @"height_insufficient" : @"public_fits";
    UICollectionView *collection=nil; for(UIView *v=cell.superview;v;v=v.superview) if([v isKindOfClass:UICollectionView.class]) { collection=(id)v; break; }
    return @{@"kind":kind,@"roles":roles,@"getters":getters,@"publicContent":publicContent,
        @"scope":@{@"isPaneListCell":@(IsPaneListCell(cell)),@"inPane":@(PaneForResponder(cell)!=nil),@"visible":@([collection.visibleCells containsObject:cell]),@"controllerClass":FPLClass(collection.delegate,NO),@"controllerISA":FPLClass(collection.delegate,YES),@"busy":@(objc_getAssociatedObject(cell,&FPCellBusyKey)!=nil),@"resetting":@(objc_getAssociatedObject(cell,&FPCellResettingKey)!=nil)},
        @"styleResult":@{@"bits":@(bits),@"public":@((bits&FPStylePublicApplied)!=0),@"native":@((bits&FPStyleNativeApplied)!=0),@"unsupported":@((bits&FPStyleContentUnsupported)!=0)},
        @"reasonMeanings":FPLReasonMeanings(),@"lastNativeDecision":decision ?: @{@"status":@"not_observed"},@"decisionTiming":@"last_normal_style_event_not_replayed_for_capture",@"nativeCache":cache,@"accessories":accessories,
        @"objects":graph.records,@"activeConstraints":graph.constraints,@"budget":@{@"views":@(graph.views.count),@"constraints":@(graph.constraints.count),@"constraintInspections":@(graph.inspected),@"truncated":@(graph.truncated)}};
}
@interface FPLayoutReport : UIViewController
@property(nonatomic,copy) NSString *text;
@end
@implementation FPLayoutReport
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"只读布局报告";
    UITextView *text=[[UITextView alloc] initWithFrame:self.view.bounds]; text.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    text.editable=NO; text.selectable=YES; text.text=self.text; text.font=[UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular]; [self.view addSubview:text];
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:@"返回双栏" style:UIBarButtonItemStylePlain target:self action:@selector(done)];
    self.navigationItem.rightBarButtonItems=@[[[UIBarButtonItem alloc] initWithTitle:@"分享" style:UIBarButtonItemStylePlain target:self action:@selector(share:)],[[UIBarButtonItem alloc] initWithTitle:@"复制" style:UIBarButtonItemStylePlain target:self action:@selector(copyReport)]];
}
- (void)done { [self.navigationController dismissViewControllerAnimated:YES completion:nil]; }
- (void)copyReport { UIPasteboard.generalPasteboard.string=self.text; }
- (void)share:(UIBarButtonItem *)sender {
    if(self.presentedViewController || !self.viewIfLoaded.window) return;
    UIActivityViewController *share=[[UIActivityViewController alloc] initWithActivityItems:@[self.text] applicationActivities:nil]; share.popoverPresentationController.barButtonItem=sender; [self presentViewController:share animated:YES completion:nil];
}
@end
static void FPLShow(FPDualContainer *container) {
    if(!FPLayoutLastReport || container.presentedViewController || container.closing || !container.viewIfLoaded.window) return;
    FPLayoutReport *report=[FPLayoutReport new]; report.text=FPLayoutLastReport;
    UINavigationController *navigation=[[UINavigationController alloc] initWithRootViewController:report]; navigation.modalPresentationStyle=UIModalPresentationFormSheet;
    [container presentViewController:navigation animated:YES completion:nil];
}
static NSURL *FPLURL(UICollectionViewCell *cell, UIView **thumbnail) {
    id root=FPNativeGet(cell,@"accessibilityThumbnailView");
    UIView *image=[root isKindOfClass:UIView.class] ? FPLThumbnail(root) : nil; if(thumbnail) *thumbnail=image;
    if(!FPClassInChain(image,@"DOCThumbnailFittingImageView")) return nil;
    NSURL *url=FPNodeURL(FPNativeGet(image,@"node"));
    if(!url) { id value=FPNativeGet(image,@"url"); if([value isKindOfClass:NSURL.class] && [value isFileURL]) url=value; }
    return url;
}
static void FPLCapture(FPDualContainer *container, NSUInteger paneIndex) {
    if(container.closing || !container.viewIfLoaded.window || paneIndex>=container.panes.count) { FPLayoutBusy=NO; return; }
    FPBrowserPane *pane=container.panes[paneIndex];
    UIViewController *controller=Get(FPFull(pane),@"currentItemCollectionViewController");
    if(!InExperiment(controller) || !controller.isViewLoaded) { FPLayoutBusy=NO; container.navigationItem.prompt=@"当前列表未就绪，未采集"; return; }
    NSMutableArray *collections=[NSMutableArray new], *queue=[NSMutableArray arrayWithObject:controller.view]; BOOL discoveryTruncated=NO;
    for(NSUInteger i=0;i<queue.count && i<64;i++) {
        UIView *v=queue[i]; if([v isKindOfClass:UICollectionView.class]) { if([(UICollectionView *)v delegate]==(id)controller) [collections addObject:v]; continue; }
        for(UIView *child in v.subviews) { if(queue.count>=64) { discoveryTruncated=YES; break; } [queue addObject:child]; }
    }
    NSMutableArray *candidates=[NSMutableArray new];
    for(UICollectionView *collection in collections) {
        NSArray *visible=[collection.visibleCells sortedArrayUsingComparator:^NSComparisonResult(UICollectionViewCell *a, UICollectionViewCell *b) { return [[collection indexPathForCell:a] compare:[collection indexPathForCell:b]]; }];
        for(UICollectionViewCell *cell in visible) {
            if(candidates.count>=24) { discoveryTruncated=YES; break; }
            if(!cell.window || cell.hidden || !CGRectIntersectsRect([cell convertRect:cell.bounds toView:collection],collection.bounds)) continue;
            UIView *thumbnail=nil; NSURL *url=nil;
            @try { url=FPLURL(cell,&thumbnail); } @catch(NSException *exception) { /* No exception text. */ }
            NSIndexPath *path=[collection indexPathForCell:cell]; if(!path) continue;
            [candidates addObject:@{@"cell":cell,@"collection":collection,@"indexPath":path,@"url":url ?: NSNull.null,@"thumbnail":thumbnail ?: NSNull.null}];
        }
    }
    if(!candidates.count) { FPLayoutBusy=NO; container.navigationItem.prompt=@"没有可见文件列表单元格，未采集"; return; }
    BOOL truncated=discoveryTruncated;
    // Metadata only, at most 24 already-visible URLs. No enumeration, coordination or download.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSMutableArray *chosen=[NSMutableArray new], *unknown=[NSMutableArray new]; NSUInteger files=0, folders=0;
        for(NSDictionary *candidate in candidates) {
            NSString *kind=@"unknown"; id url=candidate[@"url"];
            if([url isKindOfClass:NSURL.class]) {
                @try {
                    NSDictionary *values=[url resourceValuesForKeys:@[NSURLIsDirectoryKey,NSURLIsRegularFileKey,NSURLIsSymbolicLinkKey] error:nil];
                    if([values[NSURLIsSymbolicLinkKey] boolValue]) kind=@"other";
                    else if([values[NSURLIsDirectoryKey] boolValue]) kind=@"folder";
                    else if([values[NSURLIsRegularFileKey] boolValue]) kind=@"file";
                } @catch(NSException *exception) { /* Do not serialize provider errors. */ }
            }
            NSMutableDictionary *item=[candidate mutableCopy]; item[@"kind"]=kind;
            if([kind isEqual:@"file"] && files<2) { files++; [chosen addObject:item]; }
            else if([kind isEqual:@"folder"] && folders<1) { folders++; [chosen addObject:item]; }
            else if([kind isEqual:@"unknown"]) [unknown addObject:item];
            if(files==2 && folders==1) break;
        }
        for(NSDictionary *item in unknown) { if(chosen.count>=3) break; [chosen addObject:item]; }
        dispatch_async(dispatch_get_main_queue(),^{
            if(container.closing || !container.viewIfLoaded.window || Get(FPFull(pane),@"currentItemCollectionViewController")!=controller || container.presentedViewController) { FPLayoutBusy=NO; return; }
            NSMutableArray *cells=[NSMutableArray new]; NSUInteger stale=0;
            for(NSDictionary *item in chosen) {
                UICollectionViewCell *cell=item[@"cell"]; UICollectionView *collection=item[@"collection"];
                if(!cell.window || ![collection.visibleCells containsObject:cell] || ![[collection indexPathForCell:cell] isEqual:item[@"indexPath"]]) { stale++; continue; }
                @try {
                    UIView *thumbnail=nil; NSURL *url=FPLURL(cell,&thumbnail);
                    if((thumbnail ?: NSNull.null)!=item[@"thumbnail"] || ![(url ?: NSNull.null) isEqual:item[@"url"]]) { stale++; continue; }
                    [cells addObject:FPLCell(cell,item[@"kind"])];
                } @catch(NSException *exception) { [cells addObject:@{@"kind":item[@"kind"],@"status":@"capture_exception_redacted"}]; }
            }
            if(!cells.count) { FPLayoutBusy=NO; container.navigationItem.prompt=@"列表已变化或无法分类；没有报告，请保持目录后重试"; return; }
            NSDictionary *snapshot=@{@"schema":@"files-dualpane-layout-0.7.10",@"pane":@(paneIndex),@"capture":@"explicit_once_read_only",@"cellLocalIDs":@YES,@"zeroID":@"nil_or_budget_exhausted",@"metadata":@"background_directory_regular_symlink_flags_only",@"candidates":@(candidates.count),@"staleSkipped":@(stale),@"discoveryTruncated":@(truncated),@"limits":@{@"cells":@3,@"viewsPerCell":@100,@"constraintsPerCell":@500,@"inspectionPerCell":@2000,@"objectsPerCell":@400,@"visibleMetadataCandidates":@24},@"cells":cells};
            // Capture is complete before any sheet is presented. JSON sees only anonymous values.
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
                NSData *data=[NSJSONSerialization dataWithJSONObject:snapshot options:NSJSONWritingPrettyPrinted error:nil];
                NSString *text=data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
                dispatch_async(dispatch_get_main_queue(),^{ FPLayoutBusy=NO; if(text.length) { FPLayoutLastReport=text; FPLShow(container); } else container.navigationItem.prompt=@"编码失败，未保留报告"; });
            });
        });
    });
}
// Same dismissal boundary as 0.6.1: only UIKit dismisses the confirmation, never its host.
static void FPLAfterConfirmation(FPDualContainer *container, UIAlertController *alert, NSUInteger index, NSUInteger remaining) {
    if(alert.viewIfLoaded.window || alert.presentingViewController || container.presentedViewController || container.transitionCoordinator) {
        if(!remaining) { FPLayoutBusy=NO; return; }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC/20),dispatch_get_main_queue(),^{ FPLAfterConfirmation(container,alert,index,remaining-1); }); return;
    }
    @try { FPLCapture(container,index); } @catch(NSException *exception) { FPLayoutBusy=NO; }
}
static void FPOfferLayoutCapture(FPDualContainer *container, NSUInteger index) {
    if(FPLayoutBusy || container.presentedViewController || container.closing || !container.viewIfLoaded.window) return;
    if(FPLayoutLastReport) { FPLShow(container); return; }
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"可选：采集当前列表布局" message:@"请停留在普通文件和文件夹都可见的目录。本次只读最多 2 个文件和 1 个文件夹的布局；最多检查 24 个可见项目的类型元数据。不读取文件内容或图片，不导出名称、路径、URL、账号和日期文本。只在本进程保留一次报告，不自动上传、保存或复制。此包只诊断，尚未修复右空位。" preferredStyle:UIAlertControllerStyleAlert];
    __weak UIAlertController *weakAlert=alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"只读采集一次" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        if(FPLayoutBusy || FPLayoutLastReport) return; FPLayoutBusy=YES;
        UIAlertController *confirmation=weakAlert;
        dispatch_async(dispatch_get_main_queue(),^{ FPLAfterConfirmation(container,confirmation,index,60); });
    }]];
    [container presentViewController:alert animated:YES completion:nil];
}
static void FPReopenLayoutReport(FPDualContainer *container) { FPLShow(container); }
