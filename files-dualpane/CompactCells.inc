// Layout policy is shared with the host regression fixture.
static NSInteger FPNameLines(CGFloat availableHeight, CGFloat lineHeight) {
    return availableHeight>=2*lineHeight ? 2 : 1;
}
static CGFloat FPCompactRowHeight(CGFloat nameLine, CGFloat detailLine) {
    return MAX(44,ceil(2*nameLine+detailLine+8));
}
static char CellStyleKey, FPCellResettingKey;
static BOOL IsPaneListCell(UICollectionViewCell *cell) {
    if(objc_getAssociatedObject(cell,&FPCellResettingKey) || !PaneForResponder(cell)) return NO;
    UICollectionView *collection=nil;
    for(UIView *v=cell.superview;v;v=v.superview) if([v isKindOfClass:UICollectionView.class]) { collection=(id)v; break; }
    if(!collection || !InExperiment(collection.delegate)) return NO;
    id controller=collection.delegate; SEL list=NSSelectorFromString(@"accessibilityIsInListMode");
    if(!ABI([controller class],NSStringFromSelector(list),"B@:") || !((BOOL(*)(id,SEL))[controller methodForSelector:list])(controller,list)) return NO;
    return cell.bounds.size.width>=collection.bounds.size.width*0.75;
}
static UIFont *FPCellFont(UIView *view, CGFloat size) {
    return [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody] scaledFontForFont:[UIFont systemFontOfSize:size] compatibleWithTraitCollection:view.traitCollection];
}
static void StyleCell(UICollectionViewCell *cell, BOOL compact) {
    NSDictionary *saved=objc_getAssociatedObject(cell,&CellStyleKey);
    FPSelectionVisual(cell,compact);
    FPContentMargins(cell,compact);
    BOOL arranged=FPCompactImages(cell.contentView,compact);
    if(!compact) {
        if(saved[@"config"] && [cell.contentConfiguration isKindOfClass:UIListContentConfiguration.class]) {
            UIListContentConfiguration *config=[(UIListContentConfiguration *)cell.contentConfiguration copy], *original=saved[@"config"];
            config.textProperties.font=original.textProperties.font; config.textProperties.numberOfLines=original.textProperties.numberOfLines;
            config.textProperties.lineBreakMode=original.textProperties.lineBreakMode;
            config.secondaryTextProperties.font=original.secondaryTextProperties.font;
            config.secondaryTextProperties.numberOfLines=original.secondaryTextProperties.numberOfLines;
            config.imageProperties.maximumSize=original.imageProperties.maximumSize;
            config.imageProperties.reservedLayoutSize=original.imageProperties.reservedLayoutSize;
            config.axesPreservingSuperviewLayoutMargins=original.axesPreservingSuperviewLayoutMargins;
            config.directionalLayoutMargins=original.directionalLayoutMargins; config.imageToTextPadding=original.imageToTextPadding;
            cell.contentConfiguration=config;
        }
        for(NSDictionary *entry in saved[@"labels"]) {
            UILabel *label=entry[@"label"]; label.font=entry[@"font"]; label.numberOfLines=[entry[@"lines"] integerValue];
            label.lineBreakMode=[entry[@"break"] integerValue]; label.clipsToBounds=[entry[@"clips"] boolValue];
        }
        if(saved) cell.contentView.clipsToBounds=[saved[@"clips"] boolValue];
        objc_setAssociatedObject(cell,&CellStyleKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC); return;
    }
    UIFont *font=FPCellFont(cell,13), *detail=FPCellFont(cell,11);
    if([cell.contentConfiguration isKindOfClass:UIListContentConfiguration.class]) {
        UIListContentConfiguration *config=[(UIListContentConfiguration *)cell.contentConfiguration copy];
        if(!saved) { saved=@{@"config":[config copy],@"clips":@(cell.contentView.clipsToBounds)}; objc_setAssociatedObject(cell,&CellStyleKey,saved,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        NSInteger lines=FPNameLines(MAX(0,cell.bounds.size.height-detail.lineHeight-8),font.lineHeight);
        if(config.textProperties.numberOfLines!=lines || ![config.textProperties.font isEqual:font] || config.imageProperties.maximumSize.width!=20 || config.imageProperties.reservedLayoutSize.width!=20 || config.imageToTextPadding!=6 || config.axesPreservingSuperviewLayoutMargins!=0 || !NSDirectionalEdgeInsetsEqualToDirectionalEdgeInsets(config.directionalLayoutMargins,NSDirectionalEdgeInsetsMake(4,6,4,6))) {
            config.textProperties.font=font; config.textProperties.numberOfLines=lines; config.textProperties.lineBreakMode=NSLineBreakByTruncatingTail;
            config.secondaryTextProperties.font=detail; config.secondaryTextProperties.numberOfLines=1;
            config.imageProperties.maximumSize=CGSizeMake(20,20); config.imageProperties.reservedLayoutSize=CGSizeMake(20,20); config.imageToTextPadding=6;
            config.axesPreservingSuperviewLayoutMargins=0;
            config.directionalLayoutMargins=NSDirectionalEdgeInsetsMake(4,6,4,6); cell.contentConfiguration=config;
        }
        cell.contentView.clipsToBounds=YES; return;
    }
    NSMutableArray<UILabel *> *labels=[NSMutableArray new]; CollectLabels(cell.contentView,labels);
    UILabel *name=nil; CGFloat top=CGFLOAT_MAX;
    for(UILabel *label in labels) {
        CGRect frame=[label convertRect:label.bounds toView:cell.contentView];
        if(label.text.length && frame.size.width>40 && frame.origin.y<top) { name=label; top=frame.origin.y; }
    }
    if(!name) return;
    if(!saved) {
        NSMutableArray *entries=[NSMutableArray new];
        for(UILabel *label in labels) [entries addObject:@{@"label":label,@"font":label.font,@"lines":@(label.numberOfLines),@"break":@(label.lineBreakMode),@"clips":@(label.clipsToBounds)}];
        saved=@{@"labels":entries,@"clips":@(cell.contentView.clipsToBounds)}; objc_setAssociatedObject(cell,&CellStyleKey,saved,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    cell.contentView.clipsToBounds=YES;
    if(arranged) {
        // Native stack owns label frames; shrinking its thumbnail slot reclaims leading space.
        // Do not fight its constraints by overwriting individual label frames after layout.
        CGFloat available=MAX(0,cell.bounds.size.height-8-(labels.count>1 ? detail.lineHeight : 0));
        for(UILabel *label in labels) {
            label.font=label==name ? font : detail;
            label.numberOfLines=label==name ? FPNameLines(available,font.lineHeight) : 1;
            label.lineBreakMode=NSLineBreakByTruncatingTail; label.clipsToBounds=YES;
        }
        return;
    }
    // Native fixed-height layouts may reject self-sizing. Never add lines beyond actual bounds.
    CGRect frame=[name convertRect:name.bounds toView:cell.contentView];
    CGFloat left=MIN(frame.origin.x,34), width=MAX(0,cell.contentView.bounds.size.width-left-6);
    CGFloat available=MAX(0,cell.contentView.bounds.size.height-8-(labels.count>1 ? detail.lineHeight : 0));
    name.font=font; name.numberOfLines=FPNameLines(available,font.lineHeight); name.lineBreakMode=NSLineBreakByTruncatingTail; name.clipsToBounds=YES;
    CGRect nameFrame=CGRectMake(left,4,width,MIN(available,name.numberOfLines*font.lineHeight));
    name.frame=[cell.contentView convertRect:nameFrame toView:name.superview];
    CGFloat y=CGRectGetMaxY(nameFrame)+1;
    for(UILabel *label in labels) if(label!=name) {
        CGRect old=[label convertRect:label.bounds toView:cell.contentView];
        label.font=detail; label.numberOfLines=1; label.lineBreakMode=NSLineBreakByTruncatingTail; label.clipsToBounds=YES;
        // Keep native secondary columns separate; clamp to the row instead of overlapping the name.
        CGFloat x=labels.count==2 ? left : MAX(left,old.origin.x);
        CGFloat w=labels.count==2 ? width : MIN(old.size.width,MAX(0,cell.contentView.bounds.size.width-x-6));
        label.frame=[cell.contentView convertRect:CGRectMake(x,y,w,MAX(0,MIN(detail.lineHeight,cell.contentView.bounds.size.height-y-3))) toView:label.superview];
    }
}
static void ImproveCell(UICollectionViewCell *cell) { StyleCell(cell,IsPaneListCell(cell)); }
