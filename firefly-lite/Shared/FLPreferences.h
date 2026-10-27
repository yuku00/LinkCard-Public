#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import "FLLogic.h"
#define FL_DOMAIN CFSTR("dev.fireflylite.badgeglow")
#define FL_CHANGED CFSTR("dev.fireflylite.badgeglow/changed")
#define FL_STOP CFSTR("dev.fireflylite.badgeglow/uninstall")
typedef struct { BOOL enabled, allApps; double red, green, blue, intensity; } FLConfig;
FOUNDATION_EXPORT FLConfig FLReadConfig(void);
FOUNDATION_EXPORT BOOL FLWriteConfig(FLConfig config);
FOUNDATION_EXPORT BOOL FLClearPreferences(void);
FOUNDATION_EXPORT BOOL FLHasBadge(id badge);
