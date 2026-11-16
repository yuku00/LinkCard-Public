#import <Foundation/Foundation.h>

// Availability means ABI hook installed, NOT every realm/ad supported.
void WUInstallMiniAds(void);
BOOL WUMiniAdsAvailable(NSString *key);
unsigned WUMiniAdsDiagnostics(void);
NSString *WUMiniAdsStatus(void);
