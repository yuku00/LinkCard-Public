#import <Foundation/Foundation.h>
#import "Diagnostics.h"
int main(void) { @autoreleasepool {
    assert(!MRDiagnosticActive());
    MRDiagnosticStart();
    NSPredicate *p=[NSPredicate predicateWithFormat:@"subject == %@",@"secret@fixture.invalid"];
    MRDiagnosticRecord(@"fixture",@{@"ast":MRPredicateShape(p)});
    NSPredicate *unknown=[NSComparisonPredicate predicateWithLeftExpression:[NSExpression expressionForKeyPath:@"private_fixture_key"] rightExpression:[NSExpression expressionForConstantValue:@"private_fixture_value"] modifier:NSDirectPredicateModifier type:NSEqualToPredicateOperatorType options:0];
    MRDiagnosticRecord(@"fixture",@{@"ast":MRPredicateShape(unknown)});
    for(NSUInteger i=0;i<80;i++) MRDiagnosticRecord(@"bounded",@{});
    NSString *report=MRDiagnosticExport();
    assert(!MRDiagnosticActive());
    for(NSString *secret in @[@"secret@fixture.invalid",@"private_fixture_key",@"private_fixture_value"]) assert(![report containsString:secret]);
    NSDictionary *json=[NSJSONSerialization JSONObjectWithData:[report dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
    assert([json[@"events"] count]==60);
    MRDiagnosticRecord(@"after-stop",@{});
    assert(![MRDiagnosticExport() containsString:@"after-stop"]);
    MRDiagnosticStart();
    NSDictionary *reset=[NSJSONSerialization JSONObjectWithData:[MRDiagnosticExport() dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
    assert([reset[@"events"] count]==0);
    puts("PASS: diagnostic redaction, event limit, stop and reset");
} return 0; }
