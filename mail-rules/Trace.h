#import <Foundation/Foundation.h>
#define MRD_VERSION @"0.5.1"
#define MRD_BUILD @"mail051-trace-r2"
FOUNDATION_EXPORT BOOL MRDActive(void);
FOUNDATION_EXPORT NSUInteger MRDSession(void);
FOUNDATION_EXPORT void MRDStart(void);
FOUNDATION_EXPORT void MRDStop(void);
FOUNDATION_EXPORT void MRDClear(void);
FOUNDATION_EXPORT void MRDTag(NSString *tag);
FOUNDATION_EXPORT BOOL MRDCanSubmit(void);
// Shared production boundary; stamped panels remain blocked after stopping a session.
FOUNDATION_EXPORT BOOL MRDRequireSubmit(NSString *stage,id object,BOOL stampedDryRun);
FOUNDATION_EXPORT void MRDAllowTestSubmit(BOOL allow);
FOUNDATION_EXPORT void MRD(NSString *stage,NSString *status,NSString *reason,id object,NSDictionary *fields);
FOUNDATION_EXPORT void MRDAt(NSUInteger session,NSString *stage,NSString *status,NSString *reason,id object,NSDictionary *fields);
FOUNDATION_EXPORT NSNumber *MRDAccount(NSString *identity);
FOUNDATION_EXPORT NSDictionary *MRDABIFields(NSString *selector,const char *expected,const char *actual);
FOUNDATION_EXPORT NSDictionary *MRDError(NSError *error);
FOUNDATION_EXPORT void MRDAST(NSPredicate *predicate);
FOUNDATION_EXPORT NSDictionary *MRDSnapshot(void);
FOUNDATION_EXPORT NSString *MRDText(NSDictionary *snapshot);
FOUNDATION_EXPORT void MRDDeclare(NSString *stage,NSString *selector,const char *expected,const char *actual,BOOL installed);
FOUNDATION_EXPORT void MRDInstallButton(id controller);
FOUNDATION_EXPORT void MRDControl(NSString *status,NSString *reason,NSString *path);
FOUNDATION_EXPORT void MRDShareError(NSError *error);
