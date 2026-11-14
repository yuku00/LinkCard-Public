// The macOS hook harness uses a deliberately minimal UIKit, not the iOS SDK.
#ifndef WU_NEO_SETTINGS_H
#define WU_NEO_SETTINGS_H
#import <UIKit/UIKit.h>
static inline void WUNeoPrepareTable(UITableViewController *owner) { (void)owner; }
static inline UITableViewCell *WUNeoCell(UITableViewCell *cell, NSString *symbol) {
    (void)symbol;
    return cell;
}
#endif
