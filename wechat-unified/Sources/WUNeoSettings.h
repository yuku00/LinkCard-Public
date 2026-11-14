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
    UITableView *table=owner.tableView;
    table.rowHeight=UITableViewAutomaticDimension;
    table.estimatedRowHeight=72;
    table.cellLayoutMarginsFollowReadableWidth=YES;
    table.separatorStyle=UITableViewCellSeparatorStyleNone;
    table.sectionHeaderTopPadding=16;
}

static inline UITableViewCell *WUNeoCell(UITableViewCell *cell, NSString *symbol) {
    // A clear configuration avoids the grouped-cell joined-corner treatment.
    // Vertical insets leave a visible gap while the full row remains tappable.
    UIBackgroundConfiguration *background=[UIBackgroundConfiguration clearConfiguration];
    background.backgroundColor=UIColor.secondarySystemGroupedBackgroundColor;
    background.backgroundInsets=NSDirectionalEdgeInsetsMake(4,0,4,0);
    background.cornerRadius=20;
    cell.backgroundConfiguration=background;
    cell.directionalLayoutMargins=NSDirectionalEdgeInsetsMake(14,18,14,18);
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
