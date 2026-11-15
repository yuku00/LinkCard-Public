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
    if([cell.accessoryView isKindOfClass:UISwitch.class]) {
        UISwitch *toggle=(UISwitch *)cell.accessoryView;
        toggle.onTintColor=WUNeoAccentColor();
        if(!toggle.accessibilityLabel.length) toggle.accessibilityLabel=cell.textLabel.text;
        if(!toggle.accessibilityHint.length) toggle.accessibilityHint=cell.detailTextLabel.text;
    }
    return cell;
}
#endif
