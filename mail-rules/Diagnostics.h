#import <Foundation/Foundation.h>
void MRDiagnosticStart(void);
BOOL MRDiagnosticActive(void);
void MRDiagnosticRecord(NSString *event, NSDictionary *values);
NSDictionary *MRPredicateShape(NSPredicate *predicate);
NSString *MRDiagnosticExport(void);
