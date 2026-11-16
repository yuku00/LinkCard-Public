#ifndef WU_NEO_SETTINGS_H
#define WU_NEO_SETTINGS_H
#import <UIKit/UIKit.h>

static inline UIColor *WUNeoAccentColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle==UIUserInterfaceStyleDark
            ? [UIColor colorWithRed:0.30 green:0.88 blue:0.56 alpha:1]
            : [UIColor colorWithRed:0.00 green:0.46 blue:0.25 alpha:1];
    }];
}

// Explicitly opt in plugin-owned controllers. Never use UIAppearance or host hooks.
static inline void WUNeoPreparePage(UIViewController *owner) {
    owner.view.backgroundColor=UIColor.systemGroupedBackgroundColor;
    owner.view.tintColor=WUNeoAccentColor();
    owner.navigationItem.largeTitleDisplayMode=UINavigationItemLargeTitleDisplayModeNever;
    UINavigationBarAppearance *appearance=[UINavigationBarAppearance new];
    [appearance configureWithOpaqueBackground];
    appearance.backgroundColor=UIColor.systemGroupedBackgroundColor;
    appearance.shadowColor=UIColor.clearColor;
    appearance.titleTextAttributes=@{NSForegroundColorAttributeName:UIColor.labelColor,
        NSFontAttributeName:[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline]};
    // Per-item appearances leave the shared host navigation bar untouched on return.
    owner.navigationItem.standardAppearance=appearance;
    owner.navigationItem.scrollEdgeAppearance=appearance;
    owner.navigationItem.compactAppearance=appearance;
    owner.navigationItem.compactScrollEdgeAppearance=appearance;
}

static inline void WUNeoPrepareTable(UITableViewController *owner) {
    WUNeoPreparePage(owner);
    // Plain tables do not wrap an entire section in a single rounded clipping view.
    // Every caller invokes this immediately after super viewDidLoad, before setup.
    if (owner.tableView.style != UITableViewStylePlain) {
        UITableView *oldTable=owner.tableView;
        UITableView *plain=[[UITableView alloc] initWithFrame:oldTable.frame style:UITableViewStylePlain];
        plain.autoresizingMask=oldTable.autoresizingMask;
        owner.tableView=plain;
        plain.dataSource=owner;
        plain.delegate=owner;
    }
    UITableView *table=owner.tableView;
    table.backgroundColor=UIColor.systemGroupedBackgroundColor;
    table.rowHeight=UITableViewAutomaticDimension;
    table.estimatedRowHeight=72;
    table.cellLayoutMarginsFollowReadableWidth=YES;
    table.separatorStyle=UITableViewCellSeparatorStyleNone;
    table.sectionHeaderTopPadding=16;
}

static inline UIView *WUNeoCardBackground(UIColor *color) {
    UIView *container=[[UIView alloc] initWithFrame:CGRectMake(0,0,320,80)];
    container.backgroundColor=UIColor.clearColor;
    UIView *card=[[UIView alloc] initWithFrame:CGRectInset(container.bounds,16,4)];
    card.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    card.backgroundColor=color;
    card.layer.cornerRadius=16;
    card.layer.cornerCurve=kCACornerCurveContinuous;
    card.userInteractionEnabled=NO;
    [container addSubview:card];
    return container;
}

static inline UITableViewCell *WUNeoCell(UITableViewCell *cell, NSString *symbol) {
    // The cell and its selected state each own a complete, independently rounded card.
    cell.backgroundConfiguration=nil;
    cell.backgroundColor=UIColor.clearColor;
    cell.backgroundView=WUNeoCardBackground(UIColor.secondarySystemGroupedBackgroundColor);
    cell.selectedBackgroundView=WUNeoCardBackground(UIColor.tertiarySystemFillColor);
    cell.directionalLayoutMargins=NSDirectionalEdgeInsetsMake(14,34,14,34);
    // Keep a short row rectangular without constraining larger Dynamic Type rows.
    if (![cell.contentView.constraints filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"identifier == %@", @"WUNeoMinimumRowHeight"]].count) {
        NSLayoutConstraint *minimum=[cell.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:64];
        minimum.identifier=@"WUNeoMinimumRowHeight";
        minimum.priority=999;
        minimum.active=YES;
    }
    cell.tintColor=WUNeoAccentColor();
    if(symbol.length) cell.textLabel.font=[UIFontMetrics.defaultMetrics scaledFontForFont:[UIFont systemFontOfSize:17 weight:UIFontWeightSemibold]];
    cell.textLabel.adjustsFontForContentSizeCategory=YES;
    cell.textLabel.numberOfLines=0;
    cell.detailTextLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    cell.detailTextLabel.adjustsFontForContentSizeCategory=YES;
    cell.detailTextLabel.numberOfLines=0;
    cell.detailTextLabel.textColor=UIColor.secondaryLabelColor;
    // Existing thumbnails, checkmarks, accessory controls and disabled text survive.
    if(symbol.length && !cell.imageView.image) {
        UIImage *glyph=[UIImage systemImageNamed:symbol withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightMedium]];
        if(glyph) {
            // Pad the template itself so UIKit reserves space for the colored tile.
            UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(34,34)];
            UIImage *tile=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
                [glyph drawInRect:CGRectMake(7,7,20,20)];
            }];
            cell.imageView.image=[tile imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            UIColor *color=WUNeoAccentColor();
            if([symbol containsString:@"paint"] || [symbol containsString:@"photo"]) color=UIColor.systemIndigoColor;
            else if([symbol containsString:@"wave"] || [symbol containsString:@"music"]) color=UIColor.systemBlueColor;
            else if([symbol containsString:@"gear"] || [symbol containsString:@"slider"]) color=UIColor.systemOrangeColor;
            cell.imageView.tintColor=color;
            cell.imageView.backgroundColor=[color colorWithAlphaComponent:0.12];
            cell.imageView.layer.cornerRadius=9;
            cell.imageView.clipsToBounds=YES;
            cell.imageView.isAccessibilityElement=NO;
        }
    }
    // UIKit's built-in subtitle labels do not supply a reliable multiline sizing chain.
    // Keep their values for callers, and display equivalent self-sizing plugin-owned views.
    UILabel *originalTitle=cell.textLabel, *originalDetail=cell.detailTextLabel;
    if(originalTitle.text.length) {
        UILabel *title=[UILabel new], *detail=[UILabel new];
        title.text=originalTitle.text; title.font=originalTitle.font; title.textColor=originalTitle.textColor;
        title.textAlignment=originalTitle.textAlignment; title.enabled=originalTitle.enabled;
        title.numberOfLines=0; title.adjustsFontForContentSizeCategory=YES;
        title.accessibilityIdentifier=@"WUNeoTitle";
        detail.text=originalDetail.text; detail.font=originalDetail.font; detail.textColor=originalDetail.textColor;
        detail.numberOfLines=0; detail.adjustsFontForContentSizeCategory=YES;
        detail.accessibilityIdentifier=@"WUNeoDetail";
        UIStackView *text=[[UIStackView alloc] initWithArrangedSubviews:@[title,detail]];
        text.axis=UILayoutConstraintAxisVertical; text.spacing=3;
        detail.hidden=!detail.text.length;
        UIStackView *content=[[UIStackView alloc] init];
        content.axis=UILayoutConstraintAxisHorizontal; content.alignment=UIStackViewAlignmentCenter; content.spacing=12;
        content.translatesAutoresizingMaskIntoConstraints=NO;
        UIImageView *originalImage=cell.imageView;
        if(originalImage.image) {
            UIImageView *image=[[UIImageView alloc] initWithImage:originalImage.image];
            image.contentMode=originalImage.contentMode; image.tintColor=originalImage.tintColor;
            image.backgroundColor=originalImage.backgroundColor; image.layer.cornerRadius=originalImage.layer.cornerRadius;
            image.clipsToBounds=originalImage.clipsToBounds; image.isAccessibilityElement=NO;
            CGFloat side=originalImage.backgroundColor ? 34 : 80;
            [NSLayoutConstraint activateConstraints:@[[image.widthAnchor constraintEqualToConstant:side], [image.heightAnchor constraintEqualToConstant:side]]];
            [content addArrangedSubview:image]; originalImage.hidden=YES;
        }
        [content addArrangedSubview:text]; [cell.contentView addSubview:content];
        [NSLayoutConstraint activateConstraints:@[
            [content.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:34],
            [content.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-34],
            [content.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:14],
            [content.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-14]
        ]];
        originalTitle.hidden=YES; originalDetail.hidden=YES;
    }
    if([cell.accessoryView isKindOfClass:UISwitch.class]) {
        UISwitch *toggle=(UISwitch *)cell.accessoryView;
        toggle.onTintColor=WUNeoAccentColor();
        if(!toggle.accessibilityLabel.length) toggle.accessibilityLabel=cell.textLabel.text;
        if(!toggle.accessibilityHint.length) toggle.accessibilityHint=cell.detailTextLabel.text;
    }
    return cell;
}
// A full top-to-bottom constraint chain lets UITableView measure multiline rows.
static inline void WUNeoSubtitleContent(UITableViewCell *cell, UILabel **titleOut, UILabel **detailOut, UIImageView **iconOut) {
    UILabel *title=[UILabel new], *detail=[UILabel new];
    title.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    detail.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    title.adjustsFontForContentSizeCategory=YES; detail.adjustsFontForContentSizeCategory=YES;
    title.numberOfLines=0; detail.numberOfLines=0; detail.textColor=UIColor.secondaryLabelColor;
    UIStackView *text=[[UIStackView alloc] initWithArrangedSubviews:@[title,detail]];
    text.axis=UILayoutConstraintAxisVertical; text.spacing=3; text.translatesAutoresizingMaskIntoConstraints=NO;
    UIImageView *icon=[UIImageView new]; icon.translatesAutoresizingMaskIntoConstraints=NO;
    icon.contentMode=UIViewContentModeScaleAspectFit; icon.isAccessibilityElement=NO;
    [cell.contentView addSubview:icon]; [cell.contentView addSubview:text];
    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:34],
        [icon.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:22], [icon.heightAnchor constraintEqualToConstant:22],
        [text.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:12],
        [text.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-34],
        [text.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:14],
        [text.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-14]
    ]];
    *titleOut=title; *detailOut=detail; *iconOut=icon;
}

#endif
