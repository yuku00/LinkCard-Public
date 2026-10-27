#import <Foundation/Foundation.h>
#import "Metadata.h"
#include <assert.h>

@protocol MPFixtureParent
@required
- (BOOL)complete:(id)item;
@optional
+ (id)optionalFactory:(id)parent;
@end
@protocol MPFixtureChild <MPFixtureParent>
@property(nonatomic,readonly) id senderAddress;
@end
@interface MPFixtureBase : NSObject <MPFixtureChild>
@end
@implementation MPFixtureBase
- (BOOL)complete:(id)item { abort(); }
- (id)senderAddress { abort(); }
@end
@interface MPFixtureDerived : MPFixtureBase
- (id)createMailbox:(id)parent completion:(void (^)(BOOL))completion;
@end
@implementation MPFixtureDerived
- (id)createMailbox:(id)parent completion:(void (^)(BOOL))completion { abort(); }
@end
int main(void) { @autoreleasepool {
    assert(MPAllowed(@"com.apple.mobilemail",@"20G75"));
    assert(!MPAllowed(@"com.apple.mobilemail",@"20G81"));
    assert(!MPAllowed(@"com.apple.DocumentsApp",@"20G75"));
    assert(MPRelevant(@"MessageListSelectionModel")); assert(MPRelevant(@"NativeOperationQueue")); assert(!MPRelevant(@"UnrelatedView"));
    NSDictionary *report=MPMetadata(@[@"MPFixtureDerived"],@[]);
    NSDictionary *classes=report[@"classes"], *protocols=report[@"protocols"];
    assert(classes[@"MPFixtureDerived"] && classes[@"MPFixtureBase"] && classes[@"NSObject"]);
    assert(protocols[@"MPFixtureChild"] && protocols[@"MPFixtureParent"]);
    assert([protocols[@"MPFixtureChild"][@"inherits"] containsObject:@"MPFixtureParent"]);
    assert([protocols[@"MPFixtureParent"][@"optionalClass"][@"methods"] count]==1);
    BOOL found=NO;
    for(NSDictionary *m in classes[@"MPFixtureDerived"][@"instanceMethods"]) if([m[@"selector"] isEqual:@"createMailbox:completion:"]) {
        found=YES; assert([m[@"argumentsIncludingSelfCmd"] count]==4);
        assert([m[@"argumentsIncludingSelfCmd"][3] isEqual:@"@?"]);
    }
    assert(found); assert([report[@"metadataTruncated"] isEqual:@NO]);
    NSData *json=[NSJSONSerialization dataWithJSONObject:report options:0 error:NULL]; assert(json.length>0);
    puts("PASS: build gate, candidate scope, full ancestors, inherited required/optional protocols, block ABI, JSON; no fixture getter/action invoked");
} return 0; }
